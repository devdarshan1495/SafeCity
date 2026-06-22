# ── SafeCity — EC2 Instances ─────────────────────────────────────

# Latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── K3s Master ──────────────────────────────────────────────────

resource "aws_instance" "k3s_master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.k3s_master.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size           = var.master_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/userdata/master.sh", {
    aws_region       = var.aws_region
    project_name     = var.project_name
    ecr_registry     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
    account_id       = data.aws_caller_identity.current.account_id
  })

  tags = {
    Name = "${var.project_name}-k3s-master"
    Role = "master"
  }
}

# ── K3s Worker ──────────────────────────────────────────────────

resource "aws_instance" "k3s_worker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.public[1].id
  vpc_security_group_ids = [aws_security_group.k3s_worker.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size           = var.worker_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/userdata/worker.sh", {
    master_private_ip = aws_instance.k3s_master.private_ip
    aws_region        = var.aws_region
    project_name      = var.project_name
  })

  depends_on = [aws_instance.k3s_master]

  tags = {
    Name = "${var.project_name}-k3s-worker-1"
    Role = "worker"
  }
}
