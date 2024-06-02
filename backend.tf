terraform {
  backend "s3" {
    bucket         = "s3-revhire-backend-job-remote"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "revhire-job-backend-dynamodb"
  }
}

