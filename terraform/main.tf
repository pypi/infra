module "dns" {
  source = "./dns"

  primary_domain = "pypi.org"
  user_content_domain = "pythonhosted.org"
}


module "email" {
  source = "./email"
  providers = {
    "aws" = "aws"
    "aws.email" = "aws.us-west-2"
  }

  zone_id  = "${module.dns.primary_zone_id}"
  domain   = "pypi.org"
  hook_url = "https://pypi.org/_/ses-hook/"
}


output "nameservers" { value = ["${module.dns.nameservers}"] }
output "ses_delivery_topic" { value = "${module.email.delivery_topic}" }
