variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
}

variable "habitat_ttl_days" {
  type        = number
  description = "Inactive habitat retention."
}

variable "enable_point_in_time_recovery" {
  type        = bool
  description = "Enable DynamoDB point-in-time recovery."
}

variable "lambda_zip_path" {
  type        = string
  description = "Compiled Go Lambda archive."
}

variable "lambda_memory_mb" {
  type        = number
  description = "Simulation function memory."
}

variable "lambda_timeout_seconds" {
  type        = number
  description = "Simulation function timeout."
}

variable "allowed_origins" {
  type        = list(string)
  description = "CORS origins."
}

variable "api_burst_limit" {
  type        = number
  description = "HTTP API burst throttle."
}

variable "api_rate_limit" {
  type        = number
  description = "HTTP API rate throttle."
}
