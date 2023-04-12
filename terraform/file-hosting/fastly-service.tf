resource "fastly_service_vcl" "files" {
  name = var.fastly_service_name
  # Set to false for spicy changes
  activate = false

  domain {
    name = var.domain
  }

  snippet {
    name     = "B2"
    priority = 100
    type     = "miss"
    content  = <<-EOT
        set var.B2AccessKey = "${b2_application_key.primary_storage_read_key_backblaze.application_key_id}";
        set var.B2SecretKey = "${b2_application_key.primary_storage_read_key_backblaze.application_key}";
        set var.B2Bucket    = "${var.files_bucket}";
        set var.B2Region = "us-east-005";
    EOT
  }

  snippet {
    name     = "AWS-Archive"
    priority = 100
    type     = "miss"
    content  = <<-EOT
        set var.AWSArchiveAccessKeyID = "${aws_iam_access_key.archive_storage_access_key.id}";
        set var.AWSArchiveSecretAccessKey = "${aws_iam_access_key.archive_storage_access_key.secret}";
        set var.AWSArchiveBucket = "${aws_s3_bucket.archive_storage_glacier_bucket.id}";
        set var.AWSArchiveRegion = "${aws_s3_bucket.archive_storage_glacier_bucket.region}";
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
    name = "B2"
    auto_loadbalance = false
    shield = "iad-va-us"

    request_condition = "Package File"

    address = "${var.files_bucket}.s3.us-east-005.backblazeb2.com"
    port = 443
    use_ssl = true
    ssl_cert_hostname = "${var.files_bucket}.s3.us-east-005.backblazeb2.com"
    ssl_sni_hostname = "${var.files_bucket}.s3.us-east-005.backblazeb2.com"

    connect_timeout       = 5000
    first_byte_timeout    = 60000
    between_bytes_timeout = 15000
    error_threshold       = 5
  }

  backend {
    name              = "S3_Archive"
    auto_loadbalance  = false
    shield            = "bfi-wa-us"

    request_condition = "NeverReq"

    address           = "${var.files_bucket}-archive.s3.amazonaws.com"
    port              = 443
    use_ssl           = true
    ssl_cert_hostname = "${var.files_bucket}-archive.s3.amazonaws.com"
    ssl_sni_hostname  = "${var.files_bucket}-archive.s3.amazonaws.com"

    connect_timeout       = 5000
    first_byte_timeout    = 60000
    between_bytes_timeout = 15000
    error_threshold       = 5
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

  logging_datadog {
    name               = "Log Storage Fallback success"
    token              = var.datadog_token
    response_condition = "Storage Fallback success"
    format             = "{ \"ddsource\": \"fastly\", \"service\": \"%%{req.service_id}V\", \"date\": \"%%{begin:%Y-%m-%dT%H:%M:%S%z}t\", \"url\": \"%%{json.escape(req.url)}V\", \"message\": \"Storage had to fetch from fallback!\", \"short_message\": \"storage_fallback\" }"
  }

  logging_datadog {
    name               = "Log Storage Fallback failure"
    token              = var.datadog_token
    response_condition = "Storage Fallback failure"
    format             = "{ \"ddsource\": \"fastly\", \"service\": \"%%{req.service_id}V\", \"date\": \"%%{begin:%Y-%m-%dT%H:%M:%S%z}t\", \"url\": \"%%{json.escape(req.url)}V\", \"message\": \"Storage failed to fetch from fallback!\", \"short_message\": \"storage_fallback_failure\" }"
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
    name      = "Storage Fallback success"
    type      = "RESPONSE"
    statement = "req.restarts > 0 && req.http.Fallback-Backend == \"1\" && req.url ~ \"^/packages/[a-f0-9]{2}/[a-f0-9]{2}/[a-f0-9]{60}/\" && (http_status_matches(resp.status, \"200\") || http_status_matches(resp.status, \"206\"))"
  }

  condition {
    name      = "Storage Fallback failure"
    type      = "RESPONSE"
    statement = "req.restarts > 0 && req.http.Fallback-Backend == \"1\" && req.url ~ \"^/packages/[a-f0-9]{2}/[a-f0-9]{2}/[a-f0-9]{60}/\" && !(http_status_matches(resp.status, \"200\") || http_status_matches(resp.status, \"206\"))"
  }

  condition {
    name      = "Never"
    type      = "RESPONSE"
    statement = "req.http.Fastly-Client-IP == \"127.0.0.1\" && req.http.Fastly-Client-IP != \"127.0.0.1\""
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
