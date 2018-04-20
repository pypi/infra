variable "zone_id" { type = "string" }
variable "domain" { type = "string" }
variable "conveyor_address" { type = "string" }
variable "files_bucket" { type = "string" }
variable "mirror" { type = "string" }
variable "linehaul" { type = "map" }
variable "s3_logging_keys" { type = "map" }

variable "fastly_endpoints" { type = "map" }
variable "domain_map" { type = "map" }


locals {
  apex_domain = "${length(split(".", var.domain)) > 2 ? false : true}"
}


resource "fastly_service_v1" "files" {
  name = "PyPI File Hosting"

  domain {
    name = "${var.domain}"
  }

  backend {
    name              = "Conveyor"
    shield            = "iad-va-us"

    address           = "${var.conveyor_address}"
    port              = 443
    use_ssl           = true
    ssl_cert_hostname = "${var.conveyor_address}"
    ssl_sni_hostname  = "${var.conveyor_address}"

    connect_timeout   = 3000
    error_threshold   = 5
  }

  backend {
    name              = "S3"
    auto_loadbalance  = false
    shield            = "sea-wa-us"

    request_condition = "Package File"
    healthcheck       = "S3 Health"

    address           = "${var.files_bucket}.s3.amazonaws.com"
    port              = 443
    use_ssl           = true
    ssl_cert_hostname = "${var.files_bucket}.s3.amazonaws.com"
    ssl_sni_hostname  = "${var.files_bucket}.s3.amazonaws.com"

    connect_timeout   = 3000
    error_threshold   = 5
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

    connect_timeout   = 3000
    error_threshold   = 5
  }

  healthcheck {
    name   = "S3 Health"

    host   = "${var.files_bucket}.s3.amazonaws.com"
    method = "GET"
    path   = "/_health.txt"

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

    check_interval = 3000
    timeout = 2000
    threshold = 2
    initial = 2
    window = 4
  }


  vcl {
    name    = "Main"
    content = "${file("${path.module}/vcl/main.vcl")}"
    main    = true
  }

  syslog {
    name         = "linehaul"
    address      = "${var.linehaul["address"]}"
    port         = "${var.linehaul["port"]}"
    token        = "${var.linehaul["token"]}"

    use_tls      = true
    tls_hostname = "linehaul.psf.io"
    tls_ca_cert  = "${replace(file("${path.module}/certs/linehaul.pem"), "/\n$/", "")}"

    format_version = "2"

    # We actually never want this to log by default, we'll manually log to it in
    # our VCL, but we need to set it here so that the system is configured to
    # have it as a logger.
    response_condition = "Never"
  }

  s3logging {
    name           = "S3 Error Logs"

    format         = "%h \"%{now}V\" %l \"%{req.request}V %{req.url}V\" %{req.proto}V %>s %{resp.http.Content-Length}V %{resp.http.age}V \"%{resp.http.x-cache}V\" \"%{resp.http.x-cache-hits}V\" \"%{req.http.content-type}V\" \"%{req.http.accept-language}V\" \"%{cstr_escape(req.http.user-agent)}V\" %D \"%{fastly_info.state}V\""
    format_version = 2
    gzip_level     = 9

    period         = 60
    response_condition = "5xx Error"

    s3_access_key  = "${var.s3_logging_keys["access_key"]}"
    s3_secret_key  = "${var.s3_logging_keys["secret_key"]}"
    domain         = "s3-eu-west-1.amazonaws.com"
    bucket_name    = "psf-fastly-logs-eu-west-1"
    path           = "/files-pythonhosted-org-errors/%Y/%m/%d/%H/%M/"
  }


  condition {
    name      = "Package File"
    type      = "REQUEST"
    statement = "req.url ~ \"^/packages/[a-f0-9]{2}/[a-f0-9]{2}/[a-f0-9]{60}/\""
    priority  = 1
  }

  condition {
    name      = "Primary Failure (Mirror-able)"
    type      = "REQUEST"
    statement = "(!req.backend.healthy || req.restarts > 0) && req.url ~ \"^/packages/[a-f0-9]{2}/[a-f0-9]{2}/[a-f0-9]{60}/\""
    priority  = 2
  }

  condition {
    name = "5xx Error"
    type = "RESPONSE"
    statement = "(resp.status >= 500 && resp.status < 600)"
  }

  condition {
    name      = "Never"
    type      = "RESPONSE"
    statement = "req.http.Fastly-Client-IP == \"127.0.0.1\" && req.http.Fastly-Client-IP != \"127.0.0.1\""
  }
}


resource "aws_route53_record" "files" {
  zone_id = "${var.zone_id}"
  name    = "${var.domain}"
  type    = "${local.apex_domain ? "A" : "CNAME"}"
  ttl     = 60
  records = ["${var.fastly_endpoints["${join("_", list(var.domain_map[var.domain], local.apex_domain ? "A" : "CNAME"))}"]}"]
}


resource "aws_route53_record" "files-ipv6" {
  count = "${local.apex_domain ? 1 : 0}"

  zone_id = "${var.zone_id}"
  name    = "${var.domain}"
  type    = "AAAA"
  ttl     = 60
  records = ["${var.fastly_endpoints["${join("_", list(var.domain_map[var.domain], "AAAA"))}"]}"]
}
