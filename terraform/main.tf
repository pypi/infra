variable "linehaul_gcs_private_key" { type = string }
variable "fastly_s3_logging" { type = map(any) }

locals {
  tags = {
    Application = "PyPI"
    Environment = "Production"
  }
}


locals {
  fastly_endpoints = {
    "python.map.fastly.net_A"     = ["151.101.128.223", "151.101.192.223", "151.101.0.223", "151.101.64.223"]
    "python.map.fastly.net_AAAA"  = ["2a04:4e42:200::223", "2a04:4e42:400::223", "2a04:4e42:600::223", "2a04:4e42::223"]
    "python.map.fastly.net_CNAME" = ["dualstack.python.map.fastly.net"]
  }
  domain_map = {
    "pypi.org"                    = "python.map.fastly.net"
    "test.pypi.org"               = "python.map.fastly.net"
    "pythonhosted.org"            = "python.map.fastly.net"
    "test.pythonhosted.org"       = "python.map.fastly.net"
    "files.pythonhosted.org"      = "python.map.fastly.net"
    "test-files.pythonhosted.org" = "python.map.fastly.net"
    "inspector.pypi.io"           = "python.map.fastly.net"
  }
}


module "dns" {
  source = "./dns"

  tags = local.tags

  primary_domain      = "pypi.org"
  user_content_domain = "pythonhosted.org"

  caa_report_uri = "mailto:infrastructure-staff@python.org"
  caa_issuers = [
    "amazon.com",
    "globalsign.com",
    "letsencrypt.org",
  ]

  apex_txt = [
    "google-site-verification=YdrllWIiutXFzqhEamHP4HgCoh88dTFzb2A6QFljooc",
    "google-site-verification=ZI8zeHE6SWuJljW3f4csGetjOWo4krvjf13tdORsH4Y",
    "v=spf1 include:_spf.google.com include:amazonses.com include:helpscoutemail.com -all"
  ]
}


module "gmail" {
  source = "./gmail"

  zone_id = module.dns.primary_zone_id
  domain  = "pypi.org"

  dkim_host_name  = "google._domainkey"
  dkim_txt_record = "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCS6JrwMkzjpDb1I6QbSxhiVeU9Fl2G1RJYtBR58Ult1+6pezNY9krZ8waNWcymaH8rvqlbKicPuwmzDSamC6lZhQZc05w5moDIF5lmu+Ji9jcQF679K1DP1nwy6B3ro4//62P0/88aFRRK+k+cth3ZQsSqNnxf9uQYykt75O7p/QIDAQAB"
}


module "email" {
  source = "./email"

  name         = "pypi"
  display_name = "PyPI"
  zone_id      = module.dns.primary_zone_id
  domain       = "pypi.org"
  dmarc        = "mailto:re+c026728f02d6@inbound.dmarcdigests.com"
  hook_url     = "https://pypi.org/_/ses-hook/"
}


module "testpypi-email" {
  source = "./email"

  name         = "testpypi"
  display_name = "TestPyPI"
  zone_id      = module.dns.primary_zone_id
  domain       = "test.pypi.org"
  dmarc        = "mailto:re+a1s3u37pyvs@dmarc.postmarkapp.com"
  hook_url     = "https://test.pypi.org/_/ses-hook/"
}


module "pypi" {
  source = "./warehouse"

  name    = "PyPI"
  zone_id = module.dns.primary_zone_id
  domain  = "pypi.org"
  # Note:  the first domain in "extra_domains" gets an XMLRPC exception/bypass in VCL
  extra_domains   = ["pypi.python.org", "www.pypi.org", "pypi.io", "www.pypi.io", "warehouse.python.org"]
  backend         = "warehouse.ingress.us-east-2.pypi.io"
  s3_logging_keys = var.fastly_s3_logging

  warehouse_token   = var.warehouse_token
  warehouse_ip_salt = var.warehouse_ip_salt

  linehaul_enabled = true
  linehaul_gcs = {
    bucket      = "linehaul-logs"
    email       = "linehaul-logs@the-psf.iam.gserviceaccount.com"
    private_key = "${var.linehaul_gcs_private_key}"
  }

  fastly_toppops_enabled = true

  fastly_endpoints = local.fastly_endpoints
  domain_map       = local.domain_map

  # NGWAF
  ngwaf_site_name          = "pypi-prod"
  ngwaf_email              = var.ngwaf_email
  ngwaf_token              = var.ngwaf_token
  activate_ngwaf_service   = true
  edge_security_dictionary = "Edge_Security"
  fastly_key               = var.credentials["fastly"]
  ngwaf_percent_enabled    = 100
  datadog_token            = var.datadog_token
}

module "test-pypi" {
  source = "./warehouse"

  name    = "Test PyPI"
  zone_id = module.dns.primary_zone_id
  domain  = "test.pypi.org"
  # Note:  the first domain in "extra_domains" gets an XMLRPC exception/bypass in VCL
  extra_domains   = ["testpypi.python.org", "test.pypi.io", "warehouse-staging.python.org"]
  backend         = "warehouse-test.ingress.us-east-2.pypi.io"
  s3_logging_keys = var.fastly_s3_logging

  warehouse_token   = var.test_pypi_warehouse_token
  warehouse_ip_salt = var.warehouse_ip_salt

  linehaul_enabled = false
  linehaul_gcs = {
    bucket      = "linehaul-logs-staging"
    email       = "linehaul-logs@the-psf.iam.gserviceaccount.com"
    private_key = "${var.linehaul_gcs_private_key}"
  }

  fastly_toppops_enabled = false

  fastly_endpoints = local.fastly_endpoints
  domain_map       = local.domain_map

  # NGWAF
  ngwaf_site_name          = "pypi-test"
  ngwaf_email              = var.ngwaf_email
  ngwaf_token              = var.ngwaf_token
  activate_ngwaf_service   = true
  edge_security_dictionary = "Edge_Security"
  fastly_key               = var.credentials["fastly"]
  ngwaf_percent_enabled    = 100
  datadog_token            = var.datadog_token
}

module "file-hosting" {
  source = "./file-hosting"

  zone_id             = module.dns.user_content_zone_id
  domain              = "files.pythonhosted.org"
  fastly_service_name = "PyPI File Hosting"
  conveyor_address    = "conveyor.ingress.us-east-2.pypi.io"
  files_bucket        = "pypi-files"
  s3_logging_keys     = var.fastly_s3_logging
  datadog_token       = var.datadog_token
  x_pypi_admin_token  = var.x_pypi_admin_token

  aws_access_key_id     = var.aws_access_key_id
  aws_secret_access_key = var.aws_secret_access_key
  gcs_access_key_id     = var.gcs_access_key_id
  gcs_secret_access_key = var.gcs_secret_access_key

  linehaul_enabled = true
  linehaul_gcs = {
    bucket      = "linehaul-logs"
    email       = "linehaul-logs@the-psf.iam.gserviceaccount.com"
    private_key = "${var.linehaul_gcs_private_key}"
  }

  fastly_toppops_enabled = true

  fastly_endpoints = local.fastly_endpoints
  domain_map       = local.domain_map
}


module "test-file-hosting" {
  source = "./file-hosting"

  zone_id             = module.dns.user_content_zone_id
  domain              = "test-files.pythonhosted.org"
  fastly_service_name = "Test PyPI File Hosting"
  conveyor_address    = "test-conveyor.ingress.us-east-2.pypi.io"
  files_bucket        = "pypi-files-staging"
  s3_logging_keys     = var.fastly_s3_logging
  datadog_token       = var.datadog_token
  x_pypi_admin_token  = var.x_pypi_admin_token

  aws_access_key_id     = var.aws_access_key_id
  aws_secret_access_key = var.aws_secret_access_key
  gcs_access_key_id     = var.gcs_access_key_id
  gcs_secret_access_key = var.gcs_secret_access_key

  linehaul_enabled = false
  linehaul_gcs = {
    bucket      = "linehaul-logs-staging"
    email       = "linehaul-logs@the-psf.iam.gserviceaccount.com"
    private_key = "${var.linehaul_gcs_private_key}"
  }

  fastly_toppops_enabled = false

  fastly_endpoints = local.fastly_endpoints
  domain_map       = local.domain_map
}


module "docs-hosting" {
  source = "./docs-hosting"

  sitename         = "PyPI"
  zone_id          = module.dns.user_content_zone_id
  domain           = "pythonhosted.org"
  conveyor_address = "conveyor.ingress.us-east-2.pypi.io"

  fastly_endpoints = local.fastly_endpoints
  domain_map       = local.domain_map
}

module "test-docs-hosting" {
  source = "./docs-hosting"

  sitename         = "Test PyPI"
  zone_id          = module.dns.user_content_zone_id
  domain           = "test.pythonhosted.org"
  conveyor_address = "test-conveyor.ingress.us-east-2.pypi.io"

  fastly_endpoints = local.fastly_endpoints
  domain_map       = local.domain_map
}

module "test-pypi-camo" {
  source = "./image-proxy"

  sitename        = "Test PyPI Camo"
  domain          = "testpypi-camo.global.ssl.fastly.net"
  backend_address = "warehouse-test-camo.ingress.us-east-2.pypi.io"
}

module "pypi-camo" {
  source = "./image-proxy"

  sitename        = "PyPI Camo"
  domain          = "pypi-camo.global.ssl.fastly.net"
  backend_address = "warehouse-camo.ingress.us-east-2.pypi.io"
}

# inspector dns zone is different fromd ns module one
data "aws_route53_zone" "pypi_io" {
  name = "pypi.io"
}

module "inspector" {
  source = "./inspector"

  name    = "Inspector"
  zone_id = data.aws_route53_zone.pypi_io.zone_id
  domain  = "inspector.pypi.io"
  backend = "inspector.ingress.us-east-2.pypi.io"

  # NGWAF
  ngwaf_site_name          = "pypi-inspector"
  ngwaf_email              = var.ngwaf_email
  ngwaf_token              = var.ngwaf_token
  activate_ngwaf_service   = false
  edge_security_dictionary = "Edge_Security"
  fastly_key               = var.credentials["fastly"]
  ngwaf_percent_enabled    = 100
}

output "nameservers" { value = module.dns.nameservers }
output "pypi-ses_delivery_topic" { value = module.email.delivery_topic }
output "testpypi-ses_delivery_topic" { value = module.testpypi-email.delivery_topic }
