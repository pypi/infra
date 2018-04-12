variable "linehaul_token" { type = "string" }


locals {
  tags = {
    Application = "PyPI"
    Environment = "Production"
  }
}


module "dns" {
  source = "./dns"

  tags = "${local.tags}"

  primary_domain = "pypi.org"
  user_content_domain = "pythonhosted.org"
}


module "email" {
  source = "./email"
  providers = {
    "aws" = "aws"
    "aws.email" = "aws.us-west-2"
  }

  zone_id  = "${module.dns.primary_zone_id}"
  domain   = "pypi.org"
  hook_url = "https://pypi.org/_/ses-hook/"
}


module "file-hosting" {
  source = "./file-hosting"

  domain           = "files.pythonhosted.org"
  conveyor_address = "conveyor.cmh1.psfhosted.org"
  files_bucket     = "pypi-files"

  linehaul = {
    address = "linehaul01.iad1.psf.io"
    port    = 48175
    token   = "${var.linehaul_token}"
  }
}


output "nameservers" { value = ["${module.dns.nameservers}"] }
output "ses_delivery_topic" { value = "${module.email.delivery_topic}" }
