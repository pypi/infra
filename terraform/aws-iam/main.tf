# Data source to get current AWS account info
data "aws_caller_identity" "current" {}

# ===========================
# IAM Groups
# ===========================

resource "aws_iam_group" "administrator" {
  name = "administrator"
  path = "/"
}

resource "aws_iam_group" "billing" {
  name = "billing"
  path = "/"
}

resource "aws_iam_group" "kops" {
  name = "kops"
  path = "/"
}

resource "aws_iam_group" "readonly" {
  name = "readonly"
  path = "/"
}

# ===========================
# Group Memberships
# ===========================

resource "aws_iam_group_membership" "administrator" {
  name  = "administrator-membership"
  group = aws_iam_group.administrator.name
  users = [
    "di",
    "dstufft",
    "coffee",
    "terraform-pypi"
    "ee",
  ]
}

resource "aws_iam_group_membership" "kops" {
  name  = "kops-membership"
  group = aws_iam_group.kops.name
  users = [
    "kops"
  ]
}

# ===========================
# IAM Policies
# ===========================

resource "aws_iam_policy" "billing_full_access" {
  name        = "BillingFullAccess"
  description = "Provide Full Access to all billing related interfaces"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Stmt1430745153000"
        Effect = "Allow"
        Action = [
          "aws-portal:*"
        ]
        Resource = [
          "*"
        ]
      }
    ]
  })
}

# ===========================
# Group Policy Attachments
# ===========================

resource "aws_iam_group_policy_attachment" "administrator_admin_access" {
  group      = aws_iam_group.administrator.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_group_policy_attachment" "billing_full_access" {
  group      = aws_iam_group.billing.name
  policy_arn = aws_iam_policy.billing_full_access.arn
}

resource "aws_iam_group_policy_attachment" "readonly_view_only" {
  group      = aws_iam_group.readonly.name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

resource "aws_iam_group_policy_attachment" "kops_route53" {
  group      = aws_iam_group.kops.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRoute53FullAccess"
}

resource "aws_iam_group_policy_attachment" "kops_ec2" {
  group      = aws_iam_group.kops.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_group_policy_attachment" "kops_iam" {
  group      = aws_iam_group.kops.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}

resource "aws_iam_group_policy_attachment" "kops_vpc" {
  group      = aws_iam_group.kops.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
}

resource "aws_iam_group_policy_attachment" "kops_sqs" {
  group      = aws_iam_group.kops.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess"
}

resource "aws_iam_group_policy_attachment" "kops_s3" {
  group      = aws_iam_group.kops.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_group_policy_attachment" "kops_eventbridge" {
  group      = aws_iam_group.kops.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
}
