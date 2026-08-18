variable "project_name" {
  description = "Stable name used for cloud resources."
  type        = string
  default     = "digital-terrarium"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project_name))
    error_message = "project_name must be lowercase kebab-case."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage, or prod."
  }
}

variable "aws_region" {
  description = "AWS region for regional resources."
  type        = string
  default     = "us-east-2"
}

variable "site_source_dir" {
  description = "Directory containing the static terrarium."
  type        = string
  default     = "."
}

variable "lambda_zip_path" {
  description = "Path to the compiled Go Lambda zip."
  type        = string
  default     = "api/lambda.zip"
}

variable "climate_cycle_schedule" {
  description = "EventBridge schedule for automatic ecosystem cycles."
  type        = string
  default     = "rate(15 minutes)"
}

variable "habitat_ttl_days" {
  description = "Days before inactive development habitats expire. Zero disables TTL."
  type        = number
  default     = 30

  validation {
    condition     = var.habitat_ttl_days >= 0 && var.habitat_ttl_days <= 3650
    error_message = "habitat_ttl_days must be between 0 and 3650."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention."
  type        = number
  default     = 14
}

variable "monthly_request_budget" {
  description = "Soft monthly API request budget used by observability alarms."
  type        = number
  default     = 100000
}

variable "allowed_origins" {
  description = "Origins permitted to call the habitat API."
  type        = list(string)
  default = [
    "http://localhost:4173",
    "https://jean-tmk.github.io"
  ]
}

variable "enable_cloudfront" {
  description = "Create a CloudFront distribution for the static terrarium."
  type        = bool
  default     = true
}

variable "enable_scheduled_cycles" {
  description = "Advance active habitats on a schedule."
  type        = bool
  default     = true
}

variable "enable_point_in_time_recovery" {
  description = "Protect habitat state with DynamoDB point-in-time recovery."
  type        = bool
  default     = true
}

variable "alarm_email" {
  description = "Optional email endpoint for observability alerts."
  type        = string
  default     = null
}

variable "custom_domain" {
  description = "Optional custom domain for CloudFront."
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "ACM certificate ARN in us-east-1 when custom_domain is set."
  type        = string
  default     = null

  validation {
    condition     = var.custom_domain == null || var.certificate_arn != null
    error_message = "certificate_arn is required when custom_domain is set."
  }
}

variable "lambda_memory_mb" {
  description = "Memory allocated to the Go simulation function."
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_mb >= 128 && var.lambda_memory_mb <= 10240
    error_message = "lambda_memory_mb must be between 128 and 10240."
  }
}

variable "lambda_timeout_seconds" {
  description = "Maximum simulation runtime."
  type        = number
  default     = 10
}

variable "api_burst_limit" {
  description = "HTTP API burst throttle."
  type        = number
  default     = 50
}

variable "api_rate_limit" {
  description = "HTTP API sustained requests per second."
  type        = number
  default     = 25
}

variable "additional_tags" {
  description = "Additional resource tags."
  type        = map(string)
  default     = {}
}
