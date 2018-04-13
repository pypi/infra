variable "sitename" { default = "PyPI" }
variable "zone_id" { type = "string" }
variable "domain" { type = "string" }
variable "conveyor_address" { type = "string" }


locals {
  apex_domain = "${length(split(".", var.domain)) > 2 ? false : true}"
  records = {
    A = ["151.101.1.63", "151.101.65.63", "151.101.129.63", "151.101.193.63"]
    AAAA = ["2a04:4e42::319", "2a04:4e42:200::319", "2a04:4e42:400::319", "2a04:4e42:600::319"]
    CNAME = ["dualstack.r.ssl.global.fastly.net"]
  }
}


resource "aws_route53_record" "docs" {
  zone_id = "${var.zone_id}"
  name    = "${var.domain}"
  type    = "${local.apex_domain ? "A" : "CNAME"}"
  ttl     = 60
  records = "${local.records["${local.apex_domain ? "A" : "CNAME"}"]}"
}

resource "aws_route53_record" "docs-ipv6" {
  count = "${local.apex_domain ? 1 : 0}"

  zone_id = "${var.zone_id}"
  name    = "${var.domain}"
  type    = "AAAA"
  ttl     = 60
  records = "${local.records["AAAA"]}"
}


resource "fastly_service_v1" "docs" {
  name        = "${var.sitename} Docs Hosting"
  default_ttl = 86400  # 1 day

  domain { name = "${var.domain}" }

  backend {
    name              = "Conveyor"
    shield            = "iad-va-us"

    address           = "${var.conveyor_address}"
    port              = 443
    use_ssl           = true
    ssl_cert_hostname = "${var.conveyor_address}"
    ssl_sni_hostname  = "${var.conveyor_address}"
  }

  gzip { name = "Default GZIP Policy" }

  vcl {
    name    = "Main"
    content = "${file("${path.module}/vcl/main.vcl")}"
    main    = true
  }
}
