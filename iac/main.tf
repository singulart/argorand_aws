# SES Configuration Set with SNS Event Destination for "argorand.io"

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      terraform = "true"
    }
  }
}

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

data "aws_caller_identity" "current" {}

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

