variable "sitename" { default = "PyPI" }
variable "zone_id" { type = string }
variable "domain" { type = string }
variable "conveyor_address" { type = string }

variable "fastly_endpoints" { type = map(any) }
variable "domain_map" { type = map(any) }


locals {
  apex_domain = length(split(".", var.domain)) > 2 ? false : true
}


resource "fastly_service_vcl" "docs" {
  name        = "${var.sitename} Docs Hosting"
  default_ttl = 86400 # 1 day

  domain { name = var.domain }

  backend {
    name             = "Conveyor"
    shield           = "iad-va-us"
    auto_loadbalance = true

    address           = var.conveyor_address
    port              = 443
    use_ssl           = true
    ssl_cert_hostname = var.conveyor_address
    ssl_sni_hostname  = var.conveyor_address
  }

  gzip { name = "Default GZIP Policy" }

  vcl {
    name    = "Main"
    content = file("${path.module}/vcl/main.vcl")
    main    = true
  }
}


resource "aws_route53_record" "docs" {
  zone_id = var.zone_id
  name    = var.domain
  type    = local.apex_domain ? "A" : "CNAME"
  ttl     = 86400
  records = var.fastly_endpoints[join("_", [var.domain_map[var.domain], local.apex_domain ? "A" : "CNAME"])]
}


resource "aws_route53_record" "docs-ipv6" {
  count = local.apex_domain ? 1 : 0

  zone_id = var.zone_id
  name    = var.domain
  type    = "AAAA"
  ttl     = 86400
  records = var.fastly_endpoints[join("_", [var.domain_map[var.domain], "AAAA"])]
}
