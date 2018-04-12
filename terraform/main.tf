module "dns" {
    source = "./dns"
    domain = "pypi.org"
}


module "email" {
  source = "./email"
  providers = {
    "aws" = "aws"
    "aws.email" = "aws.us-west-2"
  }

  zone_id  = "${module.dns.zone_id}"
  domain   = "pypi.org"
  hook_url = "https://pypi.org/_/ses-hook/"
}


output "ses_delivery_topic" { value = "${module.email.delivery_topic}" }
