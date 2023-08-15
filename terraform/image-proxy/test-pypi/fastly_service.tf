resource "fastly_service_vcl" "Test PyPI Camo" {
  name = Test PyPI Camo

  domain {
    name    = "testpypi-image-proxy.global.ssl.fastly.net"
    comment = "Test PyPI Camo"
  }

  backend {
    address = "https://warehouse-test-camo.ingress.us-east-2.pypi.io"
    name    = "test-pypi-camo"
    port    = 443
  }

  force_destroy = true
}
