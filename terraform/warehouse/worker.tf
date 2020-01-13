resource "aws_sqs_queue" "pypi_worker" {
  name                       = "${lower(var.name)}-worker"
  # We're going to set this to 5 minutes, which basically means that if a worker
  # hasn't completed the task within 5 minutes, then SQS will make it visible for
  # another work to accept it.
  visibility_timeout_seconds = 300
}

resource "aws_sqs_queue" "pypi_worker_default" {
  name                       = "${lower(var.name)}-worker-default"
  # We're going to set this to 5 minutes, which basically means that if a worker
  # hasn't completed the task within 5 minutes, then SQS will make it visible for
  # another work to accept it.
  visibility_timeout_seconds = 300
}

resource "aws_sqs_queue" "pypi_worker_malware" {
  name                       = "${lower(var.name)}-worker-malware"
  # We're going to set this to 5 minutes, which basically means that if a worker
  # hasn't completed the task within 5 minutes, then SQS will make it visible for
  # another work to accept it.
  visibility_timeout_seconds = 300
}

resource "aws_iam_policy" "pypi_worker" {
  name        = "${var.name}WorkerSQS"
  description = "R/W Access to PyPI's SQS Worker Queue"

  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:ListQueues"
      ],
     "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:PurgeQueue",
          "sqs:ReceiveMessage",
          "sqs:SendMessage"
      ],
      "Resource": [
          "${aws_sqs_queue.pypi_worker.arn}",
          "${aws_sqs_queue.pypi_worker_default.arn}",
          "${aws_sqs_queue.pypi_worker_malware.arn}"
      ]
    }
  ]
}
EOF
}
