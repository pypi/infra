variable "zone_id" { type = "string" }
variable "domain" { type = "string" }
variable "conveyor_address" { type = "string" }
variable "files_bucket" { type = "string" }
variable "linehaul" { type = "map" }


resource "aws_route53_record" "files" {
  zone_id = "${var.zone_id}"
  name    = "${var.domain}"
  type    = "CNAME"
  ttl     = 60
  records = ["r.shared.global.fastly.net"]
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
  }

  backend {
    name              = "S3"
    auto_loadbalance  = false
    shield            = "sea-wa-us"

    request_condition = "Package File"

    address           = "${var.files_bucket}.s3.amazonaws.com"
    port              = 443
    use_ssl           = true
    ssl_cert_hostname = "${var.files_bucket}.s3.amazonaws.com"
    ssl_sni_hostname  = "${var.files_bucket}.s3.amazonaws.com"
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

  condition {
    name      = "Package File"
    type      = "REQUEST"
    statement = "req.url ~ \"^/packages/[a-f0-9]{2}/[a-f0-9]{2}/[a-f0-9]{60}/\""
    priority  = 5
  }

  condition {
    name      = "Never"
    type      = "RESPONSE"
    statement = "req.http.Fastly-Client-IP == \"127.0.0.1\" && req.http.Fastly-Client-IP != \"127.0.0.1\""
  }
}
