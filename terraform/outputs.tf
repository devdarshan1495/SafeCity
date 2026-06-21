# ── SafeCity — Terraform Outputs ─────────────────────────────────

output "master_public_ip" {
  description = "Public IP of K3s master node"
  value       = aws_instance.k3s_master.public_ip
}

output "master_private_ip" {
  description = "Private IP of K3s master node"
  value       = aws_instance.k3s_master.private_ip
}

output "worker_public_ip" {
  description = "Public IP of K3s worker node"
  value       = aws_instance.k3s_worker.public_ip
}

output "worker_private_ip" {
  description = "Private IP of K3s worker node"
  value       = aws_instance.k3s_worker.private_ip
}

output "ecr_api_url" {
  description = "ECR URL for SafeCity API image"
  value       = aws_ecr_repository.api.repository_url
}

output "ecr_dashboard_url" {
  description = "ECR URL for SafeCity Dashboard image"
  value       = aws_ecr_repository.dashboard.repository_url
}

output "s3_backup_bucket" {
  description = "S3 bucket for backups"
  value       = aws_s3_bucket.backups.id
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "ssh_command_master" {
  description = "SSH command to connect to master"
  value       = "ssh -i ~/Downloads/DevAnalytics.pem ubuntu@${aws_instance.k3s_master.public_ip}"
}

output "ssh_command_worker" {
  description = "SSH command to connect to worker"
  value       = "ssh -i ~/Downloads/DevAnalytics.pem ubuntu@${aws_instance.k3s_worker.public_ip}"
}

output "dashboard_url" {
  description = "SafeCity Dashboard URL"
  value       = "http://${aws_instance.k3s_master.public_ip}:30080"
}

output "api_url" {
  description = "SafeCity API URL"
  value       = "http://${aws_instance.k3s_master.public_ip}:30000"
}

output "grafana_url" {
  description = "Grafana URL"
  value       = "http://${aws_instance.k3s_master.public_ip}:30030"
}

output "prometheus_url" {
  description = "Prometheus URL"
  value       = "http://${aws_instance.k3s_master.public_ip}:30090"
}

output "jenkins_url" {
  description = "Jenkins URL"
  value       = "http://${aws_instance.k3s_master.public_ip}:8080"
}
