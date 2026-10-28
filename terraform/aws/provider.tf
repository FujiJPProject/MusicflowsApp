provider "aws" {
  region = var.aws_region

  # 不適切なAWS Profileによる他アカウントへの適用を防ぐ。
  allowed_account_ids = [var.aws_account_id]
}
