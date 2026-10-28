# IAMロールやIAMポリシー自体の作成・アタッチはMusicflowInfraで行う。
# このmoduleはアプリ専用の最小権限のドキュメントだけを生成する。
data "aws_iam_policy_document" "api" {
  statement {
    sid       = "SubmitMusicJobs"
    actions   = ["sqs:GetQueueUrl", "sqs:SendMessage"]
    resources = [aws_sqs_queue.jobs.arn]
  }

  statement {
    sid       = "ReadJobResults"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.files.arn}/worker-results/*"]
  }

  # GetObjectで存在しないキーを403ではなく404として識別するため。
  statement {
    sid       = "ListJobResultBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.files.arn]
  }
}

data "aws_iam_policy_document" "worker" {
  statement {
    sid = "ConsumeMusicJobs"
    actions = [
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [aws_sqs_queue.jobs.arn]
  }

  statement {
    sid       = "WriteJobResults"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.files.arn}/worker-results/*"]
  }
}

data "aws_iam_policy_document" "artifact_deployer" {
  statement {
    sid       = "ManageLambdaArtifacts"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.files.arn}/_lambda-artifacts/*"]
  }
}
