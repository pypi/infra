terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    fastly = {
      source = "fastly/fastly"
    }
    b2 = {
      source = "Backblaze/b2"
    }
  }
  required_version = ">= 0.13"
}
