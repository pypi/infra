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
  # Inspection HTML includes mutable PyPI status; origin cache headers take precedence.
  default_ttl = 60

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
    path   = "/_health/"

    check_interval = 15000
    timeout        = 5000
    threshold      = 3
    initial        = 4
    window         = 5
  }

  request_setting {
    name          = "HTTPS and fresh status"
    force_ssl     = true
    max_stale_age = 0
  }

  condition {
    name = "Uncacheable request"
    type = "REQUEST"
    # Keep the default cache key, including the homepage's ?project= query.
    statement = "req.url.path == \"/_health/\" || req.http.Authorization || (req.request != \"GET\" && req.request != \"HEAD\" && req.request != \"FASTLYPURGE\")"
  }

  request_setting {
    name              = "Pass uncacheable requests"
    request_condition = "Uncacheable request"
    action            = "pass"
  }

  condition {
    name      = "Uncacheable response"
    type      = "CACHE"
    statement = "beresp.status != 200 || beresp.http.Set-Cookie || beresp.http.Cache-Control ~ \"(?i)(private|no-store|no-cache)\" || beresp.http.Surrogate-Control ~ \"(?i)(private|no-store|no-cache)\""
  }

  cache_setting {
    name            = "Pass uncacheable responses"
    cache_condition = "Uncacheable response"
    action          = "pass"
  }

  header {
    name        = "Require authenticated purges"
    type        = "request"
    action      = "set"
    destination = "http.Fastly-Purge-Requires-Auth"
    source      = "\"1\""
  }

  # Support whole-app purges while leaving any future origin tags intact.
  header {
    name          = "Inspector purge tag"
    type          = "cache"
    action        = "set"
    destination   = "http.Surrogate-Key"
    source        = "\"inspector\""
    ignore_if_set = true
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