# Shell 01-init-s3.sh の単一バケットと名称を維持する。
# バケット内にはLambda ZIPやジョブ結果が存在するため強制削除しない。
resource "aws_s3_bucket" "files" {
  bucket        = var.file_bucket_name
  force_destroy = false
}
