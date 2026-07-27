# バックエンド API (コンテナイメージ Lambda + Function URL)。
# 初回 apply の前に scripts/bootstrap-image.sh で :bootstrap タグを
# push しておく必要がある (README のセットアップ手順を参照)。
resource "aws_iam_role" "lambda_exec" {
  name = "${local.name_prefix}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "api" {
  for_each = local.environments

  function_name = "${local.name_prefix}-${each.key}-api"
  role          = aws_iam_role.lambda_exec.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.backend.repository_url}:bootstrap"
  architectures = ["x86_64"] # GitHub ホステッドランナーでのビルドに合わせる
  timeout       = 10
  memory_size   = 256

  environment {
    variables = {
      APP_ENV = each.key
    }
  }

  # デプロイは GitHub Actions が担う。Terraform は初期状態のみ管理し、
  # 以後の image_uri / 環境変数の変更は無視する (デプロイと衝突させない)。
  lifecycle {
    ignore_changes = [image_uri, environment]
  }
}

# 同じ関数への AddPermission は同時に走らせられない (409
# ResourceConflictException になる)。この Function URL と下の permission 2 つは
# いずれも関数ポリシーを書き換える (authorization_type = "NONE" の Function URL は
# provider が FunctionURLAllowPublicAccess を自動で足す) ため、depends_on で
# 直列化している。外すと Terraform が並列に流し、apply が確率的に落ちる (#72)。
resource "aws_lambda_function_url" "api" {
  for_each = local.environments

  function_name      = aws_lambda_function.api[each.key].function_name
  authorization_type = "NONE" # チュートリアル用。CloudFront 経由アクセスが前提
}

resource "aws_lambda_permission" "function_url" {
  for_each = local.environments

  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.api[each.key].function_name
  principal              = "*"
  function_url_auth_type = "NONE"

  depends_on = [aws_lambda_function_url.api]
}

# 2025-10 以降に作られた Function URL は、上の InvokeFunctionUrl だけでは呼び出せない。
# InvokeFunction も明示的に許可しないと、authorization_type = "NONE" であっても
# 認可レイヤで 403 Forbidden になり、リクエストはアプリまで届かない。
#   https://docs.aws.amazon.com/lambda/latest/dg/urls-auth.html
#
# 仕様変更より前に作られた Function URL は影響を受けないため、既存環境では再現せず、
# 新しく作った環境だけが壊れる (#40)。
#
# invoked_via_function_url で Function URL 経由の呼び出しに限定する。外すと
# principal = "*" に対する無条件の InvokeFunction 許可になり、Lambda の API を
# 直接叩く経路まで開いてしまう。
resource "aws_lambda_permission" "function_url_invoke" {
  for_each = local.environments

  statement_id             = "AllowPublicFunctionUrlInvoke"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.api[each.key].function_name
  principal                = "*"
  invoked_via_function_url = true

  depends_on = [aws_lambda_permission.function_url]
}
