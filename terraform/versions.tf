terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.9.0"
    }
    fastly = {
      source  = "fastly/fastly"
      version = "1.1.2"
    }
  }
  required_version = ">= 0.13"
}
