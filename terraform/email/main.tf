provider "aws" {}
provider "aws" { alias = "email" }


variable "domain" { type = "string" }
variable "zone_id" { type = "string" }


resource "aws_ses_domain_identity" "primary" {
  provider = "aws.email"
  domain   = "${var.domain}"
}


resource "aws_route53_record" "primary_amazonses_verification_record" {
  zone_id = "${var.zone_id}"
  name    = "_amazonses.${var.domain}"
  type    = "TXT"
  ttl     = "1800"
  records = ["${aws_ses_domain_identity.primary.verification_token}"]
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
