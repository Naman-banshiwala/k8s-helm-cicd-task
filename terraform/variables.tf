variable "aws_region" {
  description = "AWS deployment region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project resource prefix"
  type        = string
  default     = "demo-eks"
}

variable "cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.37"
}

variable "allowed_cidr" {
  description = "Your public IPv4 address in CIDR notation"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.allowed_cidr)) && endswith(var.allowed_cidr, "/32")
    error_message = "Provide your public IPv4 address with /32, for example 203.0.113.10/32."
  }
}