# SES Configuration Set with SNS Event Destination for "argorand.io"

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      terraform     = "true"
      application   = "Email Outreach"
    }
  }
}

data "aws_caller_identity" "current" {}

# Retrieve an existing verified domain identity
data "aws_ses_domain_identity" "argorand" {
  domain = "argorand.io"
}

# This domain identity is specifically to handle clicks and opens tracking
# https://docs.aws.amazon.com/ses/latest/dg/configure-custom-open-click-domains.html#configure-custom-open-click-domain
# See Option 2: Configuring an HTTPS domain

resource "aws_ses_domain_identity" "analytics" {
  domain = "analytics.argorand.io"
}

resource "aws_route53_record" "analytics_amazonses_verification_record" {
  zone_id = aws_route53_zone.analytics.zone_id
  name    = "_amazonses.${aws_ses_domain_identity.analytics.domain}"
  type    = "TXT"
  ttl     = "600"
  records = [aws_ses_domain_identity.analytics.verification_token]
}

resource "aws_ses_domain_identity_verification" "analytics_verification" {
  domain = aws_ses_domain_identity.analytics.domain
  depends_on = [aws_route53_record.analytics_amazonses_verification_record]
}

resource "aws_acm_certificate" "cert" {
  domain_name       = aws_ses_domain_identity.analytics.domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Create DNS validation records
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.analytics.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.value]
}

# Complete validation
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_cloudfront_distribution" "ses_tracking" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "SES Link Tracking Distribution"

  aliases = [aws_ses_domain_identity.analytics.domain]

  origin {
    domain_name = "r.us-east-1.awstrack.me"
    origin_id   = "SESLinkTrackingOrigin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "SESLinkTrackingOrigin"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true

      headers = ["Host"] # 👈 this ensures the Host header is preserved

      cookies {
        forward = "none"
      }
    }

    compress = true
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.cert.arn
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  default_root_object = ""
  price_class         = "PriceClass_100" # Adjust as needed
}

resource "aws_route53_record" "cdn_alias" {
  zone_id = aws_route53_zone.analytics.zone_id
  name    = aws_ses_domain_identity.analytics.domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.ses_tracking.domain_name
    zone_id                = aws_cloudfront_distribution.ses_tracking.hosted_zone_id
    evaluate_target_health = false
  }
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
    custom_redirect_domain = "analytics.argorand.io"
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
