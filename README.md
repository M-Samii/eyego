# Hello Eyego - Node.js Application Deployment

This project deploys a simple Node.js application (**hello-eyego**) to **AWS Elastic Kubernetes Service (EKS)** using a **Jenkins CI/CD pipeline**. Infrastructure is provisioned using **Terraform**, and the pipeline builds a Docker image, pushes it to **Amazon ECR**, and deploys it to an EKS cluster.

> The project **supports migration to GCP (Google Kubernetes Engine)** for flexible, cloud-agnostic deployment.

---

## Project Structure

* `src/`: Node.js application code (`index.js`, `package.json`).
* `Dockerfile`: Docker configuration for building the application image.
* `kubernetes/`: Kubernetes manifests (`deployment.yaml`, `service.yaml`) for EKS/GKE deployment.
* `terraform/`: Terraform configuration for AWS infrastructure (`main.tf`).
* `Jenkinsfile`: Jenkins pipeline script for CI/CD.
* `README.md`: This documentation.

---

## Prerequisites

### AWS

* **AWS Account** with IAM permissions for EKS, ECR, EC2, VPC, IAM.
* **AWS CLI** configured (`aws configure`).
* **Terraform v1.5.0+**.
* **kubectl** for Kubernetes management.
* **GitHub Repository:** [https://github.com/M-Samii/eyego.git](https://github.com/M-Samii/eyego.git) (branch: `master`).
* **SSH Key Pair:** `hello-eyego-jenkins-key` in `us-east-1`.
* **Jenkins Plugins:**

  * Docker, Docker Pipeline, Docker Commons
  * AWS Credentials
  * Kubernetes CLI

### GCP (for migration)

* **GCP Account** with billing enabled.
* **GCP CLI (gcloud)** configured (`gcloud init`).
* **Google Service Account JSON key** for authentication.

---

## Setup on AWS

### 1️⃣ Clone the Repository

```bash
git clone https://github.com/M-Samii/eyego.git
cd eyego
```

### 2️⃣ Infrastructure Provisioning (IaC)

```bash
cd terraform
terraform init
terraform validate
terraform apply
```

### 3️⃣ Configure Jenkins

* **Access Jenkins:**

  * Get public IP: `terraform output -raw jenkins_public_ip`
  * Open `http://<jenkins_public_ip>:8080`
  * Retrieve admin password:

    ```bash
    ssh -i hello-eyego-jenkins-key.pem ec2-user@<jenkins_public_ip> 'sudo cat /var/lib/jenkins/secrets/initialAdminPassword'
    ```
* **Install Plugins:** Docker, Docker Pipeline, Docker Commons, AWS Credentials, Kubernetes CLI.
* **Add AWS Credentials:**

  * Manage Jenkins → Manage Credentials → (global) → Add Credentials.
  * Kind: AWS Credentials
  * ID: `aws-credentials`
  * Enter `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.

### 4️⃣ Configure Jenkins Pipeline

* Create a new **Pipeline Job**:

  * Name: `hello-eyego-pipeline`
  * SCM: Git → Repository: `https://github.com/M-Samii/eyego.git`
  * Branch: `master`
  * Script Path: `Jenkinsfile`

### 5️⃣ Run the Pipeline

* Trigger manually via **Build Now** in Jenkins.
* Or push changes to GitHub to trigger via webhook.

### 6️⃣ Verify Deployment

```bash
aws eks update-kubeconfig --region us-east-1 --name hello-eyego-cluster
kubectl get pods
kubectl get svc
```

Test application:

```bash
curl http://<EXTERNAL-IP>/api
# Expected: {"message":"Hello Eyego"}
```

---

## Migrating to GCP GKE

### 1️⃣ Create Terraform Configuration for GKE

Add `terraform/gke.tf`:

```hcl
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
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }
}

resource "google_artifact_registry_repository" "hello_eyego" {
  location      = var.region
  repository_id = "hello-eyego"
  format        = "DOCKER"
}

variable "gcp_project_id" {}
variable "region" { default = "us-central1" }
```

### 2️⃣ Apply Terraform Configuration

```bash
cd terraform
terraform init
terraform apply -var="gcp_project_id=<your-project-id>"
```

### 3️⃣ Update Jenkinsfile for GKE

Replace EKS stages with GKE deployment:

```groovy
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
```

### 4️⃣ Add GCP Credentials in Jenkins

* Manage Jenkins → Manage Credentials → (global) → Add Credentials.
* Kind: Google Service Account from private key.
* ID: `gcp-credentials`.
* Upload the JSON key.

### 5️⃣ Update Kubernetes Manifest

Update `kubernetes/deployment.yaml`:

```yaml
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
        image: us-central1-docker.pkg.dev/<your-project-id>/hello-eyego:latest
        ports:
        - containerPort: 3000
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          requests:
            cpu: "200m"
            memory: "256Mi"
```

### 6️⃣ Run the Pipeline

```bash
git add Jenkinsfile kubernetes/deployment.yaml terraform/gke.tf
git commit -m "Add GKE deployment configuration"
git push origin master
```

Trigger the pipeline in Jenkins and monitor logs.

### 7️⃣ Verify Deployment

```bash
gcloud container clusters get-credentials hello-eyego-cluster --region us-central1
kubectl get pods
kubectl get svc
curl http://<EXTERNAL-IP>/api
# Expected: {"message":"Hello Eyego"}
```

---


