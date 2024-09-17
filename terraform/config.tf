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
variable "x_pypi_admin_token" {
  type      = string
  sensitive = true
}

## NGWAF
variable "activate_ngwaf_service" {
  type        = bool
  description = "Whether to activate the NGWAF service."
}
variable "edge_security_dictionary" {
  type        = string
  description = "The dictionary name for the Edge Security product."
  default     = "Edge_Security"
}
variable "ngwaf_corp_name" {
  type        = string
  description = "Corp name for NGWAF"
  default     = "python"
}
variable "ngwaf_site_name" {
  type        = string
  description = "Site SHORT name for NGWAF"

  validation {
    condition     = can(regex("^(pypi-test|pypi-prod)$", var.ngwaf_site_name))
    error_message = "'ngwaf_site_name' must be one of the following: pypi-test, or pypiprod"
  }
}
variable "ngwaf_email" {
  type        = string
  description = "Email address associated with the token for the NGWAF API."
}
variable "ngwaf_token" {
  type        = string
  description = "Secret token for the NGWAF API."
  sensitive   = true
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
  alias  = "us-east-2"
  region = "us-east-2"
}


provider "aws" {
  alias  = "us-west-2"
  region = "us-west-2"
}

provider "aws" {
  alias  = "email"
  region = "us-west-2"
}


provider "fastly" {
  api_key = var.credentials["fastly"]
}

provider "sigsci" {
  alias          = "firewall"
  corp           = var.ngwaf_corp_name
  email          = var.ngwaf_email
  auth_token     = var.ngwaf_token
  fastly_api_key = var.credentials["fastly"]
}
