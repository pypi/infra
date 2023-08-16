variable "domain" { type = string }
variable "sitename" { type = string }
variable "backend_address" { type = string }


resource "fastly_service_vcl" "camo" {
  name        = var.sitename
  default_ttl = 10

  domain {
    name = var.domain
  }
  backend { 
    address = var.backend_address
    name    = var.sitename
    port    = 443
    ssl_cert_hostname = var.backend_address
    ssl_sni_hostname  = var.backend_address
  }
}
  
