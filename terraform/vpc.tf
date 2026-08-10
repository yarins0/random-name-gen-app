module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr

  azs            = var.availability_zones
  public_subnets = var.public_subnet_cidrs

  # Public-NLB-only demo: no private subnets, no NAT gateway (avoids per-hour NAT cost for a
  # cluster that's built, demoed, and torn down).
  enable_nat_gateway      = false
  map_public_ip_on_launch = true

  # EKS Auto Mode discovers subnets to place nodes/load balancers in via these tags.
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}
