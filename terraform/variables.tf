# =============================================================================
# terraform/variables.tf
# -----------------------------------------------------------------------------
# Defines input variables that parameterize the Terraform configuration.
# Variables make the infrastructure reusable across different environments
# (dev, staging, prod) without changing the main configuration.
# Override defaults by passing -var="aws_region=eu-west-1" to terraform apply.
# =============================================================================

variable "aws_region" {
  description = "AWS region where all resources will be created"
  type        = string
  default     = "us-east-1"  # N. Virginia — lowest latency for most users
}
