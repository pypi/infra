
variable "domain" { type = "string" }
variable "zone_id" { type = "string" }

variable "dkim_host_name" { type = "string" }
variable "dkim_txt_record" { type = "string" }


resource "aws_route53_record" "gmail_mx" {
  zone_id = "${var.zone_id}"
  name    = "${var.domain}"
  type    = "MX"
  ttl     = "3600"
  records = [
    "1 ASPMX.L.GOOGLE.COM.",
    "5 ALT1.ASPMX.L.GOOGLE.COM.",
    "5 ALT2.ASPMX.L.GOOGLE.COM.",
    "10 ASPMX2.GOOGLEMAIL.COM.",
    "10 ASPMX3.GOOGLEMAIL.COM."
  ]
}


resource "aws_route53_record" "primary_amazonses_dkim_record" {
  zone_id = "${var.zone_id}"
  name    = "${var.dkim_host_name}.${var.domain}"
  type    = "TXT"
  ttl     = "3600"
  records = ["${var.dkim_txt_record}"]
}
