module "dns" {
    source = "./dns"
    domain = "pypi.org"
}


module "email" {
  source = "./email"
  providers = {
    "aws" = "aws"
    "aws.email" = "aws.oregon"
  }

  domain = "pypi.org"
  zone_id = "${module.dns.zone_id}"
}
