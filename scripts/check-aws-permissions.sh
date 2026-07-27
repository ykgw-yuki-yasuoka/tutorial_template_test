#!/usr/bin/env bash
# terraform apply の前に、いまの AWS 認証情報で必要な権限があるかを確かめる。
# 何も作らない (読み取り専用)。
#
# 権限が足りないことに apply の途中で気付くと、生の AccessDenied が出るだけで
# 何を直せばいいのか分からない。ポリシーが古いだけ、というのが実際に起きている
# (Issue #28: リソース名に owner が入った際、旧ポリシーの ECR 許可が外れた)。
# ポリシーが別の owner 向けに作られていた、というのも起きている (Issue #30)。
#
# 判定のからくり: AWS は「リソースが在るか」より先に「認可されているか」を評価する。
# そのため存在しないリソースを指定して叩けば、
#   AccessDenied         -> 権限が無い
#   NotFound などの別エラー -> 権限はある (まだ作っていないだけ)
# と切り分けられる。
#
# 使い方:
#   ./scripts/check-aws-permissions.sh [owner]     # 省略時は terraform.tfvars の owner
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/preflight.sh
source "${SCRIPT_DIR}/lib/preflight.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/naming.sh
source "${SCRIPT_DIR}/lib/naming.sh"
cd "${SCRIPT_DIR}/.."

require_cmd aws

OWNER_ARG=${1:-$(naming_owner_from_tfvars)}
if [[ -z ${OWNER_ARG} ]]; then
  echo "ERROR: owner が分かりません" >&2
  echo "       terraform/terraform.tfvars に owner を書くか、引数で渡してください:" >&2
  echo "         ./scripts/check-aws-permissions.sh <owner>" >&2
  exit 1
fi
resolve_naming "${OWNER_ARG}"

if ! CALLER=$(aws sts get-caller-identity --query 'Arn' --output text 2>&1); then
  echo "ERROR: AWS の認証情報が使えません" >&2
  echo "       docs/00-setup.md の 0.1 (AWS 認証情報) を確認してください" >&2
  printf '%s\n' "${CALLER}" >&2
  exit 1
fi
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

echo "認証情報 : ${CALLER}"
echo "owner    : ${OWNER}"
echo "リソース名: ${PREFIX}-*"
echo

DENIED=()
# 失敗の「形」で原因を切り分けるため、プレフィックスで絞られた許可 (prefix) と、
# Resource: "*" などプレフィックスに依らない許可 (any) を分けて数える。
PREFIX_TOTAL=0
PREFIX_DENIED=0
ANY_OK=0

# 存在しないリソースを 1 つ叩いて、AccessDenied かどうかだけを見る。
#   check <prefix|any> <label> <action> <コマンド...>
check() {
  local scope=$1 label=$2 action=$3
  shift 3
  local out denied=0
  [[ ${scope} == prefix ]] && PREFIX_TOTAL=$((PREFIX_TOTAL + 1))

  printf '  %-32s ' "${action}"
  if out=$("$@" 2>&1); then
    echo "OK"
  elif grep -qE 'AccessDenied|not authorized' <<< "${out}"; then
    echo "権限なし"
    denied=1
    DENIED+=("${action} (${label})")
  else
    # NotFound / NoSuchEntity など。認可は通っている。
    echo "OK"
  fi

  if [[ ${scope} == prefix ]]; then
    ((denied)) && PREFIX_DENIED=$((PREFIX_DENIED + 1))
  elif ((denied == 0)); then
    ANY_OK=$((ANY_OK + 1))
  fi
  return 0
}

check any "ECR への docker push" \
  "ecr:GetAuthorizationToken" aws ecr get-authorization-token
check prefix "ECR リポジトリ ${PREFIX}-backend の作成" \
  "ecr:DescribeRepositories" aws ecr describe-repositories --repository-names "${PREFIX}-backend"
check prefix "Lambda 関数の作成" \
  "lambda:GetFunction" aws lambda get-function --function-name "${PREFIX}-dev-api"
check prefix "Lambda 実行ロールの作成" \
  "iam:GetRole" aws iam get-role --role-name "${PREFIX}-lambda-exec"
check any "GitHub OIDC 連携" \
  "iam:GetOpenIDConnectProvider" aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn \
  "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
check any "CloudFront ディストリビューションの作成" \
  "cloudfront:ListDistributions" aws cloudfront list-distributions
# 終章の destroy まで表面化しないのを、ここで先に捕まえる (Issue #54)。
# 参照を Owner タグで絞った古いポリシーだと、destroy が CloudFront の削除待ちで落ちる。
# Terraform は DeleteDistribution の後、GetDistribution が NotFound を返すまで待つが、
# 消えた瞬間にタグも消えるため、条件付きだと NotFound の代わりに AccessDenied が返るため。
# 存在しない ID にもタグは無いので、ここで叩けば同じ形で古いポリシーを炙り出せる。
check any "終章での CloudFront の削除" \
  "cloudfront:GetDistribution" aws cloudfront get-distribution --id E000000000000
check any "終章での後片付け" \
  "logs:DescribeLogGroups" aws logs describe-log-groups

echo

# S3 と CloudFront の作成系は読み取りだけでは確かめられない。S3 は存在しないバケットに
# 対して権限の有無によらず NoSuchBucket を返すし、cloudfront:CreateDistribution は
# タグ条件つきなので実際に作るまで分からない。ここで OK でも apply が落ちる余地は残る。
if ((${#DENIED[@]} == 0)); then
  echo "必要な権限は揃っています。docs/00-setup.md の 0.2 へ進んでください。"
  exit 0
fi

echo "ERROR: 次の権限が足りません" >&2
printf '  - %s\n' "${DENIED[@]}" >&2
echo >&2

# プレフィックス付きの許可が 1 つ残らず落ち、プレフィックスに依らない許可は通っている。
# 「権限が無い」のではなく「ポリシーが別の名前向けに作られている」形。正しいポリシーを
# 何度貼り直しても直らないので、ここを取り違えると延々と迷う (Issue #30)。
if ((PREFIX_TOTAL > 0 && PREFIX_DENIED == PREFIX_TOTAL && ANY_OK > 0)); then
  cat >&2 <<EOF
ポリシーは付いていますが、別の名前のリソース向けに作られています。
プレフィックスで絞った許可だけが全滅し、Resource: "*" の許可は通っているのが、その印です。

  このリポジトリが作るリソース : ${PREFIX}-*
  ポリシーが許可している名前   : これとは別のもの

owner か project_name の食い違いです。よくあるのは、ポリシーを作ったときの owner が
terraform.tfvars の owner と違うこと。管理者に、この owner で作り直すよう依頼してください。

  ./scripts/apply-setup-policy.sh ${OWNER}

IAM ユーザー名が owner と違う場合は --user も要ります。

  ./scripts/apply-setup-policy.sh ${OWNER} --user <IAM ユーザー名>
EOF
else
  cat >&2 <<EOF
ポリシーが古い可能性があります (リソース名の付け方が変わると、古いポリシーの許可は
名前が変わったリソースに届かなくなります)。管理者に、リポジトリを最新にした上で
次の再実行を依頼してください。

  ./scripts/apply-setup-policy.sh ${OWNER}
EOF
fi

cat >&2 <<'EOF'

自分の AWS アカウントで一人で演習しているなら、上を自分で実行してください。
EOF
exit 1

