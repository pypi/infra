variable "domain" { type = string }
variable "sitename" { type = string }
variable "conveyor_address" { type = string }


resource "fastly_service_vcl" "camo" {
  name = var.sitename

  domain {
    name = var.domain
  }
  backend { 
    address = var.conveyor_address
    name    = var.sitename
    port    = 443
    ssl_cert_hostname = var.conveyor_address
    ssl_sni_hostname  = var.conveyor_address
  }
}
  
