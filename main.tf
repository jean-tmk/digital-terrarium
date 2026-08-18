resource "random_id" "suffix" {
  byte_length = 3

  keepers = {
    project     = var.project_name
    environment = var.environment
  }
}

module "habitat" {
  source = "./modules/habitat"

  name_prefix                  = local.resource_prefix
  habitat_ttl_days             = var.habitat_ttl_days
  enable_point_in_time_recovery = var.enable_point_in_time_recovery
  lambda_zip_path              = var.lambda_zip_path
  lambda_memory_mb             = var.lambda_memory_mb
  lambda_timeout_seconds       = var.lambda_timeout_seconds
  allowed_origins              = var.allowed_origins
  api_burst_limit              = var.api_burst_limit
  api_rate_limit               = var.api_rate_limit
}

resource "aws_s3_bucket" "site" {
  bucket = "${local.resource_prefix}-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id

  versioning_configuration {
    status = var.environment == "prod" ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_object" "site" {
  for_each = local.static_files

  bucket       = aws_s3_bucket.site.id
  key          = each.key
  source       = each.value.absolute_path
  etag         = filemd5(each.value.absolute_path)
  content_type = lookup(local.mime_types, each.value.extension, "application/octet-stream")
  cache_control = each.value.cache_control
}

resource "aws_cloudfront_origin_access_control" "site" {
  count = var.enable_cloudfront ? 1 : 0

  name                              = "${local.resource_prefix}-oac"
  description                       = "Private origin access for the digital terrarium"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "site" {
  count = var.enable_cloudfront ? 1 : 0

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "Digital Terrarium / ${var.environment}"
  price_class         = "PriceClass_100"
  aliases             = var.custom_domain == null ? [] : [var.custom_domain]

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "terrarium-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.site[0].id
  }

  default_cache_behavior {
    target_origin_id       = "terrarium-site"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    compress               = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400

    response_headers_policy_id = aws_cloudfront_response_headers_policy.site[0].id
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.custom_domain == null
    acm_certificate_arn            = var.custom_domain == null ? null : var.certificate_arn
    ssl_support_method             = var.custom_domain == null ? null : "sni-only"
    minimum_protocol_version       = var.custom_domain == null ? "TLSv1" : "TLSv1.2_2021"
  }
}

resource "aws_cloudfront_response_headers_policy" "site" {
  count = var.enable_cloudfront ? 1 : 0

  name = "${local.resource_prefix}-security"

  security_headers_config {
    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "SAMEORIGIN"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = false
      override                   = true
    }

    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=()"
      override = true
    }
  }
}

data "aws_iam_policy_document" "site_bucket" {
  count = var.enable_cloudfront ? 1 : 0

  statement {
    sid     = "CloudFrontReadOnly"
    actions = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site[0].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  count = var.enable_cloudfront ? 1 : 0

  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_bucket[0].json
}

resource "aws_scheduler_schedule" "climate_cycle" {
  count = var.enable_scheduled_cycles ? 1 : 0

  name                         = "${local.resource_prefix}-climate-cycle"
  schedule_expression          = var.climate_cycle_schedule
  schedule_expression_timezone = "UTC"
  state                        = "ENABLED"

  flexible_time_window {
    mode                      = "FLEXIBLE"
    maximum_window_in_minutes = 5
  }

  target {
    arn      = module.habitat.function_arn
    role_arn = aws_iam_role.scheduler[0].arn

    input = jsonencode({
      source = "terrarium.scheduler"
      action = "cycle-active-habitats"
    })

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }

    dead_letter_config {
      arn = aws_sqs_queue.climate_dead_letter[0].arn
    }
  }
}

resource "aws_sqs_queue" "climate_dead_letter" {
  count = var.enable_scheduled_cycles ? 1 : 0

  name                      = "${local.resource_prefix}-climate-dlq"
  message_retention_seconds = 1209600

  sqs_managed_sse_enabled = true
}

data "aws_iam_policy_document" "scheduler_assume" {
  count = var.enable_scheduled_cycles ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  count = var.enable_scheduled_cycles ? 1 : 0

  name               = "${local.resource_prefix}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume[0].json
}

data "aws_iam_policy_document" "scheduler" {
  count = var.enable_scheduled_cycles ? 1 : 0

  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [module.habitat.function_arn]
  }

  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.climate_dead_letter[0].arn]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  count = var.enable_scheduled_cycles ? 1 : 0

  name   = "invoke-climate-cycle"
  role   = aws_iam_role.scheduler[0].id
  policy = data.aws_iam_policy_document.scheduler[0].json
}

resource "aws_lambda_permission" "scheduler" {
  count = var.enable_scheduled_cycles ? 1 : 0

  statement_id  = "AllowScheduler"
  action        = "lambda:InvokeFunction"
  function_name = module.habitat.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.climate_cycle[0].arn
}

module "observatory" {
  source = "./modules/observatory"

  name_prefix           = local.resource_prefix
  function_name         = module.habitat.function_name
  function_arn          = module.habitat.function_arn
  api_id                = module.habitat.api_id
  api_stage_name        = module.habitat.api_stage_name
  table_name            = module.habitat.table_name
  monthly_request_budget = var.monthly_request_budget
  log_retention_days    = var.log_retention_days
  alarm_email           = var.alarm_email
}
