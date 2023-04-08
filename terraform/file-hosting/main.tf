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

variable "fastly_endpoints" { type = map(any) }
variable "domain_map" { type = map(any) }

locals {
  apex_domain = length(split(".", var.domain)) > 2 ? false : true
}

resource "b2_bucket" "primary_storage_bucket_backblaze" {
  bucket_name = "${var.files_bucket}"
  bucket_info = {}
  bucket_type = "allPrivate"
  default_server_side_encryption {
    mode = "none"
  }
  file_lock_configuration {
    is_file_lock_enabled = true
  }
}
