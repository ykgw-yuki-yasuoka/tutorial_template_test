output "ecr_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "ecr_repository_name" {
  value = aws_ecr_repository.backend.name
}

output "aws_region" {
  value = var.aws_region
}

# 自分のリソースがどの名前で作られたか。終章の後片付け (ロググループの削除) で使う。
output "name_prefix" {
  value = local.name_prefix
}

# OIDC の信頼ポリシー (oidc.tf) に実際に焼き込まれたリポジトリ。
# scripts/sync-github-vars.sh が、実際のリポジトリと突き合わせて食い違いを検出する。
# var ではなく output から読ませるのは、「tfvars を直したが apply していない」状態も
# 捕まえたいため (信頼ポリシーに入っているのは apply 済みの値)。
output "github_repository" {
  value = var.github_repository
}

# scripts/sync-github-vars.sh がこの JSON 構造を読んで
# GitHub Environments の variables に流し込む
output "environments" {
  value = {
    for env in local.environments : env => {
      role_arn                   = aws_iam_role.deploy[env].arn
      lambda_function_name       = aws_lambda_function.api[env].function_name
      s3_bucket                  = aws_s3_bucket.frontend[env].bucket
      cloudfront_distribution_id = aws_cloudfront_distribution.app[env].id
      app_url                    = "https://${aws_cloudfront_distribution.app[env].domain_name}"
    }
  }
}
