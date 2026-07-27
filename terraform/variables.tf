variable "project_name" {
  description = "リソース名のプレフィックス"
  type        = string
  default     = "gitflow-tutorial"
}

# 1 つの AWS アカウントを複数人で共有して演習するための仕切り。
# リソース名は全て "<project_name>-<owner>-..." になり、全リソースに Owner タグが付く。
# 最小権限ポリシー (docs/assets/setup-policy.template.json) はこの名前とタグの 2 つで
# 許可範囲を絞るため、owner を変えれば「自分のリソースにしか触れない IAM ユーザー」になる。
#
# 一人で自分のアカウントを使う場合も設定は必要 (好きな識別子でよい)。
#
# 長さの上限 13 文字は S3 バケット名から逆算した値。バケット名はグローバル一意にするため
# アカウント ID を末尾に付けており、63 文字制限にほとんど余裕がない:
#   <project_name>-<owner>-production-frontend-<12 桁のアカウント ID> <= 63
# 既定の project_name (16 文字) だと owner に使えるのは 13 文字まで。
# project_name を変えた場合の実際の長さは s3.tf の precondition が plan 時に検査する。
variable "owner" {
  description = "リソースの所有者を表す識別子 (英小文字・数字・ハイフン、13 文字以内)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,11}[a-z0-9])?$", var.owner))
    error_message = "Owner は英小文字・数字・ハイフンのみ、1〜13 文字で指定してください (先頭と末尾にハイフンは使えません)."
  }
}

variable "aws_region" {
  description = "デプロイ先リージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "github_repository" {
  description = "OIDC 信頼対象の GitHub リポジトリ (owner/repo 形式)"
  type        = string
  # 例: "ykgw-daiki-nakamura/gitflow-tutorial-handson"
}

# GitHub の OIDC プロバイダは URL ごとに AWS アカウントで 1 つしか作れない、
# アカウント全体で共有されるリソース。プロジェクト単位のリソースとは寿命が違う。
#
# 既に他プロジェクトが作っているアカウントで true にすると apply が 409 で落ちる。
# さらに厄介なのは destroy 側で、うっかり管理下に置くと、このチュートリアルの
# 後片付けで他プロジェクトの OIDC 連携ごと消してしまう。
# そのため既定は false = 「既存を参照するだけ。作りも消しもしない」にしてある。
#
# 自分専用のまっさらな AWS アカウントで、まだプロバイダが無い場合だけ true にする。
# 複数人で 1 アカウントを共有する場合は、管理者が事前に 1 つだけ作り、参加者は全員 false のまま。
variable "create_oidc_provider" {
  description = "GitHub OIDC プロバイダを新規作成するか (false = 既存のものを参照する)"
  type        = bool
  default     = false
}
