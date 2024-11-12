terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.13.0"
    }
    fastly = {
      source  = "fastly/fastly"
      version = "5.13.0"
    }
    sigsci = {
      source  = "signalsciences/sigsci"
      version = "3.3.0"
    }
  }
  required_version = ">= 1.1.8"
}
