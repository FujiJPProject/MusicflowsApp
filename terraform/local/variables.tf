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
