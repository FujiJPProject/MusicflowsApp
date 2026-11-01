locals { prefix = "${var.project_name}-${var.environment}" }
resource "aws_cognito_user_pool" "users" {
  name = "${local.prefix}-users"
}
resource "aws_cognito_user_pool_client" "web" {
  name = "${local.prefix}-web-client"
  user_pool_id = aws_cognito_user_pool.users.id
  generate_secret = false
  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
}
# Test users/passwords are provisioned outside of Terraform.
