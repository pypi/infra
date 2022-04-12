variable "credentials" {
  type      = map(any)
  sensitive = true
}
variable "linehaul_token" {
  type      = string
  sensitive = true
}
variable "linehaul_creds" {
  type      = string
  sensitive = true
}
variable "aws_access_key_id" {
  type      = string
  sensitive = true
}
variable "aws_secret_access_key" {
  type      = string
  sensitive = true
}
variable "gcs_access_key_id" {
  type      = string
  sensitive = true
}
variable "gcs_secret_access_key" {
  type      = string
  sensitive = true
}
variable "warehouse_token" {
  type      = string
  sensitive = true
}


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
