variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "aws_account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_idは12桁を指定してください。"
  }
}

variable "file_bucket_name" {
  type = string
}

variable "job_queue_name" {
  type = string
}

variable "dlq_name" {
  type = string
}
