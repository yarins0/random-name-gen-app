# force_delete lets `terraform destroy` remove the repo without manually deleting images first
# (Phase 5 teardown needs this — see docs/PLAN.md Build-Time Unknowns).
resource "aws_ecr_repository" "namegen" {
  name         = "namegen"
  force_delete = true

  tags = {
    Project = "namegen"
  }
}
