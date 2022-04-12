terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
  required_version = ">= 0.13"
}

variable "tags" { type = map(any) }
variable "primary_domain" { type = string }
variable "user_content_domain" { type = string }
variable "caa_report_uri" { type = string }
variable "caa_issuers" { type = list(any) }
variable "apex_txt" { type = list(any) }


resource "aws_route53_delegation_set" "ns" {}


resource "aws_route53_zone" "primary" {
  name              = var.primary_domain
  delegation_set_id = aws_route53_delegation_set.ns.id
  tags              = var.tags
}

resource "aws_route53_record" "caa" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = var.primary_domain
  type    = "CAA"
  ttl     = 3600
  records = concat(formatlist("0 issue \"%s\"", var.caa_issuers), ["0 iodef \"${var.caa_report_uri}\""])
}

resource "aws_route53_record" "apex_txt" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = var.primary_domain
  type    = "TXT"
  ttl     = 3600
  records = var.apex_txt
}


resource "aws_route53_zone" "user_content" {
  name              = var.user_content_domain
  delegation_set_id = aws_route53_delegation_set.ns.id
  tags              = var.tags
}

resource "aws_route53_record" "user_content_caa" {
  zone_id = aws_route53_zone.user_content.zone_id
  name    = var.user_content_domain
  type    = "CAA"
  ttl     = 3600
  records = concat(formatlist("0 issue \"%s\"", var.caa_issuers), ["0 iodef \"${var.caa_report_uri}\""])
}


output "nameservers" { value = ["${aws_route53_delegation_set.ns.name_servers}"] }
output "primary_zone_id" { value = aws_route53_zone.primary.zone_id }
output "user_content_zone_id" { value = aws_route53_zone.user_content.zone_id }
