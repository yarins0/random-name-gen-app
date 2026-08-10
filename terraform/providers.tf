terraform {
  # >= 1.11 is required by backend.tf's `use_lockfile` (S3-native state locking).
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 6.52 is the floor required by terraform-aws-modules/eks/aws ~> 21.0 (v6.28 for the vpc module).
      # Deliberate deviation from "pin to a recent 5.x": provider 5.x can't satisfy that, so init would fail.
      version = "~> 6.52"
    }
  }
}

provider "aws" {
  region = var.region

  # Applied to every taggable resource in this stack, so individual resources
  # and modules no longer repeat a `tags` block.
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}
