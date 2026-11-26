provider "aws" {
  region = var.aws_region
  skip_credentials_validation = true
  skip_metadata_api_check = true
  skip_requesting_account_id = true
  skip_region_validation = true
  s3_use_path_style = true
  endpoints {
    cloudfront = var.floci_endpoint_url
    s3 = var.floci_endpoint_url
    sqs = var.floci_endpoint_url
    iam = var.floci_endpoint_url
    sts = var.floci_endpoint_url
    lambda = var.floci_endpoint_url
    apigateway = var.floci_endpoint_url
    cognitoidp = var.floci_endpoint_url
    ssm = var.floci_endpoint_url
    secretsmanager = var.floci_endpoint_url
  }
}
