variable "zone_id" { type = string }
variable "domain" { type = string }
variable "fastly_service_name" { type = string }
variable "conveyor_address" { type = string }
variable "files_bucket" { type = string }
variable "linehaul_enabled" { type = bool }
variable "linehaul_gcs" { type = map(any) }
variable "s3_logging_keys" { type = map(any) }
variable "aws_access_key_id" { type = string }
variable "aws_secret_access_key" { type = string }
variable "gcs_access_key_id" { type = string }
variable "gcs_secret_access_key" { type = string }
variable "datadog_token" { type = string }
variable "x_pypi_admin_token" { type = string }
variable "fastly_toppops_enabled" { type = bool }

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

################################################################################
# Archive Object Inventory
################################################################################
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "archive_inventory" {
  provider = aws.us-west-2
  bucket = "${var.files_bucket}-archive-inventory"
}

resource "aws_s3_bucket_lifecycle_configuration" "archive_inventory_lifecycle_config" {
  provider = aws.us-west-2
  bucket   = aws_s3_bucket.archive_inventory.id

  rule {
    id = "abandon-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_public_access_block" "inventory_access_block" {
  bucket = aws_s3_bucket.archive_inventory.id

  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "inventory_versioning" {
  bucket = aws_s3_bucket.archive_inventory.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "inventory_policy" {
  bucket = aws_s3_bucket.archive_inventory.id
  policy = data.aws_iam_policy_document.inventory_bucket_policy.json
}


resource "aws_s3_bucket_inventory" "archive_object_inventory" {
  bucket = aws_s3_bucket.archive_storage_glacier_bucket
  name = "EntireBucketDaily"

  included_object_versions = "All"

  schedule {
    frequency = "Daily"
  }

  destination {
    bucket {
      format = "CSV"
      bucket_arn = aws_s3_bucket.archive_inventory.arn
    }
  }
}

data "aws_iam_policy_document" "inventory_bucket_policy" {
  statement {
    sid = "AllowS3InventoryWrite"
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = ["${aws_s3_bucket.archive_inventory.arn}/*"]

     condition {
       test = "ArnLike"
       variable = "aws:SourceArn"
       values = [aws_s3_bucket.archive_inventory.arn]
     }

     condition {
       test = "StringEquals"
       variable = "aws:SourceAccount"
       values = [data.aws_caller_identity.current.account_id]
     }

     condition {
       test = "StringEquals"
       variable = "s3:x-amz-acl"
       values = ["bucket-owner-full-control"]
     }
  }
}
