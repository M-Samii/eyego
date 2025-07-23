pipeline {
    agent any
    environment {
        AWS_REGION = 'us-east-1'
        ECR_REGISTRY = '825736768112.dkr.ecr.us-east-1.amazonaws.com/hello-eyego'
        ECR_REPOSITORY = 'hello-eyego'
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
                    dockerImage = docker.build("${ECR_REGISTRY}:${IMAGE_TAG}")
                }
            }
        }
        stage('Push to ECR') {
            steps {
                withAWS(credentials: 'aws-credentials', region: "${AWS_REGION}") {
                    script {
                        sh "aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}"
                        dockerImage.push()
                    }
                }
            }
        }
stage('Deploy to EKS') {
    steps {
        withAWS(credentials: 'aws-credentials', region: "${AWS_REGION}") {
            sh """
                aws eks update-kubeconfig --region ${AWS_REGION} --name hello-eyego-cluster
                sed -i 's|<AWS_ECR_REGISTRY>|${ECR_REGISTRY}:latest|g' k8s/deployment.yaml
                kubectl apply -f k8s/deployment.yaml
                kubectl apply -f k8s/service.yaml
                kubectl rollout restart deployment/hello-eyego -n default

            """
        }
    }
}

    }
}