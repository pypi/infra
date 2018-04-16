variable "linehaul_token" { type = "string" }
variable "fastly_s3_logging" { type = "map" }

locals {
  tags = {
    Application = "PyPI"
    Environment = "Production"
  }
}


locals {
  fastly_endpoints {
    r.ssl.fastly.net_A      = ["151.101.1.63", "151.101.65.63", "151.101.129.63", "151.101.193.63"]
    r.ssl.fastly.net_AAAA   = ["2a04:4e42::319", "2a04:4e42:200::319", "2a04:4e42:400::319", "2a04:4e42:600::319"]
    r.ssl.fastly.net_CNAME  = ["dualstack.r.ssl.global.fastly.net"]
    python.map.fastly.net_A     = ["151.101.128.223", "151.101.192.223", "151.101.0.223", "151.101.64.223"]
    python.map.fastly.net_AAAA  = ["2a04:4e42:200::223", "2a04:4e42:400::223", "2a04:4e42:600::223", "2a04:4e42::223"]
    python.map.fastly.net_CNAME = ["dualstack.python.map.fastly.net"]
  }
  domain_map {
    pypi.org                    = "python.map.fastly.net"
    pythonhosted.org            = "r.ssl.fastly.net"
    files.pythonhosted.org      = "r.ssl.fastly.net"
  }
}


module "dns" {
  source = "./dns"

  tags = "${local.tags}"

  primary_domain = "pypi.org"
  user_content_domain = "pythonhosted.org"

  google_verification = {
    primary = "google-site-verification=YdrllWIiutXFzqhEamHP4HgCoh88dTFzb2A6QFljooc"
  }
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


module "pypi" {
  source = "./warehouse"

  zone_id         = "${module.dns.primary_zone_id}"
  domain          = "pypi.org"
  # Because of limitations of the Terraform fastly provider, there must be the same
  # number of entries in any extra_domains across instances of this module, and
  # changing the number of elements in the list requires modifying the module to
  # handle the new number of elements.
  extra_domains   = ["www.pypi.org", "pypi.io", "www.pypi.io", "warehouse.python.org"]
  backend         = "warehouse.cmh1.psfhosted.org"
  mirror          = "mirror.dub1.pypi.io"
  s3_logging_keys = "${var.fastly_s3_logging}"

  fastly_endpoints = "${local.fastly_endpoints}"
  domain_map       = "${local.domain_map}"
}


module "file-hosting" {
  source = "./file-hosting"

  zone_id          = "${module.dns.user_content_zone_id}"
  domain           = "files.pythonhosted.org"
  conveyor_address = "conveyor.cmh1.psfhosted.org"
  files_bucket     = "pypi-files"
  mirror           = "mirror.dub1.pypi.io"

  linehaul = {
    address = "linehaul01.iad1.psf.io"
    port    = 48175
    token   = "${var.linehaul_token}"
  }

  fastly_endpoints = "${local.fastly_endpoints}"
  domain_map       = "${local.domain_map}"
}


module "docs-hosting" {
  source = "./docs-hosting"

  zone_id          = "${module.dns.user_content_zone_id}"
  domain           = "pythonhosted.org"
  conveyor_address = "conveyor.cmh1.psfhosted.org"

  fastly_endpoints = "${local.fastly_endpoints}"
  domain_map       = "${local.domain_map}"
}


output "nameservers" { value = ["${module.dns.nameservers}"] }
output "ses_delivery_topic" { value = "${module.email.delivery_topic}" }
