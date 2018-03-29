provider "aws" {}
provider "aws" { alias = "email" }


variable "domain" { type = "string" }
variable "zone_id" { type = "string" }


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
}


resource "aws_sqs_queue" "delivery-events" {
  name                       = "pypi-ses-delivery-events"
  visibility_timeout_seconds = 300
}


resource "aws_sns_topic_subscription" "sns-topic" {
  provider  = "aws.email"
  topic_arn = "${aws_sns_topic.delivery-events.arn}"
  protocol  = "sqs"
  endpoint  = "${aws_sqs_queue.delivery-events.arn}"
}


# TODO: We can't setup the default sending policy for a SES domain yet, because this
#       functionality doesn't exist in Terraform yet. THere is an open issue to add
#       this (https://github.com/terraform-providers/terraform-provider-aws/issues/931)
#       along with a PR that does the actuak work
#       (https://github.com/terraform-providers/terraform-provider-aws/pull/2640).
#       However, until those get added we're going to have to manually configure the
#       SES domain to send the requisete events to our SNS topic.
