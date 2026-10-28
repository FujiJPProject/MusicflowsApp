provider "aws" {
  region     = var.aws_region
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  skip_region_validation      = true
  s3_use_path_style           = true

  # Docker Compose内ではlocalhostではなくサービス名で接続する。
  endpoints {
    s3  = var.floci_endpoint_url
    sqs = var.floci_endpoint_url
  }
}
