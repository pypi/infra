# vrsions in rest of repo need upgraded first to use these version specifiers
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # version = "6.5.0"
    }
    fastly = {
      source = "fastly/fastly"
    }
  }
  # required_version = ">= 1.12.0"
}
