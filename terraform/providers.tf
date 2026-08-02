terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 6.52 is the floor required by terraform-aws-modules/eks/aws ~> 21.0 (v6.28 for the vpc module).
      # Deliberate deviation from "pin to a recent 5.x": provider 5.x can't satisfy that, so init would fail.
      version = "~> 6.52"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}
