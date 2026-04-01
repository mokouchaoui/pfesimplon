#!/usr/bin/env bash
# ============================================================
#  Helpdesk — one-shot AWS bootstrap
#  Run this ONCE on your local machine after: aws configure
#  After this script finishes, all future deploys happen
#  automatically via GitHub Actions on every git push.
# ============================================================
set -euo pipefail

# Make Windows-installed tools visible inside Git Bash
export PATH="/c/Program Files/Amazon/AWSCLIV2:/c/ProgramData/chocolatey/bin:/c/Program Files/Docker/Docker/resources/bin:$PATH"


REGION="us-east-1"
ACCOUNT="149146127959"
CLUSTER="helpdesk-eks"
SQS_URL="https://sqs.${REGION}.amazonaws.com/${ACCOUNT}/helpdesk-events"
ECR_BASE="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

echo ""
echo "======================================================"
echo " STEP 1 — Verify AWS credentials"
echo "======================================================"
aws sts get-caller-identity

echo ""
echo "======================================================"
echo " STEP 2 — Terraform: provision VPC, EKS, SQS, ECR,"
echo "          OIDC provider & GitHub Actions IAM role"
echo "          (~15-20 minutes)"
echo "======================================================"
cd "$(dirname "$0")/terraform"
terraform init -upgrade
terraform apply -auto-approve
cd ..

echo ""
echo "======================================================"
echo " STEP 3 — Configure kubectl for EKS"
echo "======================================================"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"
kubectl get nodes

echo ""
echo "======================================================"
echo " STEP 4 — Log in to ECR"
echo "======================================================"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ECR_BASE"

echo ""
echo "======================================================"
echo " STEP 5 — Build & push Docker images"
echo "======================================================"
# Backend + worker (same image, different entry point)
docker build -t "$ECR_BASE/helpdesk-backend:latest" ./backend
docker push "$ECR_BASE/helpdesk-backend:latest"

docker build -t "$ECR_BASE/helpdesk-worker:latest" ./backend
docker push "$ECR_BASE/helpdesk-worker:latest"

# Frontend
docker build -t "$ECR_BASE/helpdesk-frontend:latest" ./frontend
docker push "$ECR_BASE/helpdesk-frontend:latest"

echo ""
echo "======================================================"
echo " STEP 6 — Deploy to Kubernetes"
echo "======================================================"
# Put the SQS URL into a k8s secret (idempotent)
kubectl create secret generic app-secret \
  --namespace helpdesk \
  --from-literal=SQS_QUEUE_URL="$SQS_URL" \
  --dry-run=client -o yaml | kubectl apply -f -

# Substitute image placeholders and apply manifests
BE="$ECR_BASE/helpdesk-backend:latest"
WK="$ECR_BASE/helpdesk-worker:latest"
FE="$ECR_BASE/helpdesk-frontend:latest"

sed -e "s|REPLACE_WITH_BACKEND_IMAGE|$BE|g" \
    -e "s|REPLACE_WITH_WORKER_IMAGE|$WK|g" \
    -e "s|REPLACE_WITH_FRONTEND_IMAGE|$FE|g" \
    k8s/helpdesk.yaml | kubectl apply -f -

echo ""
echo "Waiting for pods to be ready..."
kubectl rollout status deployment/backend  -n helpdesk --timeout=180s
kubectl rollout status deployment/frontend -n helpdesk --timeout=180s

echo ""
echo "======================================================"
echo " DONE — App is live!"
echo "======================================================"
kubectl get svc frontend -n helpdesk
echo ""
echo "Copy the EXTERNAL-IP above and open it in your browser."
echo "From now on, every 'git push origin main' will trigger"
echo "the GitHub Actions pipeline to rebuild & redeploy."
