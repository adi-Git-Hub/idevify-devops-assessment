# DevOps Assessment Full-Stack Application

A production-grade "Hello World" full-stack application built with **Django REST API** (Backend) and **React + Vite + TypeScript** (Frontend), containerized with Docker, provisioned on AWS EC2 via Terraform, and deployed via automated CI/CD pipelines.

- **Live EC2 Deployment:** [http://54.253.181.175](http://54.253.181.175)
- **Live API Endpoint:** [http://54.253.181.175/api/hello/](http://54.253.181.175/api/hello/)
- **Comprehensive DevOps Documentation:** [DEVOPS.md](./DEVOPS.md)

---

## Project Architecture

- **Backend:** Django 6.1 REST API served with Gunicorn WSGI. Runs as non-root user `appuser` (UID 1000).
- **Frontend:** React 19 + TypeScript + Vite Single-Page Application (SPA) served via Nginx Unprivileged (`nginxinc/nginx-unprivileged:alpine`) on port 8080 as non-root user `nginx`.
- **Reverse Proxy:** Nginx routes `/api/` traffic directly to the backend service over an internal Docker network, avoiding CORS complexity in production.
- **Infrastructure as Code:** Terraform provisions an AWS EC2 instance (`t3.micro`) on Ubuntu 24.04 LTS in `ap-southeast-2` with custom Security Groups restricted to ports 22, 80, and 443.
- **CI/CD:** Automated dual pipelines via GitHub Actions (`.github/workflows/ci-cd.yml`) and Jenkins (`Jenkinsfile`) with automated Docker builds, GHCR container registry publishing, and SSH deployment.

---

## Quick Start Commands

### 1. Run Locally with Docker Compose
```bash
# Copy example environment configuration
cp .env.example .env

# Build and start services locally
docker compose up --build -d

# Verify services
docker compose ps
curl -i http://localhost
curl -i http://localhost/api/hello/
```

### 2. Run Locally in Development Mode
```bash
# Terminal 1: Backend
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver 127.0.0.1:8000

# Terminal 2: Frontend
cd frontend
npm ci
npm run dev
```

### 3. Deploy Infrastructure with Terraform
```bash
cd terraform
terraform init
terraform validate
terraform plan
terraform apply -auto-approve
```

---

## Engineering Assumptions

1. **GitHub Container Registry (GHCR) as the Registry of Record:**
   - Pre-built images are published to `ghcr.io/adi-git-hub/devops-fullstack-backend:latest` and `ghcr.io/adi-git-hub/devops-fullstack-frontend:latest` to take advantage of native GitHub token authentication and OCI compliance without requiring external Docker Hub credentials.
2. **GitHub Actions and Jenkinsfile Parity:**
   - Both pipelines are provided with architectural parity: building multi-stage container images, tagging with commit SHA and latest, pushing to GHCR, and deploying via SSH onto the EC2 host.
3. **Nginx Reverse Proxy & Port Translation (`80:8080`):**
   - In accordance with container security best practices, the frontend container runs without root privileges on port `8080`. Host port `80` is mapped to container port `8080` via Docker Compose so clients connect directly to standard HTTP port 80.
4. **AWS Region Selection (`ap-southeast-2`):**
   - The AWS account is governed by an AWS Organization Service Control Policy (SCP `p-75dpcfod`), which strictly blocks EC2 provisioning in `us-east-1` and most other global regions. Automated probing verified `ap-southeast-2` (Sydney) as the permitted region.
5. **Free-Tier Eligible Instance Type (`t3.micro`):**
   - Under AWS policy in `ap-southeast-2`, modern Nitro-based `t3.micro` is the designated free-tier eligible instance type (rather than legacy `t2.micro`).
