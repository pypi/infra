variable "zone_id" { type = "string" }
variable "domain" { type = "string" }
variable "extra_domains" { type = "list" }
variable "backend" { type = "string" }
variable "mirror" { type = "string" }
variable "s3_logging_keys" { type = "map" }

variable "fastly_endpoints" { type = "map" }
variable "domain_map" { type = "map" }


locals {
  apex_domain = "${length(split(".", var.domain)) > 2 ? false : true}"
}


resource "fastly_service_v1" "pypi" {
  name = "PyPI"

  domain { name = "${var.domain}" }

  # Extra Domains
  domain { name = "${var.extra_domains[0]}" }
  domain { name = "${var.extra_domains[1]}" }
  domain { name = "${var.extra_domains[2]}" }
  domain { name = "${var.extra_domains[3]}" }

  backend {
    name             = "Application"
    shield           = "iad-va-us"

    healthcheck      = "Application Health"

    address           = "${var.backend}"
    port              = 443
    use_ssl           = true
    ssl_cert_hostname = "${var.backend}"
    ssl_sni_hostname  = "${var.backend}"
  }

  backend {
    name              = "Mirror"
    auto_loadbalance  = false
    shield            = "london_city-uk"

    request_condition = "Primary Failure (Mirror-able)"
    healthcheck       = "Mirror Health"

    address           = "${var.mirror}"
    port              = 443
    use_ssl           = true
    ssl_cert_hostname = "${var.mirror}"
    ssl_sni_hostname  = "${var.mirror}"
  }

  healthcheck {
    name   = "Application Health"

    host   = "${var.domain}"
    method = "GET"
    path   = "/_health/"

    check_interval = 3000
    timeout = 2000
    threshold = 2
    initial = 2
    window = 4
  }

  healthcheck {
    name   = "Mirror Health"

    host   = "${var.domain}"
    method = "GET"
    path   = "/last-modified"
  }

  vcl {
    name    = "Main"
    content = "${file("${path.module}/vcl/main.vcl")}"
    main    = true
  }

  s3logging {
    name           = "S3 Logs"

    format         = "%h \"%{now}V\" %l \"%{req.request}V %{req.url}V\" %{req.proto}V %>s %{resp.http.Content-Length}V %{resp.http.age}V \"%{resp.http.x-cache}V\" \"%{resp.http.x-cache-hits}V\" \"%{req.http.content-type}V\" \"%{req.http.accept-language}V\" \"%{cstr_escape(req.http.user-agent)}V\""
    format_version = 2
    gzip_level     = 9

    s3_access_key  = "${var.s3_logging_keys["access_key"]}"
    s3_secret_key  = "${var.s3_logging_keys["secret_key"]}"
    domain         = "s3-eu-west-1.amazonaws.com"
    bucket_name    = "psf-fastly-logs-eu-west-1"
    path           = "/pypi-org/%Y/%m/%d/"
  }

  response_object {
    name              = "Backend Down"
    request_condition = "Backend Failure (General)"

    status            = 503
    response          = "Service Unavailable"
    content           = "${file("${path.module}/html/error.html")}"
    content_type      = "text/html; charset=utf-8"
  }

  condition {
    name      = "Primary Failure (Mirror-able)"
    type      = "REQUEST"
    statement = "(!req.backend.healthy || req.restarts > 0) && (req.url ~ \"^/simple/\" || req.url ~ \"^/pypi/[^/]+(/[^/]+)?/json$\")"
    priority  = 1
  }

  condition {
    name      = "Backend Failure (General)"
    type      = "REQUEST"
    statement = "!req.backend.healthy"
    priority  = 2
  }
}


resource "aws_route53_record" "primary" {
  zone_id = "${var.zone_id}"
  name    = "${var.domain}"
  type    = "${local.apex_domain ? "A" : "CNAME"}"
  ttl     = 60
  records = ["${var.fastly_endpoints["${join("_", list(var.domain_map[var.domain], local.apex_domain ? "A" : "CNAME"))}"]}"]
}


resource "aws_route53_record" "primary-ipv6" {
  count   = "${local.apex_domain ? 1 : 0}"
  zone_id = "${var.zone_id}"
  name    = "${var.domain}"
  type    = "AAAA"
  ttl     = 60
  records = ["${var.fastly_endpoints["${join("_", list(var.domain_map[var.domain], "AAAA"))}"]}"]
}
