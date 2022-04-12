variable "credentials" { type = map(any) }
variable "linehaul_token" { type = string }
variable "linehaul_creds" { type = string }


terraform {
  backend "s3" {
    bucket         = "pypi-infra-terraform"
    key            = "production"
    region         = "us-east-2"
    dynamodb_table = "pypi-infra-terraform-locks"
    profile        = "psf-prod"
  }
}


provider "aws" {
  alias   = "us-east-2"
  region  = "us-east-2"
  profile = "psf-prod"
}


provider "aws" {
  alias   = "us-west-2"
  region  = "us-west-2"
  profile = "psf-prod"
}

provider "aws" {
  alias   = "email"
  region  = "us-west-2"
  profile = "psf-prod"
}


provider "fastly" {
  api_key = var.credentials["fastly"]
}
