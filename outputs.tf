output "site_bucket_name" {
  description = "Private S3 bucket containing the terrarium."
  value       = aws_s3_bucket.site.id
}

output "site_url" {
  description = "CloudFront URL when enabled."
  value = var.enable_cloudfront ? (
    var.custom_domain == null
    ? "https://${aws_cloudfront_distribution.site[0].domain_name}"
    : "https://${var.custom_domain}"
  ) : null
}

output "api_url" {
  description = "Base URL for the habitat API."
  value       = module.habitat.api_endpoint
}

output "habitat_table_name" {
  description = "DynamoDB table storing ecosystem state."
  value       = module.habitat.table_name
}

output "simulation_function_name" {
  description = "Go Lambda function running climate cycles."
  value       = module.habitat.function_name
}

output "observatory_dashboard" {
  description = "CloudWatch dashboard for the ecosystem."
  value       = module.observatory.dashboard_name
}

output "climate_schedule" {
  description = "Automatic cycle schedule when enabled."
  value       = try(aws_scheduler_schedule.climate_cycle[0].schedule_expression, null)
}

output "deployment_summary" {
  description = "Useful endpoints and operational identifiers."
  value = {
    environment = var.environment
    site        = var.enable_cloudfront ? aws_cloudfront_distribution.site[0].domain_name : null
    api         = module.habitat.api_endpoint
    table       = module.habitat.table_name
    dashboard   = module.observatory.dashboard_name
  }
}
