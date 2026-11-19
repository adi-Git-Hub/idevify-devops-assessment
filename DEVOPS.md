# DevOps Engineering Documentation & Deployment Guide

This document provides complete instructions for local development, containerization, infrastructure provisioning on AWS via Terraform, CI/CD automated deployments, and an authentic engineering troubleshooting log encountered during the implementation.

---

## 1. Architecture Overview

- **Backend:** Django REST API (Gunicorn WSGI server, SQLite database, non-root user `appuser` UID 1000).
- **Frontend:** React 19 + Vite + TypeScript (Single-Page App served via `nginxinc/nginx-unprivileged` on port 8080 as non-root user `nginx`).
- **Reverse Proxy:** Nginx routes `/api/` requests internally to `http://backend:8000/api/` and serves compiled static assets from `/usr/share/nginx/html`.
- **Infrastructure:** AWS EC2 instance running Ubuntu 24.04 LTS (`t3.micro`, free-tier eligible in `ap-southeast-2`) provisioned via Terraform with custom Security Group (inbound ports `22`, `80`, `443` only).
- **Container Registry:** GitHub Container Registry (`ghcr.io`).
- **CI/CD:** Dual-pipeline support via GitHub Actions (`.github/workflows/ci-cd.yml`) and declarative Jenkinsfile.

---

## 2. Local Development & Verification

### Prerequisites
- Python 3.12+ (or 3.14)
- Node.js 20+ and npm
- Docker Engine & Docker Compose

### Running Locally (Without Docker)
1. **Backend:**
   ```bash
   cd backend
   python -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   python manage.py migrate
   python manage.py runserver 127.0.0.1:8000
   ```
2. **Frontend:**
   ```bash
   cd frontend
   npm ci
   npm run dev
   # App will be accessible on http://localhost:5173
   ```

---

## 3. Docker & Docker Compose Setup

### Local Docker Environment
1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```
2. Build and start containers locally:
   ```bash
   docker compose up --build -d
   ```
3. Verify running containers:
   ```bash
   docker compose ps
   docker compose exec backend whoami    # Outputs: appuser
   docker compose exec frontend whoami   # Outputs: nginx
   ```
4. Verification endpoints:
   - Frontend: `curl -i http://localhost` (Status 200 OK)
   - Backend API: `curl -i http://localhost/api/hello/` (Status 200 OK)

### Production Docker Environment
The production setup uses `docker-compose.prod.yml` referencing pre-built images from GHCR:
```bash
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
```

---

## 4. Infrastructure as Code (Terraform)

All Terraform configurations are modularized inside `terraform/`.

### Resources Provisioned
- **VPC / Subnet:** Default AWS VPC in `ap-southeast-2`.
- **AMI:** Dynamic Canonical Ubuntu 24.04 LTS (`data "aws_ami"`).
- **SSH Key Pair:** Automated 4096-bit RSA key pair (`tls_private_key` + `aws_key_pair`), written locally to `terraform/devops-key.pem` with `0400` permissions.
- **Security Group:** Inbound rules strictly limited to ports `22` (SSH), `80` (HTTP), and `443` (HTTPS); universal egress (`0.0.0.0/0`).
- **EC2 Instance:** `t3.micro` instance with 20 GB gp3 encrypted storage and automated cloud-init bootstrap script (`user_data.sh`) that installs Docker and Docker Compose.

### Provisioning Steps
```bash
cd terraform
terraform init
terraform validate
terraform plan
terraform apply -auto-approve
```

Outputs:
```text
ec2_instance_id = "i-0f749f106f1a8f0ed"
ec2_public_ip   = "54.253.181.175"
ssh_command     = "ssh -i devops-key.pem -o StrictHostKeyChecking=no ubuntu@54.253.181.175"
```

---

## 5. CI/CD Pipeline Setup

### GitHub Actions Secrets
In your GitHub repository settings under **Settings > Secrets and variables > Actions**, configure:

| Secret Name | Value | Description |
| :--- | :--- | :--- |
| `EC2_HOST` | `54.253.181.175` | Elastic/Public IP address of the EC2 instance |
| `EC2_SSH_KEY` | Contents of `terraform/devops-key.pem` | Full PEM private key (including `-----BEGIN RSA PRIVATE KEY-----`) |

### Pipeline Workflow (`.github/workflows/ci-cd.yml`)
1. **Trigger:** Push to `main` branch or manual `workflow_dispatch`.
2. **Stage 1 (Build & Push):**
   - Authenticates with GHCR using automated `GITHUB_TOKEN`.
   - Builds multi-stage images for backend and frontend.
   - Pushes images tagged with `latest` and `${{ github.sha }}`.
3. **Stage 2 (Deploy via SSH):**
   - Securely copies `docker-compose.prod.yml` to `/home/ubuntu/app/docker-compose.yml` via SCP.
   - Creates `/home/ubuntu/app/.env` with production safe defaults if missing.
   - Authenticates Docker on the EC2 host with GHCR.
   - Executes `docker compose pull && docker compose up -d --remove-orphans`.
   - Runs automated healthcheck verification via `curl -sf http://localhost/api/hello/`.

---

## 6. Real Engineering Troubleshooting Log

### Issue 1: Host Disk Space Exhaustion & Obsolete Docker Credential Helper
- **Symptom:** Colima VM failed during disk allocation with `write ...: no space left on device` (available disk: `141Mi`), and Docker Compose threw `exec: "docker-credential-desktop": executable file not found in $PATH`.
- **Root Cause:**
  1. The host Mac had 0 bytes of available space due to stale system application updater caches (`~/Library/Caches/*ShipIt*`) and aborted VM files.
  2. Legacy `~/.docker/config.json` contained an obsolete `"credsStore": "desktop"` leftover from an uninstalled Docker Desktop.
- **Resolution:**
  1. Purged updater caches and stale VM artifacts, reclaiming over **21 GB** of free SSD storage.
  2. Updated `~/.docker/config.json` to clean out `"credsStore": "desktop"`, enabling standard headless Docker authentication.

---

### Issue 2: React Empty String Fallback Evaluation Bug (`||` vs `??`)
- **Symptom:** Inside Docker, frontend API calls were attempting to hit `http://127.0.0.1:8000/api/hello/` instead of using the Nginx reverse-proxy relative path `/api/hello/`.
- **Root Cause:**
  In `frontend/src/App.tsx`, the base URL was defined as:
  ```ts
  const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'http://127.0.0.1:8000'
  ```
  In JavaScript, an empty string `""` passed via Docker `ARG VITE_API_BASE_URL=""` evaluates as falsy in an `||` logical OR expression, causing it to fall back to `'http://127.0.0.1:8000'`.
- **Resolution:**
  Switched to nullish coalescing `??`:
  ```ts
  const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? 'http://127.0.0.1:8000'
  ```
  When `VITE_API_BASE_URL` is set to `""`, it preserves the empty string, successfully transforming `${API_BASE_URL}/api/hello/` into the relative `/api/hello/` endpoint routed by Nginx.

---

### Issue 3: AWS Organizations SCP Blocking Provisioning in `us-east-1`
- **Symptom:** AWS CLI and Terraform commands failed with:
  ```text
  UnauthorizedOperation: You are not authorized to perform this operation ...
  with an explicit deny in a service control policy: arn:aws:organizations::...:policy/.../p-75dpcfod
  ```
- **Root Cause:**
  The AWS Organization enforcing policy `p-75dpcfod` contains explicit boundary rules (`UsEast1Partitional`) restricting EC2 resource creation in `us-east-1` and most other global regions.
- **Resolution:**
  1. Decoded the authorization failure token using `aws sts decode-authorization-message` to inspect the exact SCP statement ID and condition keys.
  2. Executed an automated dry-run check across all AWS regions (`aws ec2 create-security-group ... --dry-run`), discovering that **`ap-southeast-2`** (Sydney) is the authorized region with full permissions.
  3. Reconfigured Terraform provider and variables to target `ap-southeast-2`.

---

### Issue 4: Free-Tier Instance Type Incompatibility in `ap-southeast-2`
- **Symptom:** `terraform apply` returned:
  ```text
  InvalidParameterCombination: The specified instance type is not eligible for Free Tier.
  ```
- **Root Cause:**
  In `ap-southeast-2`, `t2.micro` is not categorized as Free Tier eligible under current AWS policies; modern Nitro-based instances (`t3.micro`) are required instead.
- **Resolution:**
  Queried the AWS offerings API:
  ```bash
  aws ec2 describe-instance-types --region ap-southeast-2 --filters "Name=free-tier-eligible,Values=true"
  ```
  Verified that `t3.micro` is free-tier eligible. Updated `variables.tf` default from `t2.micro` to `t3.micro`, resulting in a clean and successful deployment.
