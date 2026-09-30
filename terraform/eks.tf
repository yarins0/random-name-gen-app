module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # Short-lived demo cluster reachable from a laptop via kubectl — no VPN/bastion.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Grants the applying IAM identity (namegen-terraform) cluster-admin via an EKS access entry,
  # so `aws eks update-kubeconfig` + kubectl work immediately after apply with no extra IAM wiring.
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  # The module's node security group is only attached to managed/self-managed node groups.
  # Auto Mode's built-in node pools use the EKS-created cluster security group instead, so it
  # would sit unused (while still tripping Trivy's AWS-0104 for its allow-all egress rule).
  create_node_security_group = false

  # Module default is api/audit/authenticator; controllerManager + scheduler complete the set.
  enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Auto Mode: EKS manages node provisioning/scaling itself, no aws_eks_node_group needed.
  compute_config = {
    enabled    = true
    node_pools = ["general-purpose"]
  }

  # Grants the GitHub Actions deploy role kubectl access (EKS Auto Mode uses access entries,
  # not the aws-auth ConfigMap) so CI can roll out image updates.
  access_entries = {
    github_actions = {
      principal_arn = aws_iam_role.github_actions_deploy.arn
      policy_associations = {
        edit = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
}
