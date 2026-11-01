locals {
  parameter_prefix = "/${var.project_name}/${var.environment}"
  host_api_url = "${var.floci_host_url}/restapis/${aws_api_gateway_rest_api.api.id}/${var.stage_name}/_user_request_"
  internal_api_url = "${var.floci_internal_url}/restapis/${aws_api_gateway_rest_api.api.id}/${var.stage_name}/_user_request_"
  runtime_parameters = {
    "app-name" = var.project_name
    "file-bucket-name" = var.file_bucket_name
    "music-job-queue-name" = var.job_queue_name
    "cognito-user-pool-id" = aws_cognito_user_pool.users.id
    "cognito-app-client-id" = aws_cognito_user_pool_client.web.id
    "api-id" = aws_api_gateway_rest_api.api.id
    "api-base-url-host" = local.host_api_url
    "api-base-url-internal" = local.internal_api_url
  }
}
resource "aws_ssm_parameter" "runtime" {
  for_each = local.runtime_parameters
  name = "${local.parameter_prefix}/${each.key}"
  type = "String"
  value = each.value
  depends_on = [aws_api_gateway_stage.api]
}
