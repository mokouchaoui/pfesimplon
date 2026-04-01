# Complete Step-by-Step Project Guide
## Helpdesk App — PFE DevOps & Cloud AWS

---

## PREREQUISITES — Install These First

```bash
# macOS — install all tools
brew install git docker docker-compose terraform awscli kubectl helm
brew install --cask docker   # Docker Desktop

# Verify
docker --version
terraform --version
aws --version
kubectl version --client
```

Create accounts if you don't have them:
- GitHub account (free): https://github.com
- AWS account: https://aws.amazon.com (requires credit card, use Free Tier)

---

## PART 1 — Run the App Locally

```bash
cd /Users/mohamed/Desktop/PFE

# Copy and fill in env file
cp .env.example .env
# Leave SQS_QUEUE_URL empty for local testing

# Start everything
docker compose up --build

# Test backend
curl http://localhost:5000/health
# Expected: {"status":"ok"}

curl -X POST http://localhost:5000/tickets \
  -H "Content-Type: application/json" \
  -d '{"title":"Test ticket","description":"First ticket"}'

curl http://localhost:5000/tickets

# Open browser: http://localhost:3000
```

Expected result: you can create tickets in the UI and they appear in the list.

---

## PART 2 — Push to GitHub

```bash
cd /Users/mohamed/Desktop/PFE

git init
git add .
git commit -m "initial helpdesk app"

# Create repo on GitHub (go to github.com/new)
git remote add origin https://github.com/YOUR_USERNAME/helpdesk-pfe.git
git branch -M main
git push -u origin main
```

---

## PART 3 — AWS Account & IAM Setup

```bash
# Configure AWS CLI with your credentials
aws configure
# Enter: Access Key ID, Secret Access Key, region=us-east-1, output=json

# Verify
aws sts get-caller-identity
```

**Create IAM Role for GitHub Actions (OIDC):**
1. Go to AWS Console → IAM → Identity Providers → Add provider
2. Provider type: OpenID Connect
3. Provider URL: `https://token.actions.githubusercontent.com`
4. Audience: `sts.amazonaws.com`
5. Create an IAM Role with trust policy:

```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringLike": { "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_USERNAME/helpdesk-pfe:*" }
  }
}
```

6. Attach policies: `AmazonEKSClusterPolicy`, `AmazonECRFullAccess`, `AmazonSQSFullAccess`, `AmazonVPCFullAccess`
7. Save the Role ARN (you'll need it later)

---

## PART 4 — Create ECR Repositories

```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1

aws ecr create-repository --repository-name helpdesk-backend  --region $REGION
aws ecr create-repository --repository-name helpdesk-frontend --region $REGION
aws ecr create-repository --repository-name helpdesk-worker   --region $REGION

# Print the ECR URLs (you'll need them for GitHub secrets)
echo "Backend:  ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/helpdesk-backend"
echo "Frontend: ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/helpdesk-frontend"
echo "Worker:   ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/helpdesk-worker"
```

---

## PART 5 — Terraform: Provision AWS Infrastructure

```bash
cd /Users/mohamed/Desktop/PFE/terraform

terraform init

# Review what will be created (VPC + EKS + SQS)
terraform plan

# Create everything (takes ~15-20 minutes)
terraform apply
# Type "yes" when prompted

# Save outputs
terraform output cluster_name   # helpdesk-eks
terraform output sqs_queue_url  # https://sqs.us-east-1.amazonaws.com/...
```

> Save the `sqs_queue_url` output — you'll need it for Kubernetes secrets.

---

## PART 6 — Configure kubectl for EKS

```bash
aws eks update-kubeconfig --name helpdesk-eks --region us-east-1

# Verify cluster connection
kubectl get nodes
# Expected: 2 nodes in Ready state
```

---

## PART 7 — Set GitHub Secrets

Go to your GitHub repo → Settings → Secrets and variables → Actions → New repository secret

| Secret Name     | Value                                                                 |
|-----------------|-----------------------------------------------------------------------|
| `AWS_ROLE_ARN`  | arn:aws:iam::ACCOUNT_ID:role/YOUR_ROLE_NAME                          |
| `ECR_BACKEND`   | ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/helpdesk-backend          |
| `ECR_WORKER`    | ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/helpdesk-worker           |
| `ECR_FRONTEND`  | ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/helpdesk-frontend         |
| `BACKEND_URL`   | http://FRONTEND_LOADBALANCER_DNS/api  (get from kubectl after deploy) |

---

## PART 8 — First Manual Kubernetes Deployment

```bash
# Set the SQS URL in the secret
SQS_URL=$(cd /Users/mohamed/Desktop/PFE/terraform && terraform output -raw sqs_queue_url)

# Update k8s secret
kubectl create secret generic app-secret \
  --namespace helpdesk \
  --from-literal=SQS_QUEUE_URL=$SQS_URL \
  --dry-run=client -o yaml | kubectl apply -f -

# Log into ECR and push images manually (first time)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
ECR_LOGIN=$(aws ecr get-login-password --region $REGION)
echo $ECR_LOGIN | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

cd /Users/mohamed/Desktop/PFE
docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/helpdesk-backend:latest ./backend
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/helpdesk-backend:latest

docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/helpdesk-worker:latest ./backend
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/helpdesk-worker:latest

docker build \
  --build-arg NEXT_PUBLIC_API_URL=http://backend:5000 \
  -t ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/helpdesk-frontend:latest ./frontend
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/helpdesk-frontend:latest

# Deploy to EKS
cd /Users/mohamed/Desktop/PFE
BE=${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/helpdesk-backend:latest
WK=${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/helpdesk-worker:latest
FE=${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/helpdesk-frontend:latest

sed -e "s|REPLACE_WITH_BACKEND_IMAGE|$BE|g" \
    -e "s|REPLACE_WITH_WORKER_IMAGE|$WK|g" \
    -e "s|REPLACE_WITH_FRONTEND_IMAGE|$FE|g" \
    k8s/helpdesk.yaml | kubectl apply -f -

# Watch pods come up
kubectl get pods -n helpdesk -w
```

---

## PART 9 — Test on EKS

```bash
# Get the Load Balancer URL
kubectl get svc frontend -n helpdesk
# Copy the EXTERNAL-IP value

# Test
curl http://EXTERNAL_IP/api/health   # {"status":"ok"}
```

---

## PART 10 — Trigger CI/CD Pipeline

```bash
# Push any code change to trigger the pipeline
cd /Users/mohamed/Desktop/PFE
echo "# trigger" >> README.md
git add README.md
git commit -m "trigger ci/cd"
git push
```

Go to GitHub → Actions → watch the pipeline run. It builds and deploys automatically.

---

## PART 11 — CloudWatch Monitoring Setup

```bash
# Install CloudWatch Container Insights on EKS
aws eks create-addon \
  --cluster-name helpdesk-eks \
  --addon-name amazon-cloudwatch-observability \
  --region us-east-1
```

Then in AWS Console:
1. Go to CloudWatch → Log Groups — you'll see `/aws/containerinsights/helpdesk-eks/...`
2. Go to CloudWatch → Dashboards → Create dashboard → "Helpdesk"
3. Add widgets:
   - CPU Utilization: namespace `ContainerInsights`, metric `pod_cpu_utilization`
   - Memory: `pod_memory_utilization`
   - Line graph for both backend pods

**Create an alarm:**
- CloudWatch → Alarms → Create Alarm
- Metric: `pod_cpu_utilization`, threshold > 80%
- Action: Create SNS topic → add your email

---

## PART 12 — SQS Monitoring

1. Go to AWS Console → SQS → `helpdesk-events`
2. Under Monitoring tab: view Messages Sent, Messages Received
3. View `helpdesk-dlq` — any messages here = processing failures

---

## PART 13 — Security Hardening

```bash
# Verify K8s secret was created (not in plaintext env)
kubectl describe pod -n helpdesk -l app=backend | grep SQS
# Should show valueFrom secretKeyRef, not plain value

# Verify least privilege — check IAM role has only required policies
aws iam list-attached-role-policies --role-name YOUR_ROLE_NAME
```

In AWS Console → Secrets Manager (optional upgrade):
- Store SQS URL and other secrets here instead of K8s secrets

---

## CLEANUP (After Presentation — to avoid AWS charges)

```bash
# Delete K8s resources
kubectl delete namespace helpdesk

# Destroy infrastructure (saves ~$0.10/hour for EKS + NAT Gateway)
cd /Users/mohamed/Desktop/PFE/terraform
terraform destroy
# Type "yes"

# Delete ECR images (optional)
aws ecr delete-repository --repository-name helpdesk-backend  --force
aws ecr delete-repository --repository-name helpdesk-frontend --force
aws ecr delete-repository --repository-name helpdesk-worker   --force
```

---

## CHECKLIST — Day Before Presentation

- [ ] Local demo works: `docker compose up --build` → open localhost:3000
- [ ] GitHub repo is public and has all files committed
- [ ] Terraform apply completed, outputs saved
- [ ] EKS pods all Running: `kubectl get pods -n helpdesk`
- [ ] Frontend LoadBalancer URL accessible in browser
- [ ] CI/CD pipeline has run at least once (green)
- [ ] CloudWatch has at least one log group visible
- [ ] Screenshots ready: AWS Console, CloudWatch, GitHub Actions, K8s pods
- [ ] Slides loaded in browser and tested with keyboard navigation
- [ ] Each Jenkins/CI/CD run shows successful green status

---

## COST ESTIMATE (AWS)

| Resource       | Cost/hour |
|----------------|-----------|
| EKS Cluster    | ~$0.10    |
| t3.small × 2  | ~$0.05    |
| NAT Gateway    | ~$0.05    |
| SQS            | Free tier |
| ECR            | ~$0.01    |
| **Total**      | ~$0.21/hr |

> Destroy infrastructure when not using it to save money.
