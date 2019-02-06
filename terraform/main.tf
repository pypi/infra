variable "linehaul_token" { type = "string" }
variable "linehaul_creds" { type = "string" }
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

  caa_report_uri = "mailto:infrastructure-staff@python.org"
  caa_issuers = [
    "amazon.com",
    "globalsign.com",
    "Digicert.com",
  ]

  apex_txt = [
    "google-site-verification=YdrllWIiutXFzqhEamHP4HgCoh88dTFzb2A6QFljooc",
    "google-site-verification=ZI8zeHE6SWuJljW3f4csGetjOWo4krvjf13tdORsH4Y",
    "v=spf1 include:_spf.google.com include:amazonses.com -all"
  ]
}


module "gmail" {
  source = "./gmail"

  zone_id  = "${module.dns.primary_zone_id}"
  domain = "pypi.org"

  dkim_host_name = "google._domainkey"
  dkim_txt_record = "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCS6JrwMkzjpDb1I6QbSxhiVeU9Fl2G1RJYtBR58Ult1+6pezNY9krZ8waNWcymaH8rvqlbKicPuwmzDSamC6lZhQZc05w5moDIF5lmu+Ji9jcQF679K1DP1nwy6B3ro4//62P0/88aFRRK+k+cth3ZQsSqNnxf9uQYykt75O7p/QIDAQAB"
}


module "email" {
  source = "./email"
  providers = {
    "aws" = "aws"
    "aws.email" = "aws.us-west-2"
  }

  name         = "pypi"
  display_name = "PyPI"
  zone_id      = "${module.dns.primary_zone_id}"
  domain       = "pypi.org"
  dmarc        = "mailto:re+ahhqsxbwmkl@dmarc.postmarkapp.com"
  hook_url     = "https://pypi.org/_/ses-hook/"
}


module "testpypi-email" {
  source = "./email"
  providers = {
    "aws" = "aws"
    "aws.email" = "aws.us-west-2"
  }

  name         = "testpypi"
  display_name = "TestPyPI"
  zone_id      = "${module.dns.primary_zone_id}"
  domain       = "test.pypi.org"
  dmarc        = "mailto:re+qjfavuizyth@dmarc.postmarkapp.com"
  hook_url     = "https://test.pypi.org/_/ses-hook/"
}


module "pypi" {
  source = "./warehouse"

  name            = "PyPI"
  zone_id         = "${module.dns.primary_zone_id}"
  domain          = "pypi.org"
  # Because of limitations of the Terraform fastly provider, there must be the same
  # number of entries in any extra_domains across instances of this module, and
  # changing the number of elements in the list requires modifying the module to
  # handle the new number of elements.
  extra_domains   = ["www.pypi.org", "pypi.python.org", "pypi.io", "www.pypi.io", "warehouse.python.org"]
  backend         = "warehouse.cmh1.psfhosted.org"
  mirror          = "mirror.dub1.pypi.io"
  linehaul_bucket = "linehaul-logs"
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
  s3_logging_keys = "${var.fastly_s3_logging}"

  linehaul = {
    address = "linehaul01.iad1.psf.io"
    port    = 48175
    token   = "${var.linehaul_token}"
  }

  fastly_endpoints = "${local.fastly_endpoints}"
  domain_map       = "${local.domain_map}"
}

module "linehaul" {
  source = "./linehaul"

  bucket_name = "linehaul-logs"
  queue_name  = "linehaul-log-events"
  bigquery_creds = "${var.linehaul_creds}"
  bigquery_table = "the-psf.pypi.simple_requests"
}


module "docs-hosting" {
  source = "./docs-hosting"

  zone_id          = "${module.dns.user_content_zone_id}"
  domain           = "pythonhosted.org"
  conveyor_address = "conveyor.cmh1.psfhosted.org"

  fastly_endpoints = "${local.fastly_endpoints}"
  domain_map       = "${local.domain_map}"
}

module "lambda-deployer" {
  source = "./lambda-deployer"

  bucket_name = "pypi-lambdas"
  queue_name  = "pypi-lambdas-events"

  functions = [
    "linehaul",
  ]
}


output "nameservers" { value = ["${module.dns.nameservers}"] }
output "pypi-ses_delivery_topic" { value = "${module.email.delivery_topic}" }
output "testpypi-ses_delivery_topic" { value = "${module.testpypi-email.delivery_topic}" }
