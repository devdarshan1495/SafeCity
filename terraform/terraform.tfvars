# ── SafeCity — Variable Values ───────────────────────────────────
# Adjust these for your environment.

aws_region           = "ap-south-1"
environment          = "demo"
project_name         = "safecity"

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
availability_zones   = ["ap-south-1a", "ap-south-1b"]

key_name             = "DevAnalytics"
master_instance_type = "t3.small"
worker_instance_type = "t3.small"
master_volume_size   = 30
worker_volume_size   = 25

# Set to your public IP for SSH lockdown, e.g. "203.0.113.42/32"
allowed_ssh_cidr     = "0.0.0.0/0"
