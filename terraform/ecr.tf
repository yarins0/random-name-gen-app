# force_delete lets `terraform destroy` remove the repo without manually deleting images first
# (Phase 5 teardown needs this — see docs/PLAN.md Build-Time Unknowns).
resource "aws_ecr_repository" "namegen" {
  name         = var.ecr_repository_name
  force_delete = true

  # Stays MUTABLE on purpose: .github/workflows/deploy.yml pushes a moving `:latest`
  # tag alongside the immutable `:$GITHUB_SHA` tag. IMMUTABLE would reject the second
  # `:latest` push and break the pipeline.
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Untagged layers are orphaned by each `:latest` re-push and bill as storage forever.
# Only untagged images expire — SHA-tagged images are left alone so a rollback target
# and the currently-running image can never be deleted out from under the cluster.
resource "aws_ecr_lifecycle_policy" "namegen" {
  repository = aws_ecr_repository.namegen.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = var.untagged_image_expiry_days
      }
      action = {
        type = "expire"
      }
    }]
  })
}
