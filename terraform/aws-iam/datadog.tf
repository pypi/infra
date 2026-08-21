# Datadog AWS Integration Resources

resource "aws_iam_policy" "datadog_integration" {
  name = "AWSDataDogIntegration"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:Describe*",
          "budgets:ViewBudget",
          "cloudfront:GetDistributionConfig",
          "cloudfront:ListDistributions",
          "cloudtrail:DescribeTrails",
          "cloudtrail:GetTrailStatus",
          "cloudwatch:Describe*",
          "cloudwatch:Get*",
          "cloudwatch:List*",
          "codedeploy:List*",
          "codedeploy:BatchGet*",
          "directconnect:Describe*",
          "dynamodb:List*",
          "dynamodb:Describe*",
          "ec2:Describe*",
          "ec2:Get*",
          "ecs:Describe*",
          "ecs:List*",
          "elasticache:Describe*",
          "elasticache:List*",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeTags",
          "elasticloadbalancing:Describe*",
          "elasticmapreduce:List*",
          "elasticmapreduce:Describe*",
          "es:ListTags",
          "es:ListDomainNames",
          "es:DescribeElasticsearchDomains",
          "health:DescribeEvents",
          "health:DescribeEventDetails",
          "health:DescribeAffectedEntities",
          "kinesis:List*",
          "kinesis:Describe*",
          "lambda:AddPermission",
          "lambda:GetPolicy",
          "lambda:List*",
          "lambda:RemovePermission",
          "logs:Get*",
          "logs:Describe*",
          "logs:FilterLogEvents",
          "logs:TestMetricFilter",
          "rds:Describe*",
          "rds:List*",
          "redshift:DescribeClusters",
          "redshift:DescribeLoggingStatus",
          "route53:List*",
          "s3:GetBucketTagging",
          "s3:ListAllMyBuckets",
          "s3:GetBucketLogging",
          "s3:GetBucketLocation",
          "s3:GetBucketNotification",
          "s3:ListAllMyBuckets",
          "s3:PutBucketNotification",
          "ses:Get*",
          "sns:List*",
          "sns:Publish",
          "sqs:ListQueues",
          "support:*",
          "tag:getResources",
          "tag:getTagKeys",
          "tag:getTagValues",
          "apigateway:GET",
          "ec2:SearchTransitGatewayRoutes",
          "elasticfilesystem:DescribeAccessPoints",
          "fsx:DescribeFileSystems",
          "states:ListStateMachines",
          "apigateway:GET"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "datadog_integration" {
  name = "AWSDataDogIntegration"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::464622532012:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "63ce1985605d40499b0a2a0091d76b0e"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "datadog_integration" {
  role       = aws_iam_role.datadog_integration.name
  policy_arn = aws_iam_policy.datadog_integration.arn
}
