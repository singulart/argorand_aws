# TODO ENABLE commented-out resources WHEN NEEDED TO PRODUCE REPORTS for APN FTR


# #####################################
# # SNS Topic for CIS Alerts
# #####################################
# resource "aws_sns_topic" "cis_alerts" {
#   name = "cis-alerts"
# }

# resource "aws_sns_topic_subscription" "cis_alerts_email" {
#   topic_arn = aws_sns_topic.cis_alerts.arn
#   protocol  = "email"
#   endpoint  = "site@argorand.io"
# }

# #####################################
# # CloudTrail Trail
# #####################################
# resource "aws_cloudwatch_log_group" "trail" {
#   name              = "/aws/cloudtrail/cis"
#   retention_in_days = 90
# }

# resource "aws_iam_role" "cloudtrail_role" {
#   name = "cis-cloudtrail-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Action = "sts:AssumeRole"
#       Effect = "Allow"
#       Principal = {
#         Service = "cloudtrail.amazonaws.com"
#       }
#     }]
#   })
# }

# resource "aws_iam_role_policy" "cloudtrail_policy" {
#   name = "cis-cloudtrail-policy"
#   role = aws_iam_role.cloudtrail_role.id

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "logs:CreateLogStream",
#           "logs:PutLogEvents"
#         ]
#         Resource = "${aws_cloudwatch_log_group.trail.arn}:*"
#       }
#     ]
#   })
# }

resource "aws_s3_bucket" "cloudtrail" {
  bucket = "cis-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_kms_key_policy" "cloudtrail" {
  key_id = aws_kms_key.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "key-default-1"
    Statement = [
      {
        Sid       = "AllowRootAccount"
        Effect    = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid       = "AllowCloudTrail"
        Effect    = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
      }
    ]
  })
}

data "aws_region" "current" {}

resource "aws_kms_key" "cloudtrail" {
  description             = "KMS CMK for CloudTrail logs"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "cloudtrail" {
  name          = "alias/cis-cloudtrail-logs"
  target_key_id = aws_kms_key.cloudtrail.key_id
}

# resource "aws_cloudtrail" "cis" {
#   name                          = "cis-trail"
#   s3_bucket_name                = aws_s3_bucket.cloudtrail.id
#   include_global_service_events = true
#   is_multi_region_trail         = true
#   enable_logging                = true
#   cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
#   cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_role.arn
#   kms_key_id                    = aws_kms_alias.cloudtrail.arn
#   enable_log_file_validation    = true
# }


# #####################################
# # Metric Filter for Root User Usage
# #####################################
# resource "aws_cloudwatch_log_metric_filter" "root_user_usage" {
#   name           = "RootUserUsage"
#   log_group_name = aws_cloudwatch_log_group.trail.name

#   pattern = "{$.userIdentity.type=\"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType !=\"AwsServiceEvent\"}"

#   metric_transformation {
#     name      = "RootUserEventCount"
#     namespace = "CISMetrics"
#     value     = "1"
#   }
# }

# #####################################
# # Alarm for Root User Usage
# #####################################
# resource "aws_cloudwatch_metric_alarm" "root_user_usage_alarm" {
#   alarm_name          = "RootUserUsageAlarm"
#   alarm_description   = "CIS Benchmark: Detect usage of the root user"
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   evaluation_periods  = 1
#   metric_name         = aws_cloudwatch_log_metric_filter.root_user_usage.metric_transformation[0].name
#   namespace           = "CISMetrics"
#   period              = 300
#   statistic           = "Sum"
#   threshold           = 1

#   alarm_actions = [aws_sns_topic.cis_alerts.arn]
#   ok_actions    = [aws_sns_topic.cis_alerts.arn]
# }

# #####################################
# # Metric Filter for Security Group Changes
# #####################################
# resource "aws_cloudwatch_log_metric_filter" "security_group_changes" {
#   name           = "SecurityGroupChanges"
#   log_group_name = aws_cloudwatch_log_group.trail.name

#   # Matches Create/Delete/Authorize/Revoke security group events
#   pattern = "{ ($.eventName = AuthorizeSecurityGroupIngress) || ($.eventName = AuthorizeSecurityGroupEgress) || ($.eventName = RevokeSecurityGroupIngress) || ($.eventName = RevokeSecurityGroupEgress) || ($.eventName = CreateSecurityGroup) || ($.eventName = DeleteSecurityGroup) }"

#   metric_transformation {
#     name      = "SecurityGroupChangeCount"
#     namespace = "CISMetrics"
#     value     = "1"
#   }
# }

# #####################################
# # Alarm for Security Group Changes
# #####################################
# resource "aws_cloudwatch_metric_alarm" "security_group_changes_alarm" {
#   alarm_name          = "SecurityGroupChangesAlarm"
#   alarm_description   = "CIS Benchmark: Detect security group changes"
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   evaluation_periods  = 1
#   metric_name         = aws_cloudwatch_log_metric_filter.security_group_changes.metric_transformation[0].name
#   namespace           = "CISMetrics"
#   period              = 300
#   statistic           = "Sum"
#   threshold           = 1

#   alarm_actions = [aws_sns_topic.cis_alerts.arn]
#   ok_actions    = [aws_sns_topic.cis_alerts.arn]
# }

# #####################################
# # Metric Filter for NACL Changes
# #####################################
# resource "aws_cloudwatch_log_metric_filter" "nacl_changes" {
#   name           = "NACLChanges"
#   log_group_name = aws_cloudwatch_log_group.trail.name

#   # Matches Create, Delete, and entry changes for NACLs
#   pattern = "{ ($.eventName = CreateNetworkAcl) || ($.eventName = CreateNetworkAclEntry) || ($.eventName = DeleteNetworkAcl) || ($.eventName = DeleteNetworkAclEntry) || ($.eventName = ReplaceNetworkAclEntry) || ($.eventName = ReplaceNetworkAclAssociation) }"

#   metric_transformation {
#     name      = "NACLChangeCount"
#     namespace = "CISMetrics"
#     value     = "1"
#   }
# }

# #####################################
# # Alarm for NACL Changes
# #####################################
# resource "aws_cloudwatch_metric_alarm" "nacl_changes_alarm" {
#   alarm_name          = "NACLChangesAlarm"
#   alarm_description   = "CIS Benchmark: Detect changes to Network ACLs"
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   evaluation_periods  = 1
#   metric_name         = aws_cloudwatch_log_metric_filter.nacl_changes.metric_transformation[0].name
#   namespace           = "CISMetrics"
#   period              = 300
#   statistic           = "Sum"
#   threshold           = 1

#   alarm_actions = [aws_sns_topic.cis_alerts.arn]
#   ok_actions    = [aws_sns_topic.cis_alerts.arn]
# }

# #####################################
# # Metric Filter for Network Gateway Changes
# #####################################
# resource "aws_cloudwatch_log_metric_filter" "network_gateway_changes" {
#   name           = "NetworkGatewayChanges"
#   log_group_name = aws_cloudwatch_log_group.trail.name

#   # Matches Create/Delete/Attach/Detach Internet and VPC gateways
#   pattern = "{ ($.eventName = CreateCustomerGateway) || ($.eventName = DeleteCustomerGateway) || ($.eventName = AttachInternetGateway) || ($.eventName = CreateInternetGateway) || ($.eventName = DeleteInternetGateway) || ($.eventName = DetachInternetGateway) }"

#   metric_transformation {
#     name      = "NetworkGatewayChangeCount"
#     namespace = "CISMetrics"
#     value     = "1"
#   }
# }

# #####################################
# # Alarm for Network Gateway Changes
# #####################################
# resource "aws_cloudwatch_metric_alarm" "network_gateway_changes_alarm" {
#   alarm_name          = "NetworkGatewayChangesAlarm"
#   alarm_description   = "CIS Benchmark: Detect changes to network gateways"
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   evaluation_periods  = 1
#   metric_name         = aws_cloudwatch_log_metric_filter.network_gateway_changes.metric_transformation[0].name
#   namespace           = "CISMetrics"
#   period              = 300
#   statistic           = "Sum"
#   threshold           = 1

#   alarm_actions = [aws_sns_topic.cis_alerts.arn]
#   ok_actions    = [aws_sns_topic.cis_alerts.arn]
# }

# #####################################
# # Metric Filter for Route Table Changes
# #####################################
# resource "aws_cloudwatch_log_metric_filter" "route_table_changes" {
#   name           = "RouteTableChanges"
#   log_group_name = aws_cloudwatch_log_group.trail.name

#   # Matches Create, Replace, Associate, Disassociate, Delete route table/route events
#   pattern = "{ ($.eventSource=ec2.amazonaws.com) && (($.eventName = CreateRoute) || ($.eventName = CreateRouteTable) || ($.eventName = ReplaceRoute) || ($.eventName = ReplaceRouteTableAssociation) || ($.eventName = DeleteRouteTable) || ($.eventName = DeleteRoute) || ($.eventName = DisassociateRouteTable)) }"

#   metric_transformation {
#     name      = "RouteTableChangeCount"
#     namespace = "CISMetrics"
#     value     = "1"
#   }
# }

# #####################################
# # Alarm for Route Table Changes
# #####################################
# resource "aws_cloudwatch_metric_alarm" "route_table_changes_alarm" {
#   alarm_name          = "RouteTableChangesAlarm"
#   alarm_description   = "CIS Benchmark: Detect changes to route tables"
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   evaluation_periods  = 1
#   metric_name         = aws_cloudwatch_log_metric_filter.route_table_changes.metric_transformation[0].name
#   namespace           = "CISMetrics"
#   period              = 300
#   statistic           = "Sum"
#   threshold           = 1

#   alarm_actions = [aws_sns_topic.cis_alerts.arn]
#   ok_actions    = [aws_sns_topic.cis_alerts.arn]
# }

# #####################################
# # Metric Filter for VPC Changes
# #####################################
# resource "aws_cloudwatch_log_metric_filter" "vpc_changes" {
#   name           = "VPCChanges"
#   log_group_name = aws_cloudwatch_log_group.trail.name

#   # Matches Create/Delete/Modify VPC-related events
#   pattern = "{ ($.eventName = CreateVpc) || ($.eventName = DeleteVpc) || ($.eventName = ModifyVpcAttribute) || ($.eventName = AcceptVpcPeeringConnection) || ($.eventName = CreateVpcPeeringConnection) || ($.eventName = DeleteVpcPeeringConnection) || ($.eventName = RejectVpcPeeringConnection) || ($.eventName = AttachClassicLinkVpc) || ($.eventName = DetachClassicLinkVpc) || ($.eventName = DisableVpcClassicLink) || ($.eventName = EnableVpcClassicLink) }"

#   metric_transformation {
#     name      = "VPCChangeCount"
#     namespace = "CISMetrics"
#     value     = "1"
#   }
# }

# #####################################
# # Alarm for VPC Changes
# #####################################
# resource "aws_cloudwatch_metric_alarm" "vpc_changes_alarm" {
#   alarm_name          = "VPCChangesAlarm"
#   alarm_description   = "CIS Benchmark: Detect changes to VPCs"
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   evaluation_periods  = 1
#   metric_name         = aws_cloudwatch_log_metric_filter.vpc_changes.metric_transformation[0].name
#   namespace           = "CISMetrics"
#   period              = 300
#   statistic           = "Sum"
#   threshold           = 1

#   alarm_actions = [aws_sns_topic.cis_alerts.arn]
#   ok_actions    = [aws_sns_topic.cis_alerts.arn]
# }

# #####################################
# # Metric Filter for IAM Policy Changes
# #####################################
# resource "aws_cloudwatch_log_metric_filter" "iam_policy_changes" {
#   name           = "IAMPolicyChanges"
#   log_group_name = aws_cloudwatch_log_group.trail.name

#   # Matches IAM policy changes: Attach, Detach, Create, Delete, Update
#   pattern = "{($.eventSource=iam.amazonaws.com) && (($.eventName=DeleteGroupPolicy) || ($.eventName=DeleteRolePolicy) || ($.eventName=DeleteUserPolicy) || ($.eventName=PutGroupPolicy) || ($.eventName=PutRolePolicy) || ($.eventName=PutUserPolicy) || ($.eventName=CreatePolicy) || ($.eventName=DeletePolicy) || ($.eventName=CreatePolicyVersion) || ($.eventName=DeletePolicyVersion) || ($.eventName=AttachRolePolicy) || ($.eventName=DetachRolePolicy) || ($.eventName=AttachUserPolicy) || ($.eventName=DetachUserPolicy) || ($.eventName=AttachGroupPolicy) || ($.eventName=DetachGroupPolicy))}"

#   metric_transformation {
#     name      = "IAMPolicyChangeCount"
#     namespace = "CISMetrics"
#     value     = "1"
#   }
# }

# #####################################
# # Alarm for IAM Policy Changes
# #####################################
# resource "aws_cloudwatch_metric_alarm" "iam_policy_changes_alarm" {
#   alarm_name          = "IAMPolicyChangesAlarm"
#   alarm_description   = "CIS Benchmark: Detect changes to IAM policies"
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   evaluation_periods  = 1
#   metric_name         = aws_cloudwatch_log_metric_filter.iam_policy_changes.metric_transformation[0].name
#   namespace           = "CISMetrics"
#   period              = 300
#   statistic           = "Sum"
#   threshold           = 1

#   alarm_actions = [aws_sns_topic.cis_alerts.arn]
#   ok_actions    = [aws_sns_topic.cis_alerts.arn]
# }

# #####################################
# # Metric Filter for CloudTrail Configuration Changes
# #####################################
# resource "aws_cloudwatch_log_metric_filter" "cloudtrail_config_changes" {
#   name           = "CloudTrailConfigChanges"
#   log_group_name = aws_cloudwatch_log_group.trail.name

#   # Matches changes to CloudTrail configuration
#   pattern = "{ ($.eventName = CreateTrail) || ($.eventName = UpdateTrail) || ($.eventName = DeleteTrail) || ($.eventName = StartLogging) || ($.eventName = StopLogging) }"

#   metric_transformation {
#     name      = "CloudTrailConfigChangeCount"
#     namespace = "CISMetrics"
#     value     = "1"
#   }
# }

# #####################################
# # Alarm for CloudTrail Configuration Changes
# #####################################
# resource "aws_cloudwatch_metric_alarm" "cloudtrail_config_changes_alarm" {
#   alarm_name          = "CloudTrailConfigChangesAlarm"
#   alarm_description   = "CIS Benchmark: Detect CloudTrail configuration changes"
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   evaluation_periods  = 1
#   metric_name         = aws_cloudwatch_log_metric_filter.cloudtrail_config_changes.metric_transformation[0].name
#   namespace           = "CISMetrics"
#   period              = 300
#   statistic           = "Sum"
#   threshold           = 1

#   alarm_actions = [aws_sns_topic.cis_alerts.arn]
#   ok_actions    = [aws_sns_topic.cis_alerts.arn]
# }

# #####################################
# # Metric Filter for Console Authentication Failures
# #####################################
# resource "aws_cloudwatch_log_metric_filter" "console_auth_failures" {
#   name           = "ConsoleAuthFailures"
#   log_group_name = aws_cloudwatch_log_group.trail.name

#   # Matches failed AWS Management Console login attempts
#   pattern = "{ ($.eventName = ConsoleLogin) && ($.errorMessage = \"Failed authentication\") }"

#   metric_transformation {
#     name      = "ConsoleAuthFailureCount"
#     namespace = "CISMetrics"
#     value     = "1"
#   }
# }

# #####################################
# # Alarm for Console Authentication Failures
# #####################################
# resource "aws_cloudwatch_metric_alarm" "console_auth_failures_alarm" {
#   alarm_name          = "ConsoleAuthFailuresAlarm"
#   alarm_description   = "CIS Benchmark: Detect AWS Management Console authentication failures"
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   evaluation_periods  = 1
#   metric_name         = aws_cloudwatch_log_metric_filter.console_auth_failures.metric_transformation[0].name
#   namespace           = "CISMetrics"
#   period              = 300
#   statistic           = "Sum"
#   threshold           = 1

#   alarm_actions = [aws_sns_topic.cis_alerts.arn]
#   ok_actions    = [aws_sns_topic.cis_alerts.arn]
# }

# #####################################
# # Metric Filter for CMK Disable/Delete Events
# #####################################
# resource "aws_cloudwatch_log_metric_filter" "cmk_disable_or_delete" {
#   name           = "CMKDisableOrDelete"
#   log_group_name = aws_cloudwatch_log_group.trail.name

#   # Matches disabling or scheduling deletion of KMS CMKs
#   pattern = "{ ($.eventSource = kms.amazonaws.com) && (($.eventName = DisableKey) || ($.eventName = ScheduleKeyDeletion)) }"

#   metric_transformation {
#     name      = "CMKDisableOrDeleteCount"
#     namespace = "CISMetrics"
#     value     = "1"
#   }
# }

# #####################################
# # Alarm for CMK Disable/Delete Events
# #####################################
# resource "aws_cloudwatch_metric_alarm" "cmk_disable_or_delete_alarm" {
#   alarm_name          = "CMKDisableOrDeleteAlarm"
#   alarm_description   = "CIS Benchmark: Detect disabling or scheduled deletion of customer-managed CMKs"
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   evaluation_periods  = 1
#   metric_name         = aws_cloudwatch_log_metric_filter.cmk_disable_or_delete.metric_transformation[0].name
#   namespace           = "CISMetrics"
#   period              = 300
#   statistic           = "Sum"
#   threshold           = 1

#   alarm_actions = [aws_sns_topic.cis_alerts.arn]
#   ok_actions    = [aws_sns_topic.cis_alerts.arn]
# }

# #####################################
# # Metric Filter for S3 Bucket Policy Changes
# #####################################
# resource "aws_cloudwatch_log_metric_filter" "s3_bucket_policy_changes" {
#   name           = "S3BucketPolicyChanges"
#   log_group_name = aws_cloudwatch_log_group.trail.name

#   # Matches changes to S3 bucket policies
#   pattern = "{ ($.eventSource = s3.amazonaws.com) && (($.eventName = PutBucketAcl) || ($.eventName = PutBucketPolicy) || ($.eventName = PutBucketCors) || ($.eventName = PutBucketLifecycle) || ($.eventName = PutBucketReplication) || ($.eventName = DeleteBucketPolicy) || ($.eventName = DeleteBucketCors) || ($.eventName = DeleteBucketLifecycle) || ($.eventName = DeleteBucketReplication)) }"

#   metric_transformation {
#     name      = "S3BucketPolicyChangeCount"
#     namespace = "CISMetrics"
#     value     = "1"
#   }
# }

# #####################################
# # Alarm for S3 Bucket Policy Changes
# #####################################
# resource "aws_cloudwatch_metric_alarm" "s3_bucket_policy_changes_alarm" {
#   alarm_name          = "S3BucketPolicyChangesAlarm"
#   alarm_description   = "CIS Benchmark: Detect S3 bucket policy or ACL changes"
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   evaluation_periods  = 1
#   metric_name         = aws_cloudwatch_log_metric_filter.s3_bucket_policy_changes.metric_transformation[0].name
#   namespace           = "CISMetrics"
#   period              = 300
#   statistic           = "Sum"
#   threshold           = 1

#   alarm_actions = [aws_sns_topic.cis_alerts.arn]
#   ok_actions    = [aws_sns_topic.cis_alerts.arn]
# }

# #####################################
# # Metric Filter for AWS Config Configuration Changes
# #####################################
# resource "aws_cloudwatch_log_metric_filter" "config_changes" {
#   name           = "ConfigConfigurationChanges"
#   log_group_name = aws_cloudwatch_log_group.trail.name

#   # Matches AWS Config configuration recorder & delivery changes
#   pattern = "{ ($.eventSource = config.amazonaws.com) && (($.eventName = StopConfigurationRecorder) || ($.eventName = DeleteDeliveryChannel) || ($.eventName = PutDeliveryChannel) || ($.eventName = PutConfigurationRecorder)) }"

#   metric_transformation {
#     name      = "ConfigChangeCount"
#     namespace = "CISMetrics"
#     value     = "1"
#   }
# }

# #####################################
# # Alarm for AWS Config Configuration Changes
# #####################################
# resource "aws_cloudwatch_metric_alarm" "config_changes_alarm" {
#   alarm_name          = "ConfigConfigurationChangesAlarm"
#   alarm_description   = "CIS Benchmark: Detect changes to AWS Config configuration"
#   comparison_operator = "GreaterThanOrEqualToThreshold"
#   evaluation_periods  = 1
#   metric_name         = aws_cloudwatch_log_metric_filter.config_changes.metric_transformation[0].name
#   namespace           = "CISMetrics"
#   period              = 300
#   statistic           = "Sum"
#   threshold           = 1

#   alarm_actions = [aws_sns_topic.cis_alerts.arn]
#   ok_actions    = [aws_sns_topic.cis_alerts.arn]
# }

# #####################################
# # IAM Role for AWS Support
# #####################################
# resource "aws_iam_role" "aws_support_role" {
#   name = "AWSIncidentsSupportRole"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Principal = {
#           AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
#         }
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })

#   description = "Role for AWS Support to manage incidents"
# }

# resource "aws_iam_role_policy_attachment" "aws_support_role_attach" {
#   role       = aws_iam_role.aws_support_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AWSSupportAccess"
# }

# #####################################
# # Logging target bucket for access logs
# #####################################
# resource "aws_s3_bucket" "cloudtrail_access_logs" {
#   bucket = "cis-cloudtrail-access-logs-${data.aws_caller_identity.current.account_id}"

#   tags = {
#     Purpose = "AccessLogsForCloudTrailBucket"
#   }
# }

# resource "aws_s3_bucket_logging" "cloudtrail" {
#   bucket = aws_s3_bucket.cloudtrail.id

#   target_bucket = aws_s3_bucket.cloudtrail_access_logs.id
#   target_prefix = "cloudtrail-logs/"
# }
