resource "aws_dynamodb_table" "habitats" {
  name         = "${var.name_prefix}-habitats"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "habitat_id"
  range_key    = "record_type"

  attribute {
    name = "habitat_id"
    type = "S"
  }

  attribute {
    name = "record_type"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "updated_at"
    type = "S"
  }

  global_secondary_index {
    name            = "active-by-update"
    hash_key        = "status"
    range_key       = "updated_at"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = var.habitat_ttl_days > 0
  }
}

resource "aws_dynamodb_table" "cycle_locks" {
  name         = "${var.name_prefix}-cycle-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "lock_id"

  attribute {
    name = "lock_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  server_side_encryption {
    enabled = true
  }
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "simulation" {
  name               = "${var.name_prefix}-simulation"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "simulation" {
  statement {
    sid = "HabitatState"

    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:ConditionCheckItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:UpdateItem"
    ]

    resources = [
      aws_dynamodb_table.habitats.arn,
      "${aws_dynamodb_table.habitats.arn}/index/*",
      aws_dynamodb_table.cycle_locks.arn
    ]
  }

  statement {
    sid = "StructuredLogs"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["${aws_cloudwatch_log_group.simulation.arn}:*"]
  }

  statement {
    sid       = "EcosystemMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["DigitalTerrarium"]
    }
  }
}

resource "aws_iam_role_policy" "simulation" {
  name   = "terrarium-state-and-metrics"
  role   = aws_iam_role.simulation.id
  policy = data.aws_iam_policy_document.simulation.json
}

resource "aws_cloudwatch_log_group" "simulation" {
  name              = "/aws/lambda/${var.name_prefix}-simulation"
  retention_in_days = 14
}

resource "aws_lambda_function" "simulation" {
  function_name = "${var.name_prefix}-simulation"
  role          = aws_iam_role.simulation.arn
  runtime       = "provided.al2023"
  architectures = ["arm64"]
  handler       = "bootstrap"
  filename      = var.lambda_zip_path
  source_code_hash = try(filebase64sha256(var.lambda_zip_path), null)
  publish          = true
  memory_size   = var.lambda_memory_mb
  timeout       = var.lambda_timeout_seconds

  environment {
    variables = {
      HABITAT_TABLE       = aws_dynamodb_table.habitats.name
      CYCLE_LOCK_TABLE    = aws_dynamodb_table.cycle_locks.name
      HABITAT_TTL_DAYS    = tostring(var.habitat_ttl_days)
      METRIC_NAMESPACE    = "DigitalTerrarium"
      ECOLOGY_RULESET     = "cycle-v1"
    }
  }

  depends_on = [
    aws_iam_role_policy.simulation,
    aws_cloudwatch_log_group.simulation
  ]
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  description      = "Stable alias for the terrarium API"
  function_name    = aws_lambda_function.simulation.function_name
  function_version = aws_lambda_function.simulation.version
}

resource "aws_apigatewayv2_api" "habitat" {
  name          = "${var.name_prefix}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.allowed_origins
    allow_methods = ["GET", "PUT", "POST", "DELETE", "OPTIONS"]
    allow_headers = ["content-type", "if-match", "x-terrarium-seed", "x-request-id"]
    expose_headers = ["etag", "x-request-id"]
    max_age = 86400
  }
}

resource "aws_apigatewayv2_integration" "simulation" {
  api_id                 = aws_apigatewayv2_api.habitat.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.simulation.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 10000
}

locals {
  routes = toset([
    "GET /health",
    "GET /habitats/{id}",
    "PUT /habitats/{id}",
    "POST /habitats/{id}/cycle",
    "DELETE /habitats/{id}"
  ])
}

resource "aws_apigatewayv2_route" "habitat" {
  for_each = local.routes

  api_id    = aws_apigatewayv2_api.habitat.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.simulation.id}"
}

resource "aws_apigatewayv2_stage" "live" {
  api_id      = aws_apigatewayv2_api.habitat.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = var.api_burst_limit
    throttling_rate_limit  = var.api_rate_limit
    detailed_metrics_enabled = true
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      integrationMs  = "$context.integrationLatency"
      sourceIp       = "$context.identity.sourceIp"
    })
  }
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${var.name_prefix}"
  retention_in_days = 14
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowHabitatApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.simulation.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.habitat.execution_arn}/*/*"
}
