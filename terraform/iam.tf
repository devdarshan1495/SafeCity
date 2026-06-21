# ── SafeCity — IAM Roles & Instance Profiles ─────────────────────

# EC2 assume-role policy
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# IAM role for EC2 instances
resource "aws_iam_role" "ec2_role" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

# Policy: ECR full access (pull + push images)
data "aws_iam_policy_document" "ecr_access" {
  statement {
    sid = "ECRAuth"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ECRPullPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [
      aws_ecr_repository.api.arn,
      aws_ecr_repository.dashboard.arn,
    ]
  }
}

resource "aws_iam_role_policy" "ecr_access" {
  name   = "${var.project_name}-ecr-access"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.ecr_access.json
}

# Policy: S3 access for backups
data "aws_iam_policy_document" "s3_access" {
  statement {
    sid = "S3BackupAccess"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      aws_s3_bucket.backups.arn,
      "${aws_s3_bucket.backups.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "s3_access" {
  name   = "${var.project_name}-s3-access"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.s3_access.json
}

# Policy: SSM Parameter Store (for K3s join token)
data "aws_iam_policy_document" "ssm_access" {
  statement {
    sid = "SSMParameterAccess"
    actions = [
      "ssm:GetParameter",
      "ssm:PutParameter",
      "ssm:DeleteParameter",
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/*"
    ]
  }
}

resource "aws_iam_role_policy" "ssm_access" {
  name   = "${var.project_name}-ssm-access"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.ssm_access.json
}

# Instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}
