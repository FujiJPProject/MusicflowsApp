variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "file_bucket_name" {
  type = string
}

variable "job_queue_name" {
  type = string
}

variable "job_queue_arn" {
  type = string
}

variable "api_role_arn" {
  type = string
}

variable "worker_role_arn" {
  type = string
}

variable "frontend_origin" {
  type = string
}

variable "api_zip_hash" {
  type = string
}

variable "worker_zip_hash" {
  type = string
}

variable "stage_name" {
  type    = string
  default = "local"
}

variable "floci_internal_url" {
  type    = string
  default = "http://floci:4566"
}

variable "floci_host_url" {
  type    = string
  default = "http://localhost:4566"
}

variable "enable_snapstart" {
  type    = bool
  default = true
}

variable "worker_execution_mode" {
  type    = string
  default = "lambda"

  validation {
    condition     = contains(["lambda", "local"], var.worker_execution_mode)
    error_message = "Choose lambda or local."
  }
}

# ViteとCloudFrontを同じAPIへ接続するためのCORS設定
variable "frontend_allowed_origins" {
  type        = string
  description = "APIにアクセス可能なブラウザOriginのカンマ区切りリスト"
}
