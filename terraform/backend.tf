terraform {
  backend "s3" {
    bucket         = "namegen-tfstate-592404497449"
    key            = "namegen/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "namegen-tfstate-lock"
    encrypt        = true
  }
}
