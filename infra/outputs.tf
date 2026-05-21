output "api_gateway_public_ip" {
  description = "Public IP of the Nginx API gateway — wire this into your curl / DNS"
  value       = aws_instance.api_gateway.public_ip
}

output "engine_private_ip" {
  description = "Private IP of the iii engine VM (used as III_URL host in worker cloud-init)"
  value       = aws_instance.engine.private_ip
}

output "inference_worker_private_ip" {
  description = "Private IP of the inference-worker VM"
  value       = aws_instance.inference_worker.private_ip
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "nat_gateway_public_ip" {
  description = "Elastic IP of the NAT Gateway (for allowlisting outbound traffic)"
  value       = aws_eip.nat.public_ip
}
