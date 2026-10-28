variable "file_bucket_name" {
  description = "既存のFILE_BUCKETと一致させる"
  type        = string
}

variable "job_queue_name" {
  description = "既存のQUEUE_NAMEと一致させる"
  type        = string
}

variable "dlq_name" {
  description = "今回追加するDLQ名"
  type        = string
}

variable "max_receive_count" {
  type    = number
  default = 5

  validation {
    condition     = var.max_receive_count >= 5 && var.max_receive_count <= 1000 && floor(var.max_receive_count) == var.max_receive_count
    error_message = "max_receive_countは5〜1000の整数を指定してください。"
  }
}

variable "enable_redrive_allow_policy" {
  description = "Flociでのサポート検証まではfalse、AWSではtrue"
  type        = bool
  default     = false
}
