terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    fastly = {
      source  = "fastly/fastly"
      version = ">= 10.1.0"
    }
    sigsci = {
      source  = "signalsciences/sigsci"
      version = "3.3.0"
    }
  }
  required_version = ">= 1.14.0"
}
