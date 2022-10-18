terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
  required_version = ">= 0.13"
}

provider "aws" {
  alias  = "aws-us-east-1"
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

variable "tags" { type = map(any) }
variable "primary_domain" { type = string }
variable "user_content_domain" { type = string }
variable "caa_report_uri" { type = string }
variable "caa_issuers" { type = list(any) }
variable "apex_txt" { type = list(any) }


resource "aws_route53_delegation_set" "ns" {}

resource "aws_kms_key" "dnssec" {
  provider                           = aws.aws-us-east-1
  customer_master_key_spec           = "ECC_NIST_P256"
  key_usage                          = "SIGN_VERIFY"
  bypass_policy_lockout_safety_check = false
  policy = jsonencode({
    Id = "dnssec-policy"
    Statement = [
      {
        Action = "kms:*"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Resource = "*"
        Sid      = "Enable IAM User Permissions"
      },
      {
        Action = [
          "kms:DescribeKey",
          "kms:GetPublicKey",
          "kms:Sign",
        ],
        Effect = "Allow"
        Principal = {
          Service = "dnssec-route53.amazonaws.com"
        }
        Sid      = "Allow Route 53 DNSSEC Service",
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:route53:::hostedzone/*"
          }
        }
      },
      {
        Action = "kms:CreateGrant",
        Effect = "Allow"
        Principal = {
          Service = "dnssec-route53.amazonaws.com"
        }
        Sid      = "Allow Route 53 DNSSEC to CreateGrant",
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      },
    ]
    Version = "2012-10-17"
  })
}

resource "aws_kms_alias" "dnssec" {
  provider      = aws.aws-us-east-1
  name          = "alias/${replace(var.primary_domain, ".", "-")}-dnssec-0"
  target_key_id = aws_kms_key.dnssec.key_id
}


resource "aws_route53_zone" "primary" {
  name              = var.primary_domain
  delegation_set_id = aws_route53_delegation_set.ns.id
  tags              = var.tags
}

resource "aws_route53_key_signing_key" "primary" {
  hosted_zone_id             = aws_route53_zone.primary.zone_id
  key_management_service_arn = aws_kms_key.dnssec.arn
  name                       = "${element(split(".", var.primary_domain), 0)}0"
}

resource "aws_route53_hosted_zone_dnssec" "primary" {
  depends_on = [
    aws_route53_key_signing_key.primary
  ]
  hosted_zone_id = aws_route53_key_signing_key.primary.hosted_zone_id
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


output "nameservers" { value = aws_route53_delegation_set.ns.name_servers }
output "primary_zone_id" { value = aws_route53_zone.primary.zone_id }
output "user_content_zone_id" { value = aws_route53_zone.user_content.zone_id }
