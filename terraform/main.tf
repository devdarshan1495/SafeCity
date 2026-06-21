# ── SafeCity — Terraform Provider & Backend ──────────────────────
# AWS provider for ap-south-1 (Mumbai)
# ─────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local state by default. For team use, switch to S3 backend:
  # backend "s3" {
  #   bucket = "safecity-tf-state"
  #   key    = "infra/terraform.tfstate"
  #   region = "ap-south-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "SafeCity"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Current account ID (used for unique S3 bucket names, etc.)
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
