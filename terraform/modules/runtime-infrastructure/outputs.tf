output "api_url" { value = local.host_api_url }
output "api_id" { value = aws_api_gateway_rest_api.api.id }
output "api_function_name" { value = aws_lambda_function.api.function_name }
output "worker_function_name" { value = aws_lambda_function.worker.function_name }
output "mapping_uuid" { value = aws_lambda_event_source_mapping.worker.uuid }
output "user_pool_id" { value = aws_cognito_user_pool.users.id }
output "client_id" { value = aws_cognito_user_pool_client.web.id }
output "secret_name" { value = aws_secretsmanager_secret.db.name }
