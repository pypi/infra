variable "zone_id" { type = string }
variable "domain" { type = string }
variable "fastly_service_name" { type = string }
variable "conveyor_address" { type = string }

variable "fastly_endpoints" { type = map(any) }
variable "domain_map" { type = map(any) }
