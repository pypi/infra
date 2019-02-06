variable "bucket_name" { type = "string" }
variable "queue_name" { type = "string" }
variable "functions" { default = [] }

locals {
  timeout = 300
}


resource "aws_s3_bucket" "lambdas" {
  bucket = "${var.bucket_name}"
  versioning {
      enabled = true
  }
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
        "ArnEquals": { "aws:SourceArn": "${aws_s3_bucket.lambdas.arn}" }
      }
    }
  ]
}
POLICY
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = "${aws_s3_bucket.lambdas.id}"

  queue {
    queue_arn     = "${aws_sqs_queue.events.arn}"
    events        = ["s3:ObjectCreated:*"]
  }
}

resource "aws_iam_role" "lambda" {
  name = "LambdaDeployerRole"

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

resource "aws_lambda_function" "deployer" {
  function_name    = "lambda-deployer"
  role             = "${aws_iam_role.lambda.arn}"

  filename         = "../lambda-deployer/target/x86_64-unknown-linux-musl/release/lambda-deployer.zip"
  source_code_hash = "${base64sha256(file("../lambda-deployer/target/x86_64-unknown-linux-musl/release/lambda-deployer.zip"))}"
  runtime          = "provided"
  handler          = "Provided"

  timeout          = "${local.timeout}"
}


resource "aws_cloudwatch_log_group" "deployer" {
  name              = "/aws/lambda/${aws_lambda_function.deployer.function_name}"
  retention_in_days = 14
}


resource "aws_iam_policy" "lambda_logging" {
  name = "LambdaDeployerWriteLogs"
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
      "Resource": "${aws_cloudwatch_log_group.deployer.arn}",
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
  name = "LambdaDeployerSQSReadDelete"
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


resource "aws_lambda_event_source_mapping" "deployer" {
  event_source_arn = "${aws_sqs_queue.events.arn}"
  function_name    = "${aws_lambda_function.deployer.arn}"
}


resource "aws_iam_policy" "lambda_s3" {
  name = "LambdaDeployerS3Read"
  path = "/"
  description = "IAM policy for reading a S3 Bucket."

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion"
      ],
      "Resource": "${aws_s3_bucket.lambdas.arn}/*",
      "Effect": "Allow"
    }
  ]
}
EOF
}


resource "aws_iam_role_policy_attachment" "lambda_s3" {
  role = "${aws_iam_role.lambda.name}"
  policy_arn = "${aws_iam_policy.lambda_s3.arn}"
}


# Setup permissions for the functions we expect to handle.

data "aws_lambda_function" "deployed" {
  count = "${length(var.functions)}"
  function_name = "${element(var.functions, count.index)}"
}


resource "aws_iam_policy" "update_deployed" {
  count = "${length(var.functions)}"
  name = "LambdaDeployerUpdate@${data.aws_lambda_function.deployed.*.function_name[count.index]}"
  path = "/"
  description = "IAM policy for updating ${data.aws_lambda_function.deployed.*.function_name[count.index]}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": ["lambda:UpdateFunctionCode"],
      "Resource": "${replace(data.aws_lambda_function.deployed.*.arn[count.index], ":$LATEST", "")}",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "update_deployed" {
  count = "${length(var.functions)}"
  role = "${aws_iam_role.lambda.name}"
  policy_arn = "${aws_iam_policy.update_deployed.*.arn[count.index]}"
}
