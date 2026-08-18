resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alarm_email == null ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name_prefix}-simulation-errors"
  alarm_description   = "The ecosystem simulation is returning errors."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = var.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${var.name_prefix}-slow-cycles"
  alarm_description   = "Terrarium climate cycles are taking too long."
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 2
  threshold           = 3000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = var.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.name_prefix}-api-5xx"
  alarm_description   = "The habitat API is returning server errors."
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ApiId = var.api_id
    Stage = var.api_stage_name
  }
}

resource "aws_cloudwatch_metric_alarm" "request_budget" {
  alarm_name          = "${var.name_prefix}-request-budget"
  alarm_description   = "The terrarium is approaching its monthly request budget."
  namespace           = "AWS/ApiGateway"
  metric_name         = "Count"
  statistic           = "Sum"
  period              = 2592000
  evaluation_periods  = 1
  threshold           = var.monthly_request_budget
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ApiId = var.api_id
  }
}

resource "aws_cloudwatch_metric_alarm" "low_biodiversity" {
  alarm_name          = "${var.name_prefix}-low-biodiversity"
  alarm_description   = "Average biodiversity fell below the safe threshold."
  namespace           = "DigitalTerrarium"
  metric_name         = "Biodiversity"
  statistic           = "Average"
  period              = 900
  evaluation_periods  = 2
  threshold           = 0.35
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "terrarium" {
  dashboard_name = "${var.name_prefix}-observatory"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# Digital Terrarium Observatory\nLive habitat, climate, and API signals."
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 12
        height = 6
        properties = {
          title  = "Ecosystem health"
          region = data.aws_region.current.name
          view   = "timeSeries"
          metrics = [
            ["DigitalTerrarium", "Biodiversity"],
            [".", "Moisture"],
            [".", "Population"],
            [".", "CycleDuration"]
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 2
        width  = 12
        height = 6
        properties = {
          title  = "Simulation runtime"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "Habitat state traffic"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.table_name],
            [".", "ConsumedWriteCapacityUnits", ".", "."]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "API requests"
          region = data.aws_region.current.name
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", var.api_id],
            [".", "4xx", ".", "."],
            [".", "5xx", ".", "."]
          ]
          period = 300
          stat   = "Sum"
        }
      }
    ]
  })
}

data "aws_region" "current" {}
