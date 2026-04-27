terraform {
  backend "s3" {
    bucket = "terraform-state-argorand"
    key    = "email_outreach/email_outreach.tfstate"
    region = "us-east-1"
  }
}