variable "domain" {
  type = "string"
}


resource "aws_route53_zone" "primary" {
  name = "${var.domain}"
}


output "zone_id" {
  value = "${aws_route53_zone.primary.zone_id}"
}
