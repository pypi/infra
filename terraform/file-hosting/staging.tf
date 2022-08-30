resource "fastly_service_vcl" "files_staging" {
  name     = "PyPI Staging File Hosting"
  # Set to false for spicy changes
  activate = true

  domain {
    name = var.staging_domain
  }

  snippet {
    name     = "GCS"
    priority = 100
    type     = "recv"
    content  = <<-EOT
        set var.GCS-Access-Key-ID = "${var.gcs_access_key_id}";
        set var.GCS-Secret-Access-Key = "${var.gcs_secret_access_key}";
        set var.GCS-Bucket-Name = "${var.files_bucket}";
    EOT
  }

  snippet {
    name     = "AWS"
    priority = 100
    type     = "recv"
    content  = <<-EOT
        set var.AWS-Access-Key-ID = "${var.aws_access_key_id}";
        set var.AWS-Secret-Access-Key = "${var.aws_secret_access_key}";
        set var.S3-Bucket-Name = "${var.files_bucket}";
    EOT
  }

  backend {
    name             = "Conveyor"
    auto_loadbalance = true
    shield           = "iad-va-us"

    address           = var.conveyor_address
    port              = 443
    use_ssl           = true
    ssl_cert_hostname = var.conveyor_address
    ssl_sni_hostname  = var.conveyor_address

    connect_timeout       = 5000
    first_byte_timeout    = 60000
    between_bytes_timeout = 15000
    error_threshold       = 5
  }

  backend {
    name             = "GCS"
    auto_loadbalance = false
    shield           = "bfi-wa-us"

    request_condition = "Package File"
    healthcheck       = "GCS Health"

    address           = "${var.files_bucket}.storage.googleapis.com"
    port              = 443
    use_ssl           = true
    ssl_cert_hostname = "${var.files_bucket}.storage.googleapis.com"
    ssl_sni_hostname  = "${var.files_bucket}.storage.googleapis.com"

    connect_timeout       = 5000
    first_byte_timeout    = 60000
    between_bytes_timeout = 15000
    error_threshold       = 5
  }

  backend {
    name              = "S3"
    auto_loadbalance  = false
    request_condition = "NeverReq"
    shield            = "bfi-wa-us"

    healthcheck = "S3 Health"

    address           = "${var.files_bucket}.s3.amazonaws.com"
    port              = 443
    use_ssl           = true
    ssl_cert_hostname = "${var.files_bucket}.s3.amazonaws.com"
    ssl_sni_hostname  = "${var.files_bucket}.s3.amazonaws.com"

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

    connect_timeout = 3000
    error_threshold = 5
  }

  healthcheck {
    name = "GCS Health"

    host   = "${var.files_bucket}.storage.googleapis.com"
    method = "GET"
    path   = "/_health.txt"

    check_interval = 3000
    timeout        = 2000
    threshold      = 2
    initial        = 2
    window         = 4
  }

  healthcheck {
    name = "S3 Health"

    host   = "${var.files_bucket}.s3.amazonaws.com"
    method = "GET"
    path   = "/_health.txt"

    check_interval = 3000
    timeout        = 2000
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


  vcl {
    name    = "PyPI Files Custom Varnish Configuration"
    content = file("${path.module}/vcl/files.vcl")
    main    = true
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
    name      = "NeverReq"
    type      = "REQUEST"
    statement = "req.http.Fastly-Client-IP == \"127.0.0.1\" && req.http.Fastly-Client-IP != \"127.0.0.1\""
  }

  condition {
    name      = "5xx Error"
    type      = "RESPONSE"
    statement = "(resp.status >= 500 && resp.status < 600)"
  }

  condition {
    name      = "Never"
    type      = "RESPONSE"
    statement = "req.http.Fastly-Client-IP == \"127.0.0.1\" && req.http.Fastly-Client-IP != \"127.0.0.1\""
  }
}


resource "aws_route53_record" "files-staging" {
  zone_id = var.zone_id
  name    = var.staging_domain
  type    = local.apex_domain ? "A" : "CNAME"
  ttl     = 86400
  records = var.fastly_endpoints[join("_", [var.domain_map[var.staging_domain], local.apex_domain ? "A" : "CNAME"])]
}
