terraform {
  # Backend blocks cannot interpolate variables, so these values stay literal.
  # Change them here to match the bucket created during bootstrap (see README.md).
  backend "s3" {
    bucket = "namegen-tfstate-592404497449"
    key    = "namegen/terraform.tfstate"
    region = "eu-north-1"

    # S3-native state locking (Terraform >= 1.11). Replaces the separate DynamoDB
    # lock table, whose `dynamodb_table` argument is deprecated and slated for removal.
    use_lockfile = true
    encrypt      = true
  }
}
