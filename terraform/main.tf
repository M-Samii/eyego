
provider "aws" {
  region = var.region
}

# Optional: S3 backend for state locking (uncomment to enable)
# terraform {
#   backend "s3" {
#     bucket         = "<your-s3-bucket>"
#     key            = "terraform/state"
#     region         = "us-east-1"
#     dynamodb_table = "terraform-locks"
#   }
# }

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "hello-eyego-vpc"
  }
}

# Subnets
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name                     = "hello-eyego-public-${count.index}"
    "kubernetes.io/role/elb" = "1"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "hello-eyego-igw"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name = "hello-eyego-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Group for Jenkins
resource "aws_security_group" "jenkins" {
  vpc_id = aws_vpc.main.id
  name   = "hello-eyego-jenkins-sg"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict to your IP in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "hello-eyego-jenkins-sg"
  }
}

# Security Group for EKS
resource "aws_security_group" "eks" {
  vpc_id = aws_vpc.main.id
  name   = "hello-eyego-eks-sg"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "hello-eyego-eks-sg"
  }
}

# IAM Role for Jenkins
resource "aws_iam_role" "jenkins_role" {
  name = "hello-eyego-jenkins-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_policy" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

resource "aws_iam_role_policy_attachment" "jenkins_eks_policy" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "hello-eyego-jenkins-profile"
  role = aws_iam_role.jenkins_role.name
}

# Jenkins EC2 Instance
resource "aws_instance" "jenkins" {
  ami                    = "ami-0cbbe2c6a1bb2ad63"
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins_profile.name
  key_name               = "hello-eyego-jenkins-key"
  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y openjdk-11-jdk docker.io
              curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io.key | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
              echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | tee /etc/apt/sources.list.d/jenkins.list
              apt-get update
              apt-get install -y jenkins
              systemctl start jenkins
              usermod -aG docker jenkins
              snap install aws-cli --classic
              snap install kubectl --classic
              systemctl restart docker
              systemctl restart jenkins
              EOF
  tags = {
    Name = "hello-eyego-jenkins"
  }
}

# ECR Repository
resource "aws_ecr_repository" "hello_eyego" {
  name = "hello-eyego"
  tags = {
    Name = "hello-eyego-ecr"
  }
}

# EKS Cluster
resource "aws_eks_cluster" "hello_eyego" {
  name     = "hello-eyego-cluster"
  role_arn = aws_iam_role.eks_role.arn
  version  = "1.30"

  vpc_config {
    subnet_ids         = aws_subnet.public[*].id
    security_group_ids = [aws_security_group.eks.id]
  }
}

# EKS Node Group
resource "aws_eks_node_group" "hello_eyego" {
  cluster_name    = aws_eks_cluster.hello_eyego.name
  node_group_name = "hello-eyego-ng"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.public[*].id
  instance_types  = [var.eks_node_instance_type]
  scaling_config {
    desired_size = 3
    max_size     = 3
    min_size     = 3
  }
  depends_on = [
    aws_eks_cluster.hello_eyego,
    aws_iam_role_policy_attachment.eks_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_policy
  ]
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_role" {
  name = "hello-eyego-eks-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_policy" {
  role       = aws_iam_role.eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# IAM Role for EKS Node Group
resource "aws_iam_role" "eks_node_role" {
  name = "hello-eyego-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Data Sources
data "aws_availability_zones" "available" {
  state = "available"
}

variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "eks_node_instance_type" {
  description = "Instance type for EKS node group"
  default     = "t2.micro"
}

output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}

output "ecr_repository_url" {
  value = aws_ecr_repository.hello_eyego.repository_url
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.hello_eyego.endpoint
}
