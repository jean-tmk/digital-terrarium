output "table_name" {
  value = aws_dynamodb_table.habitats.name
}

output "function_name" {
  value = aws_lambda_function.simulation.function_name
}

output "function_arn" {
  value = aws_lambda_function.simulation.arn
}

output "api_id" {
  value = aws_apigatewayv2_api.habitat.id
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.habitat.api_endpoint
}

output "api_stage_name" {
  value = aws_apigatewayv2_stage.live.name
}
