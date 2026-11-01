# REST API / ANY proxy; the Spring Security filter validates access tokens.
resource "aws_api_gateway_rest_api" "api" {
  name = "${local.prefix}-api"
}
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id = aws_api_gateway_rest_api.api.root_resource_id
  path_part = "{proxy+}"
}
resource "aws_api_gateway_method" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = "ANY"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method
  type = "AWS_PROXY"
  integration_http_method = "POST"
  # Route to the published version through the live alias (not $LATEST).
  uri = aws_lambda_alias.api.invoke_arn
}
resource "aws_lambda_permission" "api_gateway" {
  statement_id = "allow-api-gateway-invoke"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  qualifier = aws_lambda_alias.api.name
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/*"
}
resource "aws_api_gateway_deployment" "api" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  triggers = {
    redeployment = sha1(jsonencode({
      resource = aws_api_gateway_resource.proxy.id
      method = aws_api_gateway_method.proxy.http_method
      authorization = aws_api_gateway_method.proxy.authorization
      integration = aws_api_gateway_integration.proxy.uri
    }))
  }
  lifecycle { create_before_destroy = true }
  depends_on = [aws_api_gateway_integration.proxy, aws_lambda_permission.api_gateway]
}
resource "aws_api_gateway_stage" "api" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name = var.stage_name
  deployment_id = aws_api_gateway_deployment.api.id
}
