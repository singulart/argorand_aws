# SES Configuration Set with SNS Event Destination for "argorand.io"

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      terraform = "true"
    }
  }
}

data "aws_caller_identity" "current" {}

# Retrieve an existing verified domain identity
data "aws_ses_domain_identity" "argorand" {
  domain = "argorand.io"
}

# Create a configuration set
resource "aws_sesv2_configuration_set" "main" {
  configuration_set_name = "argorand-ses-config-set"

  delivery_options {
    tls_policy = "REQUIRE"
  }

  reputation_options {
    reputation_metrics_enabled = true
  }

  sending_options {
    sending_enabled = true
  }

  tracking_options {
    custom_redirect_domain = "mail.argorand.io"
  }

  suppression_options {
    suppressed_reasons = ["BOUNCE", "COMPLAINT"]
  }
}

# Create an SNS topic to receive SES event notifications
resource "aws_sns_topic" "ses_events" {
  name = "ses-argorand-events"
}

# (Optional) Allow SES to publish to the topic - useful if you want to subscribe other services like Lambda
resource "aws_sns_topic_policy" "allow_ses_publish" {
  arn = aws_sns_topic.ses_events.arn

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ses.amazonaws.com"
        },
        Action   = "SNS:Publish",
        Resource = aws_sns_topic.ses_events.arn,
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Attach an event destination to the configuration set
resource "aws_sesv2_configuration_set_event_destination" "sns_destination" {
  configuration_set_name = aws_sesv2_configuration_set.main.configuration_set_name
  event_destination_name = "argorand-sns-destination"

  event_destination {
    enabled              = true
    matching_event_types = ["SEND", "REJECT", "BOUNCE", "COMPLAINT", "DELIVERY", "OPEN", "CLICK"]

    sns_destination {
      topic_arn = aws_sns_topic.ses_events.arn
    }
  }
}

# Create SQS queue
resource "aws_sqs_queue" "ses_events_queue" {
  name = "ses-argorand-events-queue"
}

# Allow SNS topic to send messages to SQS
resource "aws_sqs_queue_policy" "ses_events_queue_policy" {
  queue_url = aws_sqs_queue.ses_events_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Allow-SNS-SendMessage"
        Effect    = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.ses_events_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.ses_events.arn
          }
        }
      }
    ]
  })
}

# Subscribe SQS queue to SNS topic
resource "aws_sns_topic_subscription" "ses_events_subscription" {
  topic_arn = aws_sns_topic.ses_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.ses_events_queue.arn
  raw_message_delivery = true
}
