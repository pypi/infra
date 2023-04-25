variable "name" { type = string }
variable "zone_id" { type = string }
variable "domain" { type = string }
variable "extra_domains" { type = list(any) }
variable "backend" { type = string }
variable "mirror" { type = string }
variable "s3_logging_keys" { type = map(any) }
variable "linehaul_enabled" { type = bool }
variable "linehaul_gcs" { type = map(any) }
variable "warehouse_token" { type = string }
variable "warehouse_ip_salt" { type = string }

variable "fastly_endpoints" { type = map(any) }
variable "domain_map" { type = map(any) }


locals {
  apex_domain = length(split(".", var.domain)) > 2 ? false : true
}


resource "fastly_service_vcl" "pypi" {
  name     = var.name
  # Set to false for spicy changes
  activate = true

  domain { name = var.domain }

  # Extra Domains

  dynamic "domain" {
    for_each = var.extra_domains
    content {
      name = domain.value
    }
  }

  snippet {
    content  = "set req.http.Warehouse-Token = \"${var.warehouse_token}\";"
    name     = "Warehouse Token"
    priority = 100
    type     = "recv"
  }

  snippet {
    content  = "set var.Warehouse-Ip-Salt = \"${var.warehouse_ip_salt}\";"
    name     = "Warehouse IP Salt"
    priority = 100
    type     = "recv"
  }

  snippet {
    name     = "Linehaul"
    priority = 100
    type     = "log"
    content  = <<-EOT
        declare local var.Ship-Logs-To-Line-Haul BOOL;
        set var.Ship-Logs-To-Line-Haul = ${var.linehaul_enabled};
    EOT
  }

  backend {
    name             = "Application"
    shield           = "iad-va-us"
    auto_loadbalance = true

    healthcheck = "Application Health"

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

  backend {
    name             = "Mirror"
    auto_loadbalance = false
    shield           = "london_city-uk"

    request_condition = "Primary Failure (Mirror-able)"
    healthcheck       = "Mirror Health"

    address           = var.mirror
    port              = 443
    use_ssl           = true
    ssl_cert_hostname = var.mirror
    ssl_sni_hostname  = var.mirror

    connect_timeout       = 5000
    first_byte_timeout    = 60000
    between_bytes_timeout = 15000
    error_threshold       = 5
  }

  healthcheck {
    name = "Application Health"

    host   = var.domain
    method = "GET"
    path   = "/_health/"

    check_interval = 6000
    timeout        = 4000
    threshold      = 2
    initial        = 2
    window         = 4
  }

  healthcheck {
    name = "Mirror Health"

    host   = var.domain
    method = "GET"
    path   = "/last-modified"

    check_interval = 3000
    timeout        = 2000
    threshold      = 2
    initial        = 2
    window         = 4
  }

  dictionary {
    name = "masked_ip_blocklist"
  }

  condition {
    name      = "masked_ip_blocklist"
    type      = "REQUEST"
    priority  = 0
    statement = "table.contains(masked_ip_blocklist, req.http.Warehouse-Hashed-IP)"
  }

  vcl {
    name    = "Main"
    content = templatefile(
        "${path.module}/vcl/main.vcl",
        {
            pretty_503 = file("${path.module}/html/error.html")
            domain = var.domain
            extra_domains = var.extra_domains
        }
    )
    main    = true
  }

  logging_s3 {
    name = "S3 Logs"

    format         = "%h \"%%{now}V\" %l \"%%{req.request}V %%{req.url}V\" %%{req.proto}V %>s %%{resp.http.Content-Length}V %%{resp.http.age}V \"%%{resp.http.x-cache}V\" \"%%{resp.http.x-cache-hits}V\" \"%%{req.http.content-type}V\" \"%%{req.http.accept-language}V\" \"%%{cstr_escape(req.http.user-agent)}V\""
    format_version = 2
    gzip_level     = 9

    s3_access_key = var.s3_logging_keys["access_key"]
    s3_secret_key = var.s3_logging_keys["secret_key"]
    domain        = "s3-eu-west-1.amazonaws.com"
    bucket_name   = "psf-fastly-logs-eu-west-1"
    path          = "/${replace(var.domain, ".", "-")}/%Y/%m/%d/"
  }

  logging_s3 {
    name = "S3 Error Logs"

    format         = "%h \"%%{now}V\" %l \"%%{req.request}V %%{req.url}V\" %%{req.proto}V %>s %%{resp.http.Content-Length}V %%{resp.http.age}V \"%%{resp.http.x-cache}V\" \"%%{resp.http.x-cache-hits}V\" \"%%{req.http.content-type}V\" \"%%{req.http.accept-language}V\" \"%%{cstr_escape(req.http.user-agent)}V\" %D \"%%{fastly_info.state}V\" \"%%{req.restarts}V\" \"%%{req.backend}V\""
    format_version = 2
    gzip_level     = 9

    period             = 60
    response_condition = "5xx Error"

    s3_access_key = var.s3_logging_keys["access_key"]
    s3_secret_key = var.s3_logging_keys["secret_key"]
    domain        = "s3-eu-west-1.amazonaws.com"
    bucket_name   = "psf-fastly-logs-eu-west-1"
    path          = "/${replace(var.domain, ".", "-")}-errors/%Y/%m/%d/%H/%M/"
  }

  logging_gcs {
    name             = "Linehaul GCS"
    bucket_name      = var.linehaul_gcs["bucket"]
    path             = "simple/%Y/%m/%d/%H/%M/"
    message_type     = "blank"
    format           = "simple|%%{now}V|%%{client.geo.country_code}V|%%{req.url.path}V|%%{tls.client.protocol}V|%%{tls.client.cipher}V||||%%{req.http.user-agent}V"
    timestamp_format = "%Y-%m-%dT%H:%M:%S.000"
    gzip_level       = 9
    period           = 120

    user       = var.linehaul_gcs["email"]
    secret_key = var.linehaul_gcs["private_key"]

    response_condition = "Linehaul Log"
  }

  response_object {
    name              = "Bandersnatch User-Agent prohibited"
    status            = 403
    content           = "Bandersnatch version no longer supported, upgrade to 1.4+"
    content_type      = "text/plain"
    request_condition = "Bandersnatch User-Agent prohibited"
  }

  response_object {
    name              = "masked_ip_blocklist"
    request_condition = "masked_ip_blocklist"
    status            = 403
    response          = "Forbidden"
    content           = "Your IP Address has been temporarily blocked."
    content_type      = "text/plain"
  }

  condition {
    name      = "Primary Failure (Mirror-able)"
    type      = "REQUEST"
    statement = "(!req.backend.healthy || req.restarts > 0) && (req.url ~ \"^/simple/\" || req.url ~ \"^/pypi/[^/]+(/[^/]+)?/json$\")"
    priority  = 1
  }

  condition {
    name      = "5xx Error"
    type      = "RESPONSE"
    statement = "(resp.status >= 500 && resp.status < 600)"
  }

  condition {
    name      = "Bandersnatch User-Agent prohibited"
    type      = "REQUEST"
    statement = "req.http.user-agent ~ \"bandersnatch/1\\.(0|1|2|3)\\ \""
  }

  condition {
    name      = "Linehaul Log"
    type      = "RESPONSE"
    statement = "var.Ship-Logs-To-Line-Haul && !req.http.Fastly-FF && req.url.path ~ \"^/simple/.+/\" && req.request == \"GET\" && http_status_matches(resp.status, \"200,304\")"
  }

  condition {
    name      = "Never"
    type      = "RESPONSE"
    statement = "req.http.Fastly-Client-IP == \"127.0.0.1\" && req.http.Fastly-Client-IP != \"127.0.0.1\""
  }
}


resource "aws_route53_record" "primary" {
  zone_id = var.zone_id
  name    = var.domain
  type    = local.apex_domain ? "A" : "CNAME"
  ttl     = 86400
  records = var.fastly_endpoints[join("_", concat([var.domain_map[var.domain]], [local.apex_domain ? "A" : "CNAME"]))]
}


resource "aws_route53_record" "primary-ipv6" {
  count   = local.apex_domain ? 1 : 0
  zone_id = var.zone_id
  name    = var.domain
  type    = "AAAA"
  ttl     = 86400
  records = var.fastly_endpoints[join("_", [var.domain_map[var.domain], "AAAA"])]
}
