provider "aws" {}
provider "aws" { alias = "email" }


variable "domain" { type = "string" }
variable "zone_id" { type = "string" }
variable "hook_url" { type = "string" }


resource "aws_ses_domain_identity" "primary" {
  provider = "aws.email"
  domain   = "${var.domain}"
}


resource "aws_ses_domain_dkim" "primary" {
  provider = "aws.email"
  domain = "${aws_ses_domain_identity.primary.domain}"
}


resource "aws_route53_record" "primary_amazonses_verification_record" {
  zone_id = "${var.zone_id}"
  name    = "_amazonses.${var.domain}"
  type    = "TXT"
  ttl     = "1800"
  records = ["${aws_ses_domain_identity.primary.verification_token}"]
}


resource "aws_route53_record" "primary_amazonses_dkim_record" {
  count   = 3
  zone_id = "${var.zone_id}"
  name    = "${element(aws_ses_domain_dkim.primary.dkim_tokens, count.index)}._domainkey.${var.domain}"
  type    = "CNAME"
  ttl     = "1800"
  records = ["${element(aws_ses_domain_dkim.primary.dkim_tokens, count.index)}.dkim.amazonses.com"]
}


resource "aws_sns_topic" "delivery-events" {
  provider = "aws.email"
  name = "pypi-ses-delivery-events-topic"
  display_name = "PyPI SES Delivery Events"

  delivery_policy = <<EOF
{
  "http": {
    "defaultHealthyRetryPolicy": {
      "minDelayTarget": 5,
      "maxDelayTarget": 30,
      "numRetries": 100,
      "numMaxDelayRetries": 25,
      "numNoDelayRetries": 5,
      "numMinDelayRetries": 5,
      "backoffFunction": "exponential"
    },
    "disableSubscriptionOverrides": false
  }
}
EOF
}


resource "aws_sns_topic_subscription" "delivery-events" {
    provider  = "aws.email"
    topic_arn = "${aws_sns_topic.delivery-events.arn}"
    protocol  = "https"
    endpoint  = "${var.hook_url}"
    endpoint_auto_confirms = true
}


# TODO: We can't setup the default sending policy for a SES domain yet, because this
#       functionality doesn't exist in Terraform yet. THere is an open issue to add
#       this (https://github.com/terraform-providers/terraform-provider-aws/issues/931)
#       along with a PR that does the actuak work
#       (https://github.com/terraform-providers/terraform-provider-aws/pull/2640).
#       However, until those get added we're going to have to manually configure the
#       SES domain to send the requisete events to our SNS topic.


output "delivery_topic" { value = "${aws_sns_topic.delivery-events.arn}" }
