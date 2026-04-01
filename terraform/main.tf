# =============================================================================
# terraform/main.tf
# -----------------------------------------------------------------------------
# Defines ALL AWS infrastructure for the Helpdesk PFE as code.
# Run "terraform apply" once to create everything from scratch.
# Run "terraform destroy" to tear down all resources and stop billing.
#
# Resources created:
#   - VPC with public/private subnets across 2 availability zones
#   - NAT Gateway (lets private nodes reach internet without public IPs)
#   - EKS cluster (Kubernetes) with 2x t3.small worker nodes
#   - 3 ECR repositories (private Docker registries for our images)
#   - 2 SQS queues (main queue + dead letter queue)
#   - GitHub Actions OIDC provider + IAM role (passwordless CI/CD auth)
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # Use AWS provider v5.x
    }
  }
}

# Configure the AWS provider to use the region from variables.tf
provider "aws" {
  region = var.aws_region
}

# =============================================================================
# VPC — Virtual Private Cloud
# -----------------------------------------------------------------------------
# Creates an isolated network for all our resources.
# Architecture:
#   Public subnets  — host the Load Balancer (internet-facing)
#   Private subnets — host the EKS worker nodes (no public IP, more secure)
#   NAT Gateway     — allows private nodes to pull Docker images from ECR
# =============================================================================
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "helpdesk-vpc"
  cidr = "10.0.0.0/16"  # 65,536 available IP addresses

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]  # 2 AZs for high availability
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]   # LoadBalancer lives here
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"] # EKS nodes live here

  enable_nat_gateway = true   # Allows private subnet nodes to reach internet
  single_nat_gateway = true   # One NAT Gateway (cost optimization for dev/demo)
}

# =============================================================================
# EKS — Elastic Kubernetes Service
# -----------------------------------------------------------------------------
# Managed Kubernetes cluster. AWS handles the control plane (API server, etcd).
# We only manage the worker nodes (EC2 instances that run our pods).
# =============================================================================
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "helpdesk-eks"
  cluster_version = "1.30"  # Kubernetes version

  cluster_endpoint_public_access = true  # Allow kubectl from outside the VPC

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets  # Nodes in private subnets (no public IPs)

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]  # 2 vCPU, 2GB RAM — enough for the demo
      min_size       = 1             # Scale down to 1 node when idle
      max_size       = 3             # Scale up to 3 nodes under load
      desired_size   = 2             # Start with 2 nodes (1 per AZ)
    }
  }

  # Grant the GitHub Actions IAM role cluster-admin access.
  # This allows the CI/CD pipeline to run kubectl commands during deployment.
  access_entries = {
    github_actions = {
      kubernetes_groups = []
      principal_arn     = aws_iam_role.github_actions.arn

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"  # Cluster-wide admin (not namespace-scoped)
          }
        }
      }
    }
  }
}

# =============================================================================
# ECR — Elastic Container Registry
# -----------------------------------------------------------------------------
# Private Docker image registries. Images built by CI/CD are pushed here.
# EKS nodes pull images from ECR when starting pods.
# force_delete=true allows cleanup without manually deleting images first.
# =============================================================================

resource "aws_ecr_repository" "backend" {
  name                 = "helpdesk-backend"
  image_tag_mutability = "MUTABLE"  # Allow overwriting the "latest" tag
  force_delete         = true       # Delete all images when repo is destroyed
}

resource "aws_ecr_repository" "worker" {
  name                 = "helpdesk-worker"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "frontend" {
  name                 = "helpdesk-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# =============================================================================
# GitHub Actions OIDC — Passwordless CI/CD Authentication
# -----------------------------------------------------------------------------
# Instead of storing static AWS access keys in GitHub Secrets, we use
# OpenID Connect. GitHub generates a short-lived JWT for each workflow run.
# AWS verifies the JWT and returns temporary credentials — no keys to rotate.
# =============================================================================

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"  # GitHub's OIDC issuer
  client_id_list = ["sts.amazonaws.com"]  # The audience the token is issued for
  # SHA1 thumbprints of GitHub's OIDC certificate chain — required by AWS
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# IAM Role assumed by GitHub Actions during CI/CD pipeline runs.
# The trust policy restricts it to ONLY the mokouchaoui/pfesimplon repository.
resource "aws_iam_role" "github_actions" {
  name = "helpdesk-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            # Only tokens from this specific repo can assume this role
            "token.actions.githubusercontent.com:sub" = "repo:mokouchaoui/pfesimplon:*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Allow GitHub Actions to push/pull Docker images to/from ECR
resource "aws_iam_role_policy_attachment" "github_ecr" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

# Allow GitHub Actions to describe the EKS cluster (needed for kubectl auth)
# and access SQS (needed for the CD step that updates the k8s secret)
resource "aws_iam_role_policy" "github_eks_sqs" {
  name = "helpdesk-eks-sqs"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster", "eks:ListClusters", "eks:UpdateClusterConfig"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:*"]
        Resource = "*"
      },
    ]
  })
}

# =============================================================================
# SQS — Simple Queue Service
# -----------------------------------------------------------------------------
# Implements the producer/consumer (event-driven) pattern.
# helpdesk-events: receives ticket IDs from the Flask backend
# helpdesk-dlq: receives messages that failed processing 5+ times (Dead Letter Queue)
# =============================================================================

# Dead Letter Queue — catches messages that the worker fails to process repeatedly.
# Prevents bad messages from blocking the main queue forever.
resource "aws_sqs_queue" "helpdesk_dlq" {
  name = "helpdesk-dlq"
}

# Main queue — receives ticket IDs from the backend when tickets are created.
# redrive_policy: after 5 failed processing attempts, move message to DLQ.
resource "aws_sqs_queue" "helpdesk_events" {
  name = "helpdesk-events"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.helpdesk_dlq.arn
    maxReceiveCount     = 5  # Move to DLQ after 5 failed receive attempts
  })
}

# =============================================================================
# Outputs — printed after terraform apply
# Used by the CI/CD pipeline and manual kubectl commands
# =============================================================================

output "cluster_name" {
  value = module.eks.cluster_name
}

output "sqs_queue_url" {
  value = aws_sqs_queue.helpdesk_events.url
}

output "ecr_backend_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "ecr_worker_url" {
  value = aws_ecr_repository.worker.repository_url
}

output "ecr_frontend_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
