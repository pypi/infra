# PyPI IAM Policies

# to clean up (?)
# pypi-bandersnatch-mirror - 1031 days ago
# pypi-db-backup-archive - 795 days ago
# PyPIReadOnly - 913 days ago

# DB Backup Archive Policy - not used in 795 days
# resource "aws_iam_policy" "pypi_db_backup_archive" {
#   name = "pypi-db-backup-archive"
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect   = "Allow"
#         Action   = "s3:ListAllMyBuckets"
#         Resource = "*"
#       },
#       {
#         Effect = "Allow"
#         Action = "s3:*"
#         Resource = [
#           "arn:aws:s3:::pypi-db-backup-archive",
#           "arn:aws:s3:::pypi-db-backup-archive/*"
#         ]
#       }
#     ]
#   })
# }

# opensearch
resource "aws_iam_policy" "pypi_elasticsearch" {
  name = "PyPIElasticSearch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VisualEditor0"
        Effect = "Allow"
        Action = [
          "es:DescribeReservedElasticsearchInstanceOfferings",
          "es:ESHttpGet",
          "es:ListTags",
          "es:DescribeElasticsearchDomainConfig",
          "es:GetUpgradeHistory",
          "es:DescribeReservedElasticsearchInstances",
          "es:ESHttpHead",
          "es:ListDomainNames",
          "es:DescribeElasticsearchDomain",
          "es:GetCompatibleElasticsearchVersions",
          "es:GetUpgradeStatus",
          "es:DescribeElasticsearchDomains",
          "es:ListElasticsearchInstanceTypes",
          "es:ListElasticsearchVersions",
          "es:DescribeElasticsearchInstanceTypeLimits"
        ]
        Resource = "*"
      },
      {
        Sid      = "VisualEditor1"
        Effect   = "Allow"
        Action   = "es:*"
        Resource = "arn:aws:es:us-east-2:220435833635:domain/warehouse-7/production*"
      },
      {
        Sid      = "VisualEditor2"
        Effect   = "Allow"
        Action   = "es:*"
        Resource = "arn:aws:es:us-east-2:220435833635:domain/warehouse-opensearch/production*"
      }
    ]
  })
}

# amazon ses
resource "aws_iam_policy" "pypi_email" {
  name        = "PyPIEmail"
  description = "Allows sending email as pypi.org"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "arn:aws:ses:us-west-2:220435833635:identity/pypi.org"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:ConfirmSubscription"
        ]
        Resource = "arn:aws:sns:us-west-2:220435833635:pypi-ses-delivery-events-topic"
      }
    ]
  })
}

# pypi files/docs ro - unused 913 days
# resource "aws_iam_policy" "pypi_readonly" {
#   name        = "PyPIReadOnly"
#   description = "PyPI Files/Docs Read-Only Access"
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "s3:GetObject",
#           "s3:ListBucket"
#         ]
#         Resource = [
#           "arn:aws:s3:::pypi-docs",
#           "arn:aws:s3:::pypi-docs/*",
#           "arn:aws:s3:::pypi-files",
#           "arn:aws:s3:::pypi-files/*"
#         ]
#       }
#     ]
#   })
# }

# s3 r/w
resource "aws_iam_policy" "pypi_s3_access" {
  name        = "PyPIS3Access"
  description = "R/W Access to the PyPI S3 Buckets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:ListAllMyBuckets"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = "s3:*"
        Resource = [
          "arn:aws:s3:::pypi-docs",
          "arn:aws:s3:::pypi-docs/*"
        ]
      },
      {
        Effect = "Allow"
        Action = "s3:*"
        Resource = [
          "arn:aws:s3:::pypi-files",
          "arn:aws:s3:::pypi-files/*",
          "arn:aws:s3:::pypi-files-archive",
          "arn:aws:s3:::pypi-files-archive/*"
        ]
      },
      {
        Effect = "Deny"
        Action = [
          "s3:DeleteBucket",
          "s3:DeleteBucketPolicy",
          "s3:DeleteBucketWebsite",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion"
        ]
        Resource = [
          "arn:aws:s3:::pypi-files",
          "arn:aws:s3:::pypi-files/*",
          "arn:aws:s3:::pypi-files-archive",
          "arn:aws:s3:::pypi-files-archive/*"
        ]
      }
    ]
  })
}

# amazon sqs - unused 231 days
resource "aws_iam_policy" "pypi_worker_sqs" {
  name        = "PyPIWorkerSQS"
  description = "R/W Access to PyPI's SQS Worker Queue"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ListQueues"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:PurgeQueue",
          "sqs:ReceiveMessage",
          "sqs:SendMessage",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = [
          "arn:aws:sqs:us-east-2:220435833635:pypi-worker",
          "arn:aws:sqs:us-east-2:220435833635:pypi-worker-default",
          "arn:aws:sqs:us-east-2:220435833635:pypi-worker-malware"
        ]
      }
    ]
  })
}
