terraform {
  required_version = ">= 1.15.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # bucket/region/use_lockfileはMusicflowInfraの既存tfbackendからinit時に注入する。
  # Flociのローカルstateと完全に分離する。
  backend "s3" {
    key = "musicflows-app/dev/job-messaging/terraform.tfstate"
  }
}
