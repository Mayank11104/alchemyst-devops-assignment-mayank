variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix for resource names"
  type        = string
  default     = "alchemyst-iii"
}

variable "inference_instance_type" {
  description = "Instance type for inference-worker VM (needs >= 8 GB RAM for 8192 MiB worker config)"
  type        = string
  default     = "t3.xlarge"
}

variable "caller_instance_type" {
  description = "Instance type for iii engine + caller-worker VM"
  type        = string
  default     = "t3.small"
}

variable "api_gateway_instance_type" {
  description = "Instance type for Nginx API gateway"
  type        = string
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name for SSH"
  type        = string
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR notation for SSH access to the API gateway (e.g. 203.0.113.5/32)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet (Nginx + NAT GW)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet (iii engine + workers)"
  type        = string
  default     = "10.0.2.0/24"
}