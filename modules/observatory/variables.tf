variable "name_prefix" {
  type = string
}

variable "function_name" {
  type = string
}

variable "function_arn" {
  type = string
}

variable "api_id" {
  type = string
}

variable "api_stage_name" {
  type = string
}

variable "table_name" {
  type = string
}

variable "monthly_request_budget" {
  type = number
}

variable "log_retention_days" {
  type = number
}

variable "alarm_email" {
  type    = string
  default = null
}
