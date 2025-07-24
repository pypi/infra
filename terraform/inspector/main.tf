variable "name" { type = string }
variable "zone_id" { type = string }
variable "domain" { type = string }
variable "backend" { type = string }

resource "fastly_service_vcl" "inspector" {
  name     = var.name
  activate = true

  domain {
    name = var.domain
  }

  backend {
    name             = "PyPI Inspector"
    shield           = "iad-va-us"
    auto_loadbalance = true

    healthcheck = "Inspector Health"

    address           = var.backend
    port              = 443
    use_ssl           = true
    ssl_cert_hostname = var.backend
    ssl_sni_hostname  = var.backend

    connect_timeout       = 5000
    first_byte_timeout    = 60000
    between_bytes_timeout = 15000
    error_threshold       = 5
  }

  healthcheck {
    name = "Inspector Health"

    host   = var.domain
    method = "GET"
    path   = "/_health"

    check_interval = 15000
    timeout        = 5000
    threshold      = 3
    initial        = 4
    window         = 5
  }

  lifecycle {
    ignore_changes = [
      product_enablement,
    ]
  }
}

resource "aws_route53_record" "primary" {
  zone_id = var.zone_id
  name    = var.domain
  type    = "CNAME"
  ttl     = 3600
  records = ["inspector.ingress.us-east-2.pypi.io"]
}