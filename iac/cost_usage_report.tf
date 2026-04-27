provider "aws" {
  alias  = "global_cost"
  region = "us-east-1"

  default_tags {
    tags = {
      terraform = "true"
      scope     = "global_cost"
    }
  }
}

resource "aws_s3_bucket" "cost_usage_reports" {
  provider = aws.global_cost
  bucket = "argorand-curs"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cost_usage_reports" {
  provider = aws.global_cost
  bucket = aws_s3_bucket.cost_usage_reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cost_usage_reports" {
  provider = aws.global_cost
  bucket = aws_s3_bucket.cost_usage_reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cost_usage_reports" {
  provider = aws.global_cost
  bucket = aws_s3_bucket.cost_usage_reports.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBillingServiceReadBucketMetadata"
        Effect = "Allow"
        Principal = {
          Service = "billingreports.amazonaws.com"
        }
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketPolicy"
        ]
        Resource = aws_s3_bucket.cost_usage_reports.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
            "aws:SourceArn" = "arn:aws:cur:us-east-1:${data.aws_caller_identity.current.account_id}:definition/*"
          }
        }
      },
      {
        Sid    = "AllowBillingServiceWriteReports"
        Effect = "Allow"
        Principal = {
          Service = "billingreports.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cost_usage_reports.arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
            "aws:SourceArn" = "arn:aws:cur:us-east-1:${data.aws_caller_identity.current.account_id}:definition/*"
          }
        }
      }
    ]
  })
}
