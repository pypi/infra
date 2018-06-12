variable "tags" { type = "map" }
variable "primary_domain" { type = "string" }
variable "user_content_domain" { type = "string" }
variable "google_verification" { type = "list" }


resource "aws_route53_delegation_set" "ns" {}


resource "aws_route53_zone" "primary" {
  name              = "${var.primary_domain}"
  delegation_set_id = "${aws_route53_delegation_set.ns.id}"
  tags              = "${var.tags}"
}


resource "aws_route53_record" "google-verify" {
  zone_id = "${aws_route53_zone.primary.zone_id}"
  name    = "${var.primary_domain}"
  type    = "TXT"
  ttl     = 60
  records = "${var.google_verification}"
}


resource "aws_route53_zone" "user_content" {
  name              = "${var.user_content_domain}"
  delegation_set_id = "${aws_route53_delegation_set.ns.id}"
  tags              = "${var.tags}"
}


output "nameservers" { value = ["${aws_route53_delegation_set.ns.name_servers}"] }
output "primary_zone_id" { value = "${aws_route53_zone.primary.zone_id}" }
output "user_content_zone_id" { value = "${aws_route53_zone.user_content.zone_id}" }
