variable "zone_id" { type = string }
variable "domain" { type = string }
variable "fastly_service_name" { type = string }
variable "conveyor_address" { type = string }
variable "files_bucket" { type = string }
variable "mirror" { type = string }
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
