locals {
  region              = "us-east-1"
}

resource "aws_ses_template" "argorand_reusable_campaign_template" {
  name = "argorand-campaign-template"

  html = <<EOF
<!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8">
    <title>{{subject}}</title>
  </head>
  <body style="font-family: Arial, sans-serif; color: #222222; background-color: #ffffff; padding: 20px;">
    <p style="font-size: 16px;">Hello {{first_name}},</p>

    <p style="font-size: 16px;">
      {{body_content}}
    </p>

    <p style="margin: 30px 0;">
      <a href="{{cta_link}}" style="padding: 12px 20px; background-color: #0073e6; color: #ffffff; text-decoration: none; font-weight: bold; border-radius: 4px;">
        {{cta_text}}
      </a>
    </p>

    <!-- Signature block -->
    <div dir="ltr">
      <p style="color:rgb(136,136,136);margin:0;">
        <font size="4">
          <b><span style="font-family:'Franklin Gothic Medium',sans-serif;color:rgb(0,107,181)">Lex Buistov</span></b>
        </font>
      </p>
      <p style="margin:0;">
        <font color="#7f7f7f" face="Franklin Gothic Book, sans-serif" size="4">Chief Executive Officer</font>
      </p>
      <p><img src="https://argorand.io/wp-content/uploads/2024/12/argorand-seo.png" alt="Argorand Logo" style="max-width: 200px;"></p>
      <p style="color:#444444;font-size:16px;">
        <a href="https://www.argorand.io" style="color:#1155cc;">https://www.argorand.io</a><br>
        <strong>Change the way you AWS</strong><br>
        444 North Capitol St NW, Suite 612 #603<br>
        Washington, DC 20001<br>
        (301) 882-2033
      </p>
    </div>
  </body>
</html>
EOF

  subject = "{{subject}}"
  text    = "Hello {{first_name}},\n\n{{body_content}}\n\nVisit: {{cta_link}}"
}

## S3 bucket 

resource "aws_s3_bucket" "argorand_email_campaigns" {
  bucket = "argorand-email-campaigns"
}

resource "aws_s3_bucket_lifecycle_configuration" "argorand_email_campaigns_lifecycle" {
  bucket = aws_s3_bucket.argorand_email_campaigns.id

  rule {
    id     = "NoncurrentVersionExpirationRule"
    status = "Enabled"
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "abort-incomplete-multipart-upload"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 2
    }
  }

  rule {
    id     = "transition-and-expiration-rule"
    status = "Enabled"

    transition {
      days          = 30 # Transition objects to another storage class after 30 days
      storage_class = "STANDARD_IA" # Change to desired storage class (e.g., STANDARD_IA, GLACIER, etc.)
    }

    expiration {
      days = 365 # Expire (delete) objects after 365 days
    }
  }  
}

resource "aws_s3_bucket_versioning" "argorand_email_campaigns_versioning" {
  bucket = aws_s3_bucket.argorand_email_campaigns.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "argorand_email_campaigns_encryption" {
  bucket = aws_s3_bucket.argorand_email_campaigns.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


resource "random_string" "rnd" {
  length  = 12
  special = false
}


## Loader Lambda

resource "aws_lambda_function" "email_loader" {
  function_name = "email_loader"
  runtime       = "python3.13"
  handler       = "loader_lambda.lambda_function.lambda_handler"
  filename      = "loader_lambda.zip"
  role          = aws_iam_role.email_loader_lambda_execution_role.arn
  architectures = [ "arm64" ]
  timeout       = 120
  memory_size   = 512
  publish       = true
  source_code_hash = filebase64sha256("loader_lambda.zip")


  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      S3_BUCKET              = aws_s3_bucket.argorand_email_campaigns.bucket
    }
  }
}

resource "aws_cloudwatch_log_group" "email_loader_lambda_logs" {
  name              = "/aws/lambda/loader_lambda"
  retention_in_days = 14
}

resource "aws_iam_role" "email_loader_lambda_execution_role" {
  name = "email_loader_lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement : [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "email_loader_lambda_permissions" {
  name        = "email_loader_lambda_permissions"
  description = "Permissions for Lambda to access S3, and CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement : [    
      {
        Action = [
          "s3:GetObject"
        ],
        Effect   = "Allow",
        Resource = "${aws_s3_bucket.argorand_email_campaigns.arn}/*"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:${local.region}:*:log-group:/aws/lambda/loader_lambda:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "email_loader_policy_attachment" {
  role       = aws_iam_role.email_loader_lambda_execution_role.name
  policy_arn = aws_iam_policy.email_loader_lambda_permissions.arn
}

## Sender Lambda

resource "aws_lambda_function" "cold_email_sender" {
  function_name = "cold_email_sender"
  runtime       = "python3.13"
  handler       = "email_worker_lambda.lambda_function.lambda_handler"
  filename      = "email_worker_lambda.zip"
  role          = aws_iam_role.lambda_execution_role.arn
  architectures = [ "arm64" ]
  timeout       = 120
  memory_size   = 512
  publish       = true
  source_code_hash = filebase64sha256("email_worker_lambda.zip")

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      SES_CONFIG_SET         = aws_sesv2_configuration_set.main.configuration_set_name 
      SES_SENDER             = "hello@argorand.io"
      SES_SENDER_NAME        = "Lex from Argorand"
      SES_TEMPLATE           = aws_ses_template.argorand_reusable_campaign_template.name
      RANDOM_VAR             = random_string.rnd.result
    }
  }
}

resource "aws_cloudwatch_log_group" "cold_email_sender_logs" {
  name              = "/aws/lambda/cold_email_sender"
  retention_in_days = 14
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "cold_email_sender_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement : [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_permissions" {
  name        = "cold_email_sender_permissions"
  description = "Permissions for Lambda to access SES, and CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement : [    
      {
        Action   = "ses:SendBulkTemplatedEmail",
        Effect   = "Allow",
        Resource = [
          "arn:aws:ses:${local.region}:${data.aws_caller_identity.current.account_id}:configuration-set/argorand-ses-config-set*",
          "arn:aws:ses:${local.region}:${data.aws_caller_identity.current.account_id}:template/argorand-campaign*",
          "arn:aws:ses:${local.region}:${data.aws_caller_identity.current.account_id}:identity/hello@argorand.io",
          "arn:aws:ses:${local.region}:${data.aws_caller_identity.current.account_id}:identity/argorand.io"
        ]
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:${local.region}:*:log-group:/aws/lambda/cold_email_sender:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_permissions.arn
}


# Step Function Orchestrator

# Step Function Definition
resource "aws_sfn_state_machine" "email_campaign" {
  name     = "EmailCampaign"
  role_arn = aws_iam_role.stepfn_role.arn

  definition = jsonencode({
    Comment = "Parallel email sending campaign",
    StartAt = "LoadRecipients",
    States = {
      LoadRecipients = {
        Type = "Task",
        Resource = aws_lambda_function.email_loader.arn,
        Next = "SendEmails"
      },
      SendEmails = {
        Type = "Map",
        ItemsPath = "$",
        MaxConcurrency = 10,
        Iterator = {
          StartAt = "SendBatch",
          States = {
            SendBatch = {
              Type = "Task",
              Resource = aws_lambda_function.cold_email_sender.arn,
              End = true
            }
          }
        },
        End = true
      }
    }
  })
}

# Step Function IAM role
resource "aws_iam_role" "stepfn_role" {
  name = "stepfn-email-campaign-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Principal = { Service = "states.amazonaws.com" },
      Effect = "Allow"
    }]
  })
}

resource "aws_iam_role_policy" "stepfn_policy" {
  name = "stepfn-invoke-lambda"
  role = aws_iam_role.stepfn_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "lambda:InvokeFunction",
        Effect = "Allow",
        Resource = [
          aws_lambda_function.cold_email_sender.arn,
          aws_lambda_function.email_loader.arn
        ]
      }
    ]
  })
}