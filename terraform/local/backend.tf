terraform {
  required_version = ">= 1.15.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Floci専用。実AWSとstateを共有しない。
  backend "local" {
    path = "terraform.tfstate"
  }
}
