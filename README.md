Hello Eyego - Node.js Application Deployment
This project deploys a simple Node.js application (hello-eyego) to AWS Elastic Kubernetes Service (EKS) using a Jenkins CI/CD pipeline. The infrastructure is provisioned with Terraform, and the pipeline builds a Docker image, pushes it to Amazon Elastic Container Registry (ECR), and deploys it to an EKS cluster. The project also supports migration to Google Cloud Platform (GCP) Google Kubernetes Engine (GKE).
Project Structure

src/: Node.js application code (index.js, package.json).
Dockerfile: Docker configuration for building the application image.
kubernetes/: Kubernetes manifests (deployment.yaml, service.yaml) for EKS/GKE deployment.
terraform/: Terraform configuration for AWS infrastructure (main.tf).
Jenkinsfile: Jenkins pipeline script for CI/CD.
README.md: This file.

Prerequisites
AWS

AWS Account: Active account with IAM permissions for EKS, ECR, EC2, VPC, and IAM.
AWS CLI: Installed and configured (aws configure).
Terraform: Installed (v1.5.0 or later).
kubectl: Installed for Kubernetes management.
GitHub Repository: https://github.com/M-Samii/eyego.git (branch: master).
SSH Key Pair: Named hello-eyego-jenkins-key in AWS EC2 (us-east-1).
Jenkins Plugins:
Docker
Docker Pipeline
Docker Commons
AWS Credentials
Kubernetes CLI



GCP (for Migration)

GCP Account: Active project with billing enabled.
GCP CLI (gcloud): Installed and configured (gcloud init).
Google Service Account: JSON key for authentication.

Setup on AWS
1. Clone the Repository
git clone https://github.com/M-Samii/eyego.git
cd eyego

2. Iaac

Navigate to the Terraform directory:cd terraform


Initialize Terraform:terraform init


Validate the configuration:terraform validate


Apply the configuration:terraform apply



3. Configure Jenkins

Access Jenkins:
Get the public IP: terraform output -raw jenkins_public_ip.
Open http://<jenkins_public_ip>:8080 in a browser.
Retrieve the initial admin password:ssh -i hello-eyego-jenkins-key.pem ec2-user@<jenkins_public_ip> 'sudo cat /var/lib/jenkins/secrets/initialAdminPassword'




Install required plugins:
Manage Jenkins → Manage Plugins → Available Plugins.
Install: Docker, Docker Pipeline, Docker Commons, AWS Credentials, Kubernetes CLI.


Add AWS credentials:
Manage Jenkins → Manage Credentials → (global) → Add Credentials.
Kind: AWS Credentials.
ID: aws-credentials.
Enter AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY with permissions:


4. Configure Jenkins Pipeline

Create a new pipeline job:
New Item → Pipeline → Name: hello-eyego-pipeline.
SCM: Git.
Repository URL: https://github.com/M-Samii/eyego.git.
Branch: master.
Script Path: Jenkinsfile.


5. Run the Pipeline

Trigger the pipeline:
In Jenkins: Build Now.
Or push changes to GitHub to trigger via webhook.

6. Verify Deployment

Check EKS pods and services:aws eks update-kubeconfig --region us-east-1 --name hello-eyego-cluster
kubectl get pods
kubectl get svc


Note the EXTERNAL-IP of hello-eyego-service.
Test the application:curl http://<EXTERNAL-IP>/api


Expected output: {"message":"Hello Eyego"}



Migrating to GCP GKE
1. Create Terraform Configuration for GKE
Create terraform/gke.tf:
provider "google" {
  project = var.gcp_project_id
  region  = var.region
}

resource "google_container_cluster" "hello_eyego" {
  name               = "hello-eyego-cluster"
  location           = var.region
  initial_node_count = 2
  node_config {
    machine_type = "e2-micro"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

resource "google_artifact_registry_repository" "hello_eyego" {
  location      = var.region
  repository_id = "hello-eyego"
  format        = "DOCKER"
}

variable "gcp_project_id" {
  description = "GCP project ID"
}

variable "region" {
  description = "GCP region"
  default     = "us-central1"
}

2. Apply Terraform Configuration

Initialize Terraform:cd terraform
terraform init


Apply:terraform apply -var="gcp_project_id=<your-project-id>"


Replace <your-project-id> with your GCP project ID.
Confirm with yes.



3. Update Jenkinsfile for GKE
Update Jenkinsfile to deploy to GKE:
pipeline {
    agent any
    environment {
        GCR_REGISTRY = 'us-central1-docker.pkg.dev/<your-project-id>/hello-eyego'
        IMAGE_TAG = 'latest'
    }
    stages {
        stage('Checkout') {
            steps {
                git branch: 'master', url: 'https://github.com/M-Samii/eyego.git'
            }
        }
        stage('Build Docker Image') {
            steps {
                script {
                    dockerImage = docker.build("${GCR_REGISTRY}:${IMAGE_TAG}")
                }
            }
        }
        stage('Push to GCR') {
            steps {
                withCredentials([file(credentialsId: 'gcp-credentials', variable: 'GOOGLE_APPLICATION_CREDENTIALS')]) {
                    sh """
                        gcloud auth configure-docker us-central1-docker.pkg.dev
                        docker push ${GCR_REGISTRY}:${IMAGE_TAG}
                    """
                }
            }
        }
        stage('Deploy to GKE') {
            steps {
                withCredentials([file(credentialsId: 'gcp-credentials', variable: 'GOOGLE_APPLICATION_CREDENTIALS')]) {
                    sh """
                        gcloud container clusters get-credentials hello-eyego-cluster --region us-central1
                        sed -i 's|<GCR_REGISTRY>|${GCR_REGISTRY}|g' kubernetes/deployment.yaml
                        kubectl apply -f kubernetes/deployment.yaml
                        kubectl apply -f kubernetes/service.yaml
                    """
                }
            }
        }
    }
}

4. Add GCP Credentials in Jenkins

Manage Jenkins → Manage Credentials → (global) → Add Credentials.
Kind: Google Service Account from private key.
ID: gcp-credentials.
Upload the JSON key file for your GCP service account.

5. Update Kubernetes Manifest
Update kubernetes/deployment.yaml:
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-eyego
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hello-eyego
  template:
    metadata:
      labels:
        app: hello-eyego
    spec:
      containers:
      - name: hello-eyego
        image: us-central1-docker.pkg.dev/((project-id))/hello-eyego:latest
        ports:
        - containerPort: 3000
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          requests:
            cpu: "200m"
            memory: "256Mi"

6. Run the Pipeline

Push updated files:git add Jenkinsfile kubernetes/deployment.yaml terraform/gke.tf
git commit -m "Add GKE deployment configuration"
git push origin master


Trigger the pipeline in Jenkins and monitor logs.

7. Verify Deployment

Get GKE credentials:gcloud container clusters get-credentials hello-eyego-cluster --region us-central1


Check pods and services:kubectl get pods
kubectl get svc


Note the EXTERNAL-IP of hello-eyego-service.
Test:curl http://<EXTERNAL-IP>/api


Expected output: {"message":"Hello Eyego"}
