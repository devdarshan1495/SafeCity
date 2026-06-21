# ── SafeCity — Terraform Variables ───────────────────────────────

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "demo"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "safecity"
}

# ── Networking ───────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "AZs for subnet distribution"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

# ── EC2 ──────────────────────────────────────────────────────────

variable "key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
  default     = "DevAnalytics"
}

variable "master_instance_type" {
  description = "Instance type for K3s master node"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "Instance type for K3s worker node(s)"
  type        = string
  default     = "t3.medium"
}

variable "master_volume_size" {
  description = "Root EBS volume size (GB) for master"
  type        = number
  default     = 30
}

variable "worker_volume_size" {
  description = "Root EBS volume size (GB) for worker"
  type        = number
  default     = 25
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into instances (set to your IP)"
  type        = string
  default     = "0.0.0.0/0"  # Restrict in production!
}
