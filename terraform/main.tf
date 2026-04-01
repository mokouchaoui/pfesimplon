terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "helpdesk-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "helpdesk-eks"
  cluster_version = "1.30"

  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2
    }
  }

  # Grant GitHub Actions role cluster-admin access
  access_entries = {
    github_actions = {
      kubernetes_groups = []
      principal_arn     = aws_iam_role.github_actions.arn

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
}

resource "aws_ecr_repository" "backend" {
  name                 = "helpdesk-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
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

# ── GitHub Actions OIDC ──────────────────────────────────────────────────────

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

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

resource "aws_iam_role_policy_attachment" "github_ecr" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

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

# ── Queues ────────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "helpdesk_dlq" {
  name = "helpdesk-dlq"
}

resource "aws_sqs_queue" "helpdesk_events" {
  name = "helpdesk-events"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.helpdesk_dlq.arn
    maxReceiveCount     = 5
  })
}

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
