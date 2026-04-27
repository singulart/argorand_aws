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
          Service = [
            "bcm-data-exports.amazonaws.com",
            "billingreports.amazonaws.com"
          ]
        }
        Action = [
          "s3:GetBucketAcl",
          "s3:GetBucketPolicy"
        ]
        Resource = aws_s3_bucket.cost_usage_reports.arn
        Condition = {
          StringLike = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
            "aws:SourceArn" = [
              "arn:aws:bcm-data-exports:us-east-1:${data.aws_caller_identity.current.account_id}:export/*",
              "arn:aws:cur:us-east-1:${data.aws_caller_identity.current.account_id}:definition/*"
            ]
          }
        }
      },
      {
        Sid    = "AllowBillingServiceWriteReports"
        Effect = "Allow"
        Principal = {
          Service = [
            "bcm-data-exports.amazonaws.com",
            "billingreports.amazonaws.com"
          ]        
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cost_usage_reports.arn}/*"
        Condition = {
          StringLike = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
            "aws:SourceArn" = [
              "arn:aws:bcm-data-exports:us-east-1:${data.aws_caller_identity.current.account_id}:export/*",
              "arn:aws:cur:us-east-1:${data.aws_caller_identity.current.account_id}:definition/*"
            ]          
          }
        }
      }
    ]
  })
}

resource "aws_bcmdataexports_export" "cur_per_service" {
  export {
    name = "aws-billing-report-per-service"
    data_query {
      query_statement = <<EOF
      SELECT
        identity_line_item_id,
        identity_time_interval,
        line_item_product_code,
        line_item_unblended_cost,
        line_item_usage_type,
        line_item_usage_amount,
        pricing_unit,
        line_item_net_unblended_cost,
        resource_tags,
        cost_category
      FROM COST_AND_USAGE_REPORT
      EOF
      table_configurations = {
        COST_AND_USAGE_REPORT = {
          BILLING_VIEW_ARN                      = "arn:aws:billing::${data.aws_caller_identity.current.account_id}:billingview/primary",
          TIME_GRANULARITY                      = "DAILY",
          INCLUDE_RESOURCES                     = "FALSE",
          INCLUDE_MANUAL_DISCOUNT_COMPATIBILITY = "FALSE",
          INCLUDE_SPLIT_COST_ALLOCATION_DATA    = "FALSE",
        }
      }
    }
    destination_configurations {
      s3_destination {
        s3_bucket = aws_s3_bucket.cost_usage_reports.id
        s3_prefix = "cost-usage-reports/"
        s3_region = data.aws_region.current.region
        s3_output_configurations {
          overwrite   = "CREATE_NEW_REPORT"
          format      = "PARQUET"
          compression = "PARQUET"
          output_type = "CUSTOM"
        }
      }
    }

    refresh_cadence {
      frequency = "SYNCHRONOUS"
    }
  }
}
