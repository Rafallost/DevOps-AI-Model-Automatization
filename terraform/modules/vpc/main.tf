# VPC Module - Single public subnet, no NAT Gateway (budget constraint)

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-public-subnet"
    Project = var.project_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name    = "${var.project_name}-public-rt"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for EC2 instance running k3s and MLflow"
  vpc_id      = aws_vpc.main.id

  # SSH - from your IP only (auto-detected)
  ingress {
    description = "SSH from my IP (auto-detected)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_ip_cidr]
  }

  # HTTP (FastAPI serving) - from your IP only for manual testing
  ingress {
    description = "HTTP from my IP (auto-detected)"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = [local.my_ip_cidr]
  }

  # k3s NodePort range - for accessing deployed services (e.g. wms-model UI)
  ingress {
    description = "k3s NodePort services from my IP"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [local.my_ip_cidr]
  }

  # MLflow - open for GitHub Actions (ephemeral infrastructure)
  ingress {
    description = "MLflow from anywhere (for GitHub Actions)"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NOTE: k3s API (6443) is NOT exposed to internet

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-ec2-sg"
    Project = var.project_name
  }
}
