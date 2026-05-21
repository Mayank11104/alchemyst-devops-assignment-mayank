terraform {
  required_version = ">= 1.5.0"

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

# ─── Data source: latest Ubuntu 22.04 LTS AMI ────────────────────────────────
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

# ─── VPC ─────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ─── Subnets ──────────────────────────────────────────────────────────────────
# Public subnet: Nginx API gateway + NAT Gateway
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# Private subnet: iii engine, caller-worker, inference-worker
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-private-subnet"
  }
}

# ─── Internet Gateway ─────────────────────────────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ─── Public Route Table: 0.0.0.0/0 → IGW ─────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ─── NAT Gateway (private subnet outbound — model download, pip, npm) ─────────
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.project_name}-nat"
  }

  # NAT GW needs the IGW to be attached first
  depends_on = [aws_internet_gateway.igw]
}

# ─── Private Route Table: 0.0.0.0/0 → NAT Gateway ───────────────────────────
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ─── Security Groups ──────────────────────────────────────────────────────────

# api-gateway-sg: public-facing Nginx VM
resource "aws_security_group" "api_gateway" {
  name        = "${var.project_name}-api-gateway-sg"
  description = "Allow iii-http API from internet; SSH from operator IP only"
  vpc_id      = aws_vpc.main.id

  # iii-http API port — open to world for the assignment demo
  ingress {
    description = "iii-http API"
    from_port   = 3111
    to_port     = 3111
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH restricted to operator IP
  ingress {
    description = "SSH from operator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-api-gateway-sg"
  }
}

# internal-workers-sg: iii engine + both worker VMs (private subnet)
resource "aws_security_group" "internal_workers" {
  name        = "${var.project_name}-internal-workers-sg"
  description = "iii engine ports accessible only within VPC CIDR; SSH from VPC"
  vpc_id      = aws_vpc.main.id

  # iii WebSocket bus — workers register here
  ingress {
    description = "iii WebSocket bus workers to engine"
    from_port   = 49134
    to_port     = 49134
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # iii-http — Nginx in public subnet proxies here
  ingress {
    description = "iii-http from Nginx to engine"
    from_port   = 3111
    to_port     = 3111
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # SSH via bastion / jump from within VPC only
  ingress {
    description = "SSH from within VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-internal-workers-sg"
  }
}

# ─── EC2: Nginx API Gateway (public subnet) ───────────────────────────────────
resource "aws_instance" "api_gateway" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.api_gateway_instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.api_gateway.id]

  user_data = file("${path.module}/../deploy/cloud-init/api-gateway.sh")

  tags = {
    Name = "${var.project_name}-api-gateway"
    Role = "api-gateway"
  }
}

# ─── EC2: iii Engine + Caller Worker (private subnet) ─────────────────────────
resource "aws_instance" "engine" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.caller_instance_type
  subnet_id              = aws_subnet.private.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.internal_workers.id]

  user_data = file("${path.module}/../deploy/cloud-init/engine.sh")

  tags = {
    Name = "${var.project_name}-engine"
    Role = "engine"
  }
}

# ─── EC2: Python Inference Worker (private subnet) ────────────────────────────
resource "aws_instance" "inference_worker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.inference_instance_type
  subnet_id              = aws_subnet.private.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.internal_workers.id]

  # Extra EBS space for HuggingFace model cache (~300 MB model + pip deps)
  root_block_device {
    volume_size = 30  # GiB
    volume_type = "gp3"
  }

  user_data = file("${path.module}/../deploy/cloud-init/inference-worker.sh")

  tags = {
    Name = "${var.project_name}-inference-worker"
    Role = "inference-worker"
  }
}