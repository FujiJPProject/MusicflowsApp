variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "floci_endpoint_url" {
  type    = string
  default = "http://floci:4566"

  validation {
    condition     = var.floci_endpoint_url == "http://floci:4566"
    error_message = "ローカルTerraformはDockerネットワーク内のFlociだけに接続します。"
  }
}

variable "file_bucket_name" {
  type    = string
  default = "music-app-local-files"
}

variable "job_queue_name" {
  type    = string
  default = "music-app-local-music-jobs"
}

variable "dlq_name" {
  type    = string
  default = "music-app-local-music-jobs-dlq"
}

variable "enable_runtime_infrastructure" {
  type    = bool
  default = false
}

variable "frontend_origin" {
  type    = string
  default = "http://localhost:5173"
}

variable "floci_host_url" {
  type    = string
  default = "http://localhost:4566"
}

variable "enable_snapstart" {
  type    = bool
  default = true
}

variable "api_zip_hash" {
  type    = string
  default = ""
}

variable "worker_zip_hash" {
  type    = string
  default = ""
}

variable "worker_execution_mode" {
  type    = string
  default = "lambda"

  validation {
    condition     = contains(["lambda", "local"], var.worker_execution_mode)
    error_message = "Choose lambda or local."
  }
}

# Issue #37: 既存Floci環境の意図しない変更を避けるためオプトイン。
variable "enable_frontend_delivery" {
  type    = bool
  default = false
}

variable "frontend_bucket_name" {
  type    = string
  default = "music-app-local-frontend"
}

# 独立テスト用Compose: 127.0.0.1:4567 -> Floci:4566
variable "floci_viewer_port" {
  type    = number
  default = 4567

  validation {
    condition     = var.floci_viewer_port >= 1 && var.floci_viewer_port <= 65535
    error_message = "floci_viewer_portは1〜65535を指定してください。"
  }
}
