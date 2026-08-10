# All environment-specific values live here, not inline in resources.
# Defaults are set directly (not in a .tfvars file) because .gitignore excludes *.tfvars,
# so defaults keep the repo self-contained and reproducible after a clone.

variable "region" {
  description = "AWS region for every resource in this stack"
  type        = string
  default     = "eu-north-1"
}

variable "project" {
  description = "Project name, applied to every resource as a default tag"
  type        = string
  default     = "namegen"
}

variable "cluster_name" {
  description = "EKS cluster name, also used for the subnet discovery tags"
  type        = string
  default     = "namegen"
}

variable "kubernetes_version" {
  description = "EKS control plane Kubernetes version"
  type        = string
  default     = "1.33"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for the public subnets"
  type        = list(string)
  default     = ["eu-north-1a", "eu-north-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets, one per availability zone"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository holding the app image"
  type        = string
  default     = "namegen"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint"
  type        = list(string)
  # Demo cluster reached from a laptop with a changing IP, so this stays open.
  # Narrow this to a known office or home CIDR for anything longer-lived.
  default = ["0.0.0.0/0"]
}

variable "github_actions_subject" {
  description = <<-EOT
    OIDC `sub` claim allowed to assume the deploy role. This account uses immutable
    subject claims (owner/repo numeric IDs baked into `sub`), not the plain
    "repo:owner/name:ref:..." form most tutorials assume. Confirm the exact value with
    `gh api repos/<owner>/<repo>/actions/oidc/customization/sub` before changing it.
  EOT
  type        = string
  default     = "repo:yarins0@160392523/random-name-gen-app@1320105468:ref:refs/heads/main"
}

variable "untagged_image_expiry_days" {
  description = "Days before untagged ECR images expire"
  type        = number
  default     = 1
}
