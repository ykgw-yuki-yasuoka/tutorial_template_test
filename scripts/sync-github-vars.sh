#!/usr/bin/env bash
# Terraform の出力を GitHub の variables に同期する。
# 対象の環境は terraform の environments 出力から導出する (local.environments が定義元)。
#
# 前提 (いずれも実行時に検証する):
#   - terraform apply 完了済み
#   - scripts/setup-github.sh 実行済み (Environments が存在すること)
#   - gh CLI ログイン済み、jq インストール済み
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/preflight.sh
source "${SCRIPT_DIR}/lib/preflight.sh"
cd "${SCRIPT_DIR}/.."

require_cmd gh jq terraform
require_gh_auth

# terraform 出力から必須の値を取り出す。
# jq -r は不在キーに対しても終了コード 0 のまま文字列 "null" を出力するため、
# 素直に書くと "null" という値が variables に書き込まれ、スクリプトは成功する。
# -e を付けて null / 不在を非ゼロ終了にし、この場で止める。
jq_required() {
  local filter="$1" json="$2" value
  if ! value=$(jq -er "${filter}" <<< "${json}"); then
    echo "ERROR: terraform の出力に ${filter} が見つかりません" >&2
    echo "       terraform apply は完了していますか?" >&2
    return 1
  fi
  printf '%s' "${value}"
}

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
OUTPUTS=$(terraform -chdir=terraform output -json)

# OIDC の信頼ポリシー (terraform/oidc.tf) は sub が
#   repo:<github_repository>:environment:<env>
# であることを StringEquals で要求する。一方 GitHub が発行する OIDC トークンの sub は
# リポジトリの正式表記をそのまま使う。ここが食い違うと、ロール ARN も IAM 権限も正しいのに
# GitHub Actions が
#   Not authorized to perform sts:AssumeRoleWithWebIdentity
# で落ちる。しかも落ちるのは terraform ではなく後続の Actions 実行時、つまり原因から
# 最も遠い場所なので、AWS の権限問題だと思い込んで時間を溶かす (Issue #42)。
# variables を 1 つも書き込む前に、ここで止める。
#
# 比較対象は terraform.tfvars ではなく terraform の出力から取る。信頼ポリシーに実際に
# 焼かれているのは apply 済みの値であり、「tfvars を直したが apply していない」も捕まる。
CONFIGURED_REPO=$(jq_required '.github_repository.value' "${OUTPUTS}")
if [[ ${CONFIGURED_REPO} != "${REPO}" ]]; then
  echo "ERROR: github_repository が実際のリポジトリと一致しません" >&2
  echo "       terraform に焼かれている値: ${CONFIGURED_REPO}" >&2
  echo "       実際のリポジトリ          : ${REPO}" >&2
  # 大文字小文字だけの違いは見た目で気付けない。名指ししないと直せない。
  if [[ ${CONFIGURED_REPO,,} == "${REPO,,}" ]]; then
    echo "" >&2
    echo "       違いは大文字小文字だけです。信頼ポリシーの sub 照合は大文字小文字を区別するので、" >&2
    echo "       これも不一致として扱われます。" >&2
  fi
  echo "" >&2
  echo "       このまま進めても、GitHub Actions が OIDC でロールを assume できず" >&2
  echo "       'Not authorized to perform sts:AssumeRoleWithWebIdentity' で落ちます。" >&2
  echo "       terraform/terraform.tfvars の github_repository を次の値に直し、" >&2
  echo "       terraform -chdir=terraform apply を実行してください:" >&2
  echo "         github_repository = \"${REPO}\"" >&2
  exit 1
fi

# 環境名は terraform の local.environments を唯一の定義元とし、
# その出力から導出する。ここで列挙すると terraform 側への追加が
# 無言で無視されるため。
ENV_NAMES=$(jq_required '.environments.value | keys[]' "${OUTPUTS}")
mapfile -t ENVIRONMENTS <<< "${ENV_NAMES}"

# gh variable set --env は Environment が無いと 404 で落ちる。
# 原因 (setup-github.sh 未実行) が分かるよう、1 件も書き込む前に確認する。
EXISTING_ENVS=$(gh api "repos/${REPO}/environments" -q '.environments[].name')
for ENV_NAME in "${ENVIRONMENTS[@]}"; do
  if ! grep -qxF "${ENV_NAME}" <<< "${EXISTING_ENVS}"; then
    echo "ERROR: GitHub Environment '${ENV_NAME}' がありません" >&2
    echo "       先に ./scripts/setup-github.sh を実行してください" >&2
    exit 1
  fi
done

# 値は必ず変数へ代入してから渡すこと。
# gh variable set --body "$(jq_required ...)" と書くと、引数内のコマンド置換の
# 失敗は set -e で捕捉されず、空文字が書き込まれたまま成功してしまう。
echo "==> リポジトリ変数 (${REPO})"
AWS_REGION=$(jq_required '.aws_region.value' "${OUTPUTS}")
ECR_REPOSITORY=$(jq_required '.ecr_repository_name.value' "${OUTPUTS}")
gh variable set AWS_REGION --body "${AWS_REGION}"
gh variable set ECR_REPOSITORY --body "${ECR_REPOSITORY}"

for ENV_NAME in "${ENVIRONMENTS[@]}"; do
  echo "==> environment: ${ENV_NAME}"
  E=$(jq_required ".environments.value.\"${ENV_NAME}\"" "${OUTPUTS}")

  AWS_ROLE_ARN=$(jq_required '.role_arn' "${E}")
  LAMBDA_FUNCTION_NAME=$(jq_required '.lambda_function_name' "${E}")
  S3_BUCKET=$(jq_required '.s3_bucket' "${E}")
  CLOUDFRONT_DISTRIBUTION_ID=$(jq_required '.cloudfront_distribution_id' "${E}")
  APP_URL=$(jq_required '.app_url' "${E}")

  gh variable set AWS_ROLE_ARN --env "${ENV_NAME}" --body "${AWS_ROLE_ARN}"
  gh variable set LAMBDA_FUNCTION_NAME --env "${ENV_NAME}" --body "${LAMBDA_FUNCTION_NAME}"
  gh variable set S3_BUCKET --env "${ENV_NAME}" --body "${S3_BUCKET}"
  gh variable set CLOUDFRONT_DISTRIBUTION_ID --env "${ENV_NAME}" --body "${CLOUDFRONT_DISTRIBUTION_ID}"
  gh variable set APP_URL --env "${ENV_NAME}" --body "${APP_URL}"
done

echo ""
echo "完了。各環境の URL:"
jq -er '.environments.value | to_entries[] | "  \(.key): \(.value.app_url)"' <<< "${OUTPUTS}"
