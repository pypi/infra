# Data source to get current AWS account info
data "aws_caller_identity" "current" {}

# IAM Groups
resource "aws_iam_group" "administrator" {
  name = "administrator"
  path = "/"
}

# Group Memberships
resource "aws_iam_group_membership" "administrator" {
  name  = "administrator-membership"
  group = aws_iam_group.administrator.name
  users = [
    "di",
    "dstufft",
    "coffee",
    "terraform-pypi",
    "ee",
  ]
}

# Group Policy Attachments
resource "aws_iam_group_policy_attachment" "administrator_admin_access" {
  group      = aws_iam_group.administrator.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
