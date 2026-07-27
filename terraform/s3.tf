resource "aws_s3_bucket" "frontend" {
  for_each = local.environments

  # バケット名はグローバル一意のため account_id を付与
  bucket        = "${local.name_prefix}-${each.key}-frontend-${local.account_id}"
  force_destroy = true # チュートリアル用

  # バケット名だけは 63 文字制限がきつく、末尾のアカウント ID (12 桁) で
  # 大半を使い切っている。var.owner の長さ検証は既定の project_name を前提に
  # した値なので、project_name を変えた場合はここで初めて超過が分かる。
  # AWS 側の InvalidBucketName より先に、原因が分かる形で plan を止める。
  lifecycle {
    precondition {
      condition     = length("${local.name_prefix}-${each.key}-frontend-${local.account_id}") <= 63
      error_message = "S3 バケット名が 63 文字を超えます。var.owner か var.project_name を短くしてください."
    }
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  for_each = local.environments

  bucket                  = aws_s3_bucket.frontend[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront (OAC) からのみ読み取りを許可
data "aws_iam_policy_document" "frontend_bucket" {
  for_each = local.environments

  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend[each.key].arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.app[each.key].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  for_each = local.environments

  bucket = aws_s3_bucket.frontend[each.key].id
  policy = data.aws_iam_policy_document.frontend_bucket[each.key].json
}
