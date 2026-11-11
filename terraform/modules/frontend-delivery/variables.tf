variable "name_prefix" {
  description = "Floci上のフロントエンド配信リソース名の接頭辞"
  type        = string
}

variable "frontend_bucket_name" {
  description = "ジョブ結果格納用とは独立したS3バケット名"
  type        = string
}
