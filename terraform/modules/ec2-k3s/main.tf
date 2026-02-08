# EC2 + k3s Module - Single t3.small instance with k3s, Docker, MLflow

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# NOTE: AWS Academy Learner Lab restriction - cannot create IAM roles
# Using pre-existing LabInstanceProfile instead
# The LabRole has broad permissions including S3 access

# Render user-data script with template variables
data "template_file" "user_data" {
  template = file("${path.module}/user-data.sh")

  vars = {
    mlflow_bucket = var.mlflow_bucket
  }
}

resource "aws_instance" "k3s" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_name
  iam_instance_profile   = "LabInstanceProfile"  # Pre-existing in Learner Lab

  user_data = data.template_file.user_data.rendered

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100  # Increased from 40GB to handle MLflow artifacts and k3s images
    delete_on_termination = true
  }

  tags = {
    Name    = "${var.project_name}-k3s"
    Project = var.project_name
  }
}

resource "aws_eip" "k3s" {
  instance = aws_instance.k3s.id
  domain   = "vpc"

  tags = {
    Name    = "${var.project_name}-eip"
    Project = var.project_name
  }
}
