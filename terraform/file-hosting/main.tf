variable "zone_id" { type = string }
variable "domain" { type = string }
variable "fastly_service_name" { type = string }
variable "conveyor_address" { type = string }
variable "files_bucket" { type = string }
variable "mirror" { type = string }
variable "linehaul_enabled" { type = bool }
variable "linehaul_gcs" { type = map(any) }
variable "s3_logging_keys" { type = map(any) }
variable "aws_access_key_id" { type = string }
variable "aws_secret_access_key" { type = string }
variable "gcs_access_key_id" { type = string }
variable "gcs_secret_access_key" { type = string }
variable "datadog_token" { type = string }

variable "fastly_endpoints" { type = map(any) }
variable "domain_map" { type = map(any) }

provider "aws" {
  alias  = "us-west-2"
  region = "us-west-2"
}

locals {
  apex_domain = length(split(".", var.domain)) > 2 ? false : true
}

################################################################################
# Our "primary" hot bucket in Backblaze
################################################################################

resource "b2_bucket" "primary_storage_bucket_backblaze" {
  bucket_name = var.files_bucket
  bucket_info = {}
  bucket_type = "allPrivate"
  default_server_side_encryption {
    mode = "none"
  }
  file_lock_configuration {
    is_file_lock_enabled = true
  }
}

resource "b2_application_key" "primary_storage_read_key_backblaze" {
  key_name     = "files-read-key-${var.files_bucket}"
  bucket_id    = b2_bucket.primary_storage_bucket_backblaze.id
  capabilities = ["readFiles"]
}

################################################################################
# Our "archival" failover bucket in AWS S3
################################################################################

resource "aws_s3_bucket" "archive_storage_glacier_bucket" {
  provider            = aws.us-west-2
  bucket              = "${var.files_bucket}-archive"
  object_lock_enabled = true
}

resource "aws_s3_bucket_acl" "archive_storage_glacier_bucket-acl" {
  provider = aws.us-west-2
  bucket   = aws_s3_bucket.archive_storage_glacier_bucket.id
  acl      = "private"
}

resource "aws_s3_bucket_lifecycle_configuration" "archive_storage_glacier_bucket-config" {
  provider = aws.us-west-2
  bucket   = aws_s3_bucket.archive_storage_glacier_bucket.id

  rule {
    id = "to-cold-storage"
    transition {
      days          = 1
      storage_class = "GLACIER_IR"
    }
    status = "Enabled"
  }
}

resource "aws_iam_user" "archive_storage_access_user" {
  name = "files-read-user-${var.files_bucket}-archive"
  path = "/system/"
}

data "aws_iam_policy_document" "archive_storage_access_policy_document" {
  statement {
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      "${aws_s3_bucket.archive_storage_glacier_bucket.arn}",
      "${aws_s3_bucket.archive_storage_glacier_bucket.arn}/*"
    ]
  }
}

resource "aws_iam_user_policy" "archive_storage_access_policy" {
  name   = "read-access-${aws_s3_bucket.archive_storage_glacier_bucket.id}"
  user   = aws_iam_user.archive_storage_access_user.name
  policy = data.aws_iam_policy_document.archive_storage_access_policy_document.json
}

resource "aws_iam_access_key" "archive_storage_access_key" {
  user = aws_iam_user.archive_storage_access_user.name
}
