resource "aws_athena_database" "cost_usage_reports" {
  name   = "cost_usage_reports"
  bucket = aws_s3_bucket.cost_usage_reports.id
}

resource "aws_athena_workgroup" "cost_usage_reports" {
  name = "cost-usage-reports"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.cost_usage_reports.bucket}/athena-results/"
    }
  }
}

resource "aws_glue_catalog_table" "cost_usage_reports" {
  name          = "cur_per_service"
  database_name = aws_athena_database.cost_usage_reports.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                              = "TRUE"
    classification                        = "parquet"
    "projection.enabled"                  = "true"
    "projection._year.type"               = "integer"
    "projection._year.range"              = "2026,2040"
    "projection._month.type"              = "integer"
    "projection._month.range"             = "1,12"
    "projection._month.digits"            = "2"
    "hive.mapred.supports.subdirectories" = "true"
    "mapred.input.dir.recursive"          = "true"
    "storage.location.template"           = "s3://${aws_s3_bucket.cost_usage_reports.bucket}/cost-usage-reports/aws-billing-report-per-service/data/BILLING_PERIOD=$${_year}-$${_month}/"
  }

  partition_keys {
    name = "_year"
    type = "string"
  }
  partition_keys {
    name = "_month"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.cost_usage_reports.bucket}/cost-usage-reports/aws-billing-report-per-service/data/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "identity_line_item_id"
      type = "string"
    }

    columns {
      name = "line_item_product_code"
      type = "string"
    }

    columns {
      name = "line_item_unblended_cost"
      type = "double"
    }

    columns {
      name = "line_item_usage_type"
      type = "string"
    }

    columns {
      name = "line_item_line_item_type"
      type = "string"
    }

    columns {
      name = "line_item_usage_amount"
      type = "double"
    }

    columns {
      name = "pricing_unit"
      type = "string"
    }

    columns {
      name = "line_item_net_unblended_cost"
      type = "double"
    }

  }
}

# resource "aws_athena_named_query" "spend_by_service_month" {
#   name      = "cur_spend_by_service_month"
#   database  = aws_athena_database.cost_usage_reports.name
#   workgroup = aws_athena_workgroup.cost_usage_reports.name

#   query = <<-SQL
#     SELECT
#       line_item_product_code AS service,
#       ROUND(SUM(COALESCE(line_item_net_unblended_cost, line_item_unblended_cost)), 2) AS spend_usd
#     FROM cur_per_service
#     WHERE billing_period = '2026-04'
#     GROUP BY 1
#     ORDER BY 2 DESC;
#   SQL
# }
