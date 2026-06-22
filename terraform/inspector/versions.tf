terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # version = "6.5.0"
    }
    fastly = {
      source = "fastly/fastly"
    }
    sigsci = {
      source  = "signalsciences/sigsci"
      version = "3.3.0"
    }
  }
  required_version = ">= 1.14.0"
}
