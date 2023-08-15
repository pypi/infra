resource "fastly_service_vcl" "test-pypi-camo" {
  name = var.fastly_service_name

  domain {
    name    = var.domain
    comment = "test-pypi-camo"
  }

  backend {
    address = "https://warehouse-test-camo.ingress.us-east-2.pypi.io"
    name    = "test-pypi-camo"
    port    = 443
  }

  force_destroy = true
}
