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
variable "warehouse_ip_salt" {
  type      = string
  sensitive = true
}
variable "test_pypi_warehouse_token" {
  type      = string
  sensitive = true
}
variable "datadog_token" {
  type      = string
  sensitive = true
}

terraform {
  cloud {
    organization = "psf"
    workspaces {
      name = "pypi-infra"
    }
  }
}


provider "aws" {
  alias   = "us-east-2"
  region  = "us-east-2"
}


provider "aws" {
  alias   = "us-west-2"
  region  = "us-west-2"
}

provider "aws" {
  alias   = "email"
  region  = "us-west-2"
}


provider "fastly" {
  api_key = var.credentials["fastly"]
}
