# 今回新規導入する失敗メッセージ用キュー。
resource "aws_sqs_queue" "dlq" {
  name                      = var.dlq_name
  message_retention_seconds = 1209600 # 14日
}

# Shell 02-init-sqs.sh のキュー名・180秒・標準キューを維持。
resource "aws_sqs_queue" "jobs" {
  name                       = var.job_queue_name
  visibility_timeout_seconds = 180
  message_retention_seconds  = 345600 # 既定の4日; import前に現物照合
  receive_wait_time_seconds  = 0
  fifo_queue                 = false

  # Issue 35 で唯一意図的に追加する既存キューの処理動作。
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}

# Floci互換性を考慮してオプション扱いとする。
# AWS側ではDLQをこの処理キューからのredriveだけに限定する。
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  count     = var.enable_redrive_allow_policy ? 1 : 0
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.jobs.arn]
  })
}
