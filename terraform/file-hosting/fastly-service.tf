resource "fastly_service_vcl" "files" {
  name = var.fastly_service_name
  # Set to false for spicy changes
  activate = false

  domain {
    name = var.domain
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

  snippet {
    name     = "B2"
    priority = 100
    type     = "recv"
    content  = <<-EOT
        set var.B2-Application-Key-ID = "${b2_application_key.primary_storage_read_key_backblaze.application_key_id}";
        set var.B2-Application-Key = "${b2_application_key.primary_storage_read_key_backblaze.application_key}";
        set var.B2-Bucket-Name = "${var.files_bucket}";
    EOT
  }

  snippet {
    name     = "AWS-Archive"
    priority = 100
    type     = "recv"
    content  = <<-EOT
        set var.AWS-Archive-Access-Key-ID = "${aws_iam_access_key.archive_storage_access_key.id}";
        set var.AWS-Archive-Secret-Access-Key = "${aws_iam_access_key.archive_storage_access_key.secret}";
        set var.S3-Archive-Bucket-Name = "${aws_s3_bucket.archive_storage_glacier_bucket.id}";
    EOT
  }

  snippet {
    name     = "Linehaul"
    priority = 100
    type     = "log"
    content  = "set var.Ship-Logs-To-Line-Haul = ${var.linehaul_enabled};"
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
    name    = "Main"
    content = file("${path.module}/vcl/files.vcl")
    main    = true
  }

  logging_gcs {
    name             = "Linehaul GCS"
    bucket_name      = var.linehaul_gcs["bucket"]
    path             = "downloads/%Y/%m/%d/%H/%M/"
    message_type     = "blank"
    format           = "download|%%{now}V|%%{client.geo.country_code}V|%%{req.url.path}V|%%{tls.client.protocol}V|%%{tls.client.cipher}V|%%{resp.http.x-amz-meta-project}V|%%{resp.http.x-amz-meta-version}V|%%{resp.http.x-amz-meta-package-type}V|%%{req.http.user-agent}V"
    timestamp_format = "%Y-%m-%dT%H:%M:%S.000"
    gzip_level       = 9
    period           = 120

    user       = var.linehaul_gcs["email"]
    secret_key = var.linehaul_gcs["private_key"]

    # We actually never want this to log by default, we'll manually log to it in
    # our VCL, but we need to set it here so that the system is configured to
    # have it as a logger.
    response_condition = "Never"
  }

  logging_s3 {
    name = "S3 Error Logs"

    format         = "%h \"%%{now}V\" %l \"%%{req.request}V %%{req.url}V\" %%{req.proto}V %>s %%{resp.http.Content-Length}V %%{resp.http.age}V \"%%{resp.http.x-cache}V\" \"%%{resp.http.x-cache-hits}V\" \"%%{req.http.content-type}V\" \"%%{req.http.accept-language}V\" \"%%{cstr_escape(req.http.user-agent)}V\" %D \"%%{fastly_info.state}V\""
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

resource "aws_route53_record" "files" {
  zone_id = var.zone_id
  name    = var.domain
  type    = local.apex_domain ? "A" : "CNAME"
  ttl     = 86400
  records = var.fastly_endpoints[join("_", [var.domain_map[var.domain], local.apex_domain ? "A" : "CNAME"])]
}


resource "aws_route53_record" "files-ipv6" {
  count = local.apex_domain ? 1 : 0

  zone_id = var.zone_id
  name    = var.domain
  type    = "AAAA"
  ttl     = 86400
  records = var.fastly_endpoints[join("_", [var.domain_map[var.domain], "AAAA"])]
}
