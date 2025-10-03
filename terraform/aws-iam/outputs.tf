output "group_arns" {
  description = "ARNs of IAM groups"
  value = {
    administrator = aws_iam_group.administrator.arn
    billing       = aws_iam_group.billing.arn
    kops          = aws_iam_group.kops.arn
    readonly      = aws_iam_group.readonly.arn
  }
}

output "role_arns" {
  description = "ARNs of IAM roles"
  value = {
    datadog_integration = aws_iam_role.datadog_integration.arn
  }
}

output "policy_arns" {
  description = "ARNs of custom IAM policies"
  value = {
    billing_full_access  = aws_iam_policy.billing_full_access.arn
    datadog_integration = aws_iam_policy.datadog_integration.arn
  }
}