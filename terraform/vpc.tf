# Shared cluster name — referenced here for subnet discovery tags and in eks.tf for the cluster itself.
locals {
  cluster_name = "namegen"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "namegen-vpc"
  cidr = "10.0.0.0/16"

  azs            = ["eu-north-1a", "eu-north-1b"]
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  # Public-NLB-only demo: no private subnets, no NAT gateway (avoids per-hour NAT cost for a
  # cluster that's built, demoed, and torn down).
  enable_nat_gateway      = false
  map_public_ip_on_launch = true

  # EKS Auto Mode discovers subnets to place nodes/load balancers in via these tags.
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  tags = {
    Project = "namegen"
  }
}
