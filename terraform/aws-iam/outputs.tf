output "role_arns" {
  description = "ARNs of IAM roles"
  value = {
    datadog_integration = aws_iam_role.datadog_integration.arn
  }
}

output "policy_arns" {
  description = "ARNs of custom IAM policies"
  value = {
    datadog_integration = aws_iam_policy.datadog_integration.arn
  }
}