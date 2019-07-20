variable "aws_region" {
  default = "us-east-1"
}

variable "aws_access_key" {
  default = ""
}

variable "aws_secret_key" {
  default = ""
}

variable aws_profile {
  default = ""
}

variable aws_assume_role {
  default = ""
}

################################
#### Global Tags
################################
variable "environment" {
  description = "Name of the environment"
}

variable "owner" {
  description = "Name of the owner"
}

############################
### Start VPC Variables
############################

variable "vpc_name" {
  description = "Name of the VPC"
}

variable "vpc_cidr" {
  description = "Primary CIDR of the VPC"
}

variable "vpc_private_subnet_list" {
  type = "list"
}

variable "vpc_public_subnet_list" {
  type = "list"
}

variable "dns_server_list" {
  type        = "list"
  description = "List of DNS server used by VPC"
}

variable "vpc_internal_domain_name" {
  description = "Domain name to be used inside VPC"
}

variable "secondary_cidr_blocks" {
  description = "The secondary CIDR block to be used in case of peering for gitlab"
  type        = "list"
  default     = []
}
