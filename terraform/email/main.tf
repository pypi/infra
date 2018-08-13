provider "aws" {}
provider "aws" {
    version = "~> 1.14"
    alias = "email"
}


variable "name" { type = "string" }
variable "display_name" { type = "string" }
variable "domain" { type = "string" }
variable "zone_id" { type = "string" }
variable "hook_url" { type = "string" }
variable "dmarc" { type = "string", default = "" }

data "aws_region" "mail_region" {
  provider = "aws.email"
}


resource "aws_ses_domain_identity" "primary" {
  provider = "aws.email"
  domain   = "${var.domain}"
}


resource "aws_ses_domain_dkim" "primary" {
  provider = "aws.email"
  domain = "${aws_ses_domain_identity.primary.domain}"
}

resource "aws_ses_domain_mail_from" "primary" {
  provider = "aws.email"
  domain = "${aws_ses_domain_identity.primary.domain}"
  mail_from_domain = "ses.${aws_ses_domain_identity.primary.domain}"
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

resource "aws_route53_record" "primary_amazonses_dmarc_record" {
  count = "${length(var.dmarc) >= 1 ? 1 : 0}"
  zone_id = "${var.zone_id}"
  name    = "_dmarc.${var.domain}"
  type    = "TXT"
  ttl     = "60"
  records = ["v=DMARC1; p=none; rua=${var.dmarc}; fo=1; adkim=r; aspf=r"]
}

resource "aws_route53_record" "primary_amazonses_mx_record" {
  zone_id = "${var.zone_id}"
  name    = "${aws_ses_domain_mail_from.primary.mail_from_domain}"
  type    = "MX"
  ttl     = "600"
  records = ["10 feedback-smtp.${data.aws_region.mail_region.name}.amazonses.com"]
}


resource "aws_sns_topic" "delivery-events" {
  provider = "aws.email"
  name = "${var.name}-ses-delivery-events-topic"
  display_name = "${var.display_name} SES Delivery Events"

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


resource "aws_ses_identity_notification_topic" "primary-deliveries" {
  provider          = "aws.email"
  topic_arn         = "${aws_sns_topic.delivery-events.arn}"
  notification_type = "Delivery"
  identity          = "${aws_ses_domain_identity.primary.domain}"
}


resource "aws_ses_identity_notification_topic" "primary-bounces" {
  provider          = "aws.email"
  topic_arn         = "${aws_sns_topic.delivery-events.arn}"
  notification_type = "Bounce"
  identity          = "${aws_ses_domain_identity.primary.domain}"
}


resource "aws_ses_identity_notification_topic" "primary-complaints" {
  provider          = "aws.email"
  topic_arn         = "${aws_sns_topic.delivery-events.arn}"
  notification_type = "Complaint"
  identity          = "${aws_ses_domain_identity.primary.domain}"
}


# TODO: We can't disable the policy of sending emails for a SES domain yet, because
#       this functionality doesn't exist in terraform yet. The issue to track this
#       is https://github.com/terraform-providers/terraform-provider-aws/issues/4182.
#       However, until that is addressed we will have to manually configure the
#       SES domain to disable email notifications for bounces and complaints.


output "delivery_topic" { value = "${aws_sns_topic.delivery-events.arn}" }
