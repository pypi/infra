terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    fastly = {
      source = "fastly/fastly"
    }
  }
  required_version = ">= 1.14.0"
}
