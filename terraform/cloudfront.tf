# 環境ごとに 1 ディストリビューション。
#   デフォルト        -> S3 (SPA 静的ファイル、OAC)
#   /api/*           -> Lambda Function URL
# フロントと API を同一ドメインに載せることで CORS 設定を不要にしている。
resource "aws_cloudfront_origin_access_control" "frontend" {
  # OAC 名はアカウント内で一意である必要がある。1 アカウントを複数人で共有する場合、
  # ここが project_name のままだと 2 人目の apply が衝突する。
  # なお OAC は CloudFront 側がタグに対応しておらず、最小権限ポリシーでも
  # 所有者ごとに絞れない唯一のリソース (docs/00-setup.md に明記)。
  name                              = "${local.name_prefix}-frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

locals {
  # https://xxxx.lambda-url.<region>.on.aws/ -> ホスト名だけを取り出す
  lambda_origin_domain = {
    for env in local.environments :
    env => replace(replace(aws_lambda_function_url.api[env].function_url, "https://", ""), "/", "")
  }

  # AWS マネージドポリシー ID
  cache_optimized_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  cache_disabled_id         = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
  origin_all_viewer_no_host = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader
}

resource "aws_cloudfront_distribution" "app" {
  for_each = local.environments

  enabled             = true
  comment             = "${local.name_prefix} ${each.key}"
  default_root_object = "index.html"
  price_class         = "PriceClass_200" # 日本を含むエッジのみ

  origin {
    origin_id                = "s3-frontend"
    domain_name              = aws_s3_bucket.frontend[each.key].bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  origin {
    origin_id   = "lambda-api"
    domain_name = local.lambda_origin_domain[each.key]

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = local.cache_optimized_id
  }

  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "lambda-api"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = local.cache_disabled_id
    # Host ヘッダを転送すると Function URL 側で署名不一致になるため除外する
    origin_request_policy_id = local.origin_all_viewer_no_host
  }

  # SPA ルーティング用 (S3 OAC は未知パスに 403 を返す)。
  # NOTE: ディストリビューション全体に効くため /api の 403 も index.html に
  # 置き換わる点はチュートリアル内で注意書きする。
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
