variable "bucket_name" { type = "string" }
variable "queue_name" { type = "string" }
variable "bigquery_creds" { type = "string" }
variable "bigquery_table" { type = "string" }

locals {
  timeout = 300
}


resource "aws_s3_bucket" "bucket" {
  bucket = "${var.bucket_name}"
}


resource "aws_iam_policy" "log-writer" {
  name        = "LinehaulWriteLogs"
  path        = "/"
  description = "Policy to allow writing Linehaul Logs"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": [
        "${aws_s3_bucket.bucket.arn}/*"
      ]
    }
  ]
}
EOF
}


resource "aws_sqs_queue" "events" {
  name = "${var.queue_name}"
  visibility_timeout_seconds = "${local.timeout * 2}"

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "sqs:SendMessage",
      "Resource": "arn:aws:sqs:*:*:${var.queue_name}",
      "Condition": {
        "ArnEquals": { "aws:SourceArn": "${aws_s3_bucket.bucket.arn}" }
      }
    }
  ]
}
POLICY
}


resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = "${aws_s3_bucket.bucket.id}"

  queue {
    queue_arn     = "${aws_sqs_queue.events.arn}"
    events        = ["s3:ObjectCreated:*"]
  }
}


resource "aws_iam_role" "lambda" {
  name = "LinehaulLambdaRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}


resource "aws_lambda_function" "linehaul" {
  function_name    = "linehaul"
  role             = "${aws_iam_role.lambda.arn}"

  s3_bucket        = "pypi-lambdas"
  s3_key           = "linehaul"

  runtime          = "provided"
  handler          = "Provided"

  timeout          = "${local.timeout}"
  memory_size      = 512

  environment {
    variables = {
      BIGQUERY_CREDENTIALS = "${var.bigquery_creds}"
      SIMPLE_REQUESTS_TABLE = "${var.bigquery_table}"
    }
  }
}


resource "aws_cloudwatch_log_group" "linehaul" {
  name              = "/aws/lambda/${aws_lambda_function.linehaul.function_name}"
  retention_in_days = 14
}


resource "aws_iam_policy" "lambda_logging" {
  name = "LinehaulLambdaWriteLogs"
  path = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "${aws_cloudwatch_log_group.linehaul.arn}",
      "Effect": "Allow"
    }
  ]
}
EOF
}


resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role = "${aws_iam_role.lambda.name}"
  policy_arn = "${aws_iam_policy.lambda_logging.arn}"
}


resource "aws_iam_policy" "lambda_sqs" {
  name = "LinehaulLambdaSQSReadDelete"
  path = "/"
  description = "IAM policy for reading and deleting from a SQS Queue."

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "sqs:ChangeMessageVisibility",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "${aws_sqs_queue.events.arn}",
      "Effect": "Allow"
    }
  ]
}
EOF
}


resource "aws_iam_role_policy_attachment" "lambda_sqs" {
  role = "${aws_iam_role.lambda.name}"
  policy_arn = "${aws_iam_policy.lambda_sqs.arn}"
}


resource "aws_lambda_event_source_mapping" "linehaul" {
  event_source_arn = "${aws_sqs_queue.events.arn}"
  function_name    = "${aws_lambda_function.linehaul.arn}"
}


resource "aws_iam_policy" "linehaul_s3" {
  name = "LinehaulS3ReadDelete"
  path = "/"
  description = "IAM policy for reading and deleting from the linehaul S3 Bucket."

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:DeleteObject",
        "s3:GetObject"
      ],
      "Resource": "${aws_s3_bucket.bucket.arn}/*",
      "Effect": "Allow"
    },
    {
      "Action": ["s3:ListBucket"],
      "Resource": "${aws_s3_bucket.bucket.arn}",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_linehaul_s3" {
  role = "${aws_iam_role.lambda.name}"
  policy_arn = "${aws_iam_policy.linehaul_s3.arn}"
}
