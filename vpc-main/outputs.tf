# VPC
output "vpc_id" {
  description = "The ID of the VPC"
  value       = "${module.vpc.vpc_id}"
}

# VPC name
output "vpc_name" {
  description = "The name of the VPC"
  value       = "${var.vpc_name}"
}

# CIDR blocks
output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = ["${module.vpc.vpc_cidr_block}"]
}

# Subnets
output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = ["${module.vpc.private_subnets}"]
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = ["${module.vpc.public_subnets}"]
}

# NAT gateways
output "nat_public_ips" {
  description = "List of public Elastic IPs created for AWS NAT Gateway"
  value       = ["${module.vpc.nat_public_ips}"]
}

# AZs
output "azs" {
  description = "A list of availability zones spefified as argument to this module"
  value       = ["${module.vpc.azs}"]
}

output "private_route_table_ids" {
  description = "List of IDs of private route tables"
  value       = ["${module.vpc.private_route_table_ids}"]
}

output "public_route_table_ids" {
  description = "List of IDs of public route tables"
  value       = ["${module.vpc.public_route_table_ids}"]
}

output "default_route_table_id" {
  description = "Default route table of the VPC"
  value       = "${module.vpc.default_route_table_id}"
}

output "controller0_ip" {
  value = "${aws_instance.controller0.public_ip}"
}

output "controller1_ip" {
  value = "${aws_instance.controller1.public_ip}"
}

output "apiserver1_ip" {
  value = "${aws_instance.api_server.public_ip}"
}
