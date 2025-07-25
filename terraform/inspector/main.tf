variable "name" { type = string }
variable "zone_id" { type = string }
variable "domain" { type = string }
variable "backend" { type = string }

variable "ngwaf_site_name" { type = string }
variable "ngwaf_email" { type = string }
variable "ngwaf_token" { type = string }
variable "activate_ngwaf_service" { type = bool }
variable "edge_security_dictionary" { type = string }
variable "fastly_key" { type = string }
variable "ngwaf_percent_enabled" { type = number }

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

  # NGWAF
  dynamic "dictionary" {
    for_each = var.activate_ngwaf_service ? [1] : []
    content {
      name          = var.edge_security_dictionary
      force_destroy = true
    }
  }

  dynamic "dynamicsnippet" {
    for_each = var.activate_ngwaf_service ? [1] : []
    content {
      name     = "ngwaf_config_init"
      type     = "init"
      priority = 0
    }
  }

  dynamic "dynamicsnippet" {
    for_each = var.activate_ngwaf_service ? [1] : []
    content {
      name     = "ngwaf_config_miss"
      type     = "miss"
      priority = 9000
    }
  }

  dynamic "dynamicsnippet" {
    for_each = var.activate_ngwaf_service ? [1] : []
    content {
      name     = "ngwaf_config_pass"
      type     = "pass"
      priority = 9000
    }
  }

  dynamic "dynamicsnippet" {
    for_each = var.activate_ngwaf_service ? [1] : []
    content {
      name     = "ngwaf_config_deliver"
      type     = "deliver"
      priority = 9000
    }
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
  records = ["dualstack.python.map.fastly.net"]
}