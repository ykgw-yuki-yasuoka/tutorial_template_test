#!/usr/bin/env bash
# 参加者ごとの最小権限ポリシーを IAM に登録/更新し、IAM ユーザーにアタッチする。
# 管理者権限のある認証情報で実行する。
#
# 何度実行しても同じ結果になる (冪等)。ポリシーが無ければ作り、あれば新しいバージョンを
# 既定に切り替える。「リポジトリを更新したら貼り直す」を正規の運用にするためで、これが
# 無いと、リソース名を変えたときに古いポリシーが残り続けて apply が AccessDenied になる。
# 実際、#25 で名前に owner が入ったとき、旧ポリシーの ECR は完全名 (owner 無し) を
# 許可していたため、リネームした瞬間に許可の外に出た (Issue #28)。
#
# 使い方:
#   ./scripts/apply-setup-policy.sh <owner> [--user <iam-user>] [--project <project_name>]
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/preflight.sh
source "${SCRIPT_DIR}/lib/preflight.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/naming.sh
source "${SCRIPT_DIR}/lib/naming.sh"
cd "${SCRIPT_DIR}/.."

require_cmd aws jq

usage() {
  cat >&2 <<'EOF'
使い方: ./scripts/apply-setup-policy.sh <owner> [--user <iam-user>] [--project <project_name>]

  owner       参加者の識別子。参加者の terraform.tfvars の owner と同じ値にすること
  --user      ポリシーをアタッチする IAM ユーザー名 (既定: owner と同じ)
  --project   project_name。terraform/variables.tf の既定値を上書きした場合だけ指定する

例:
  ./scripts/apply-setup-policy.sh alice
  ./scripts/apply-setup-policy.sh alice --user git-workflow-tutorial-alice
EOF
}

OWNER_ARG=${1:-}
if [[ -z ${OWNER_ARG} || ${OWNER_ARG} == -* ]]; then
  usage
  exit 1
fi
shift

IAM_USER=""
PROJECT_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      IAM_USER=${2:-}
      shift 2
      ;;
    --project)
      PROJECT_ARG=${2:-}
      shift 2
      ;;
    *)
      echo "ERROR: 不明な引数: $1" >&2
      usage
      exit 1
      ;;
  esac
done

resolve_naming "${OWNER_ARG}" ${PROJECT_ARG:+"${PROJECT_ARG}"}
IAM_USER=${IAM_USER:-${OWNER}}

POLICY_NAME="${PREFIX}-setup"
# #25 より前のポリシー。owner が無く、名前も内容も今とは別物。
LEGACY_POLICY_NAME="${PROJECT_NAME}-setup"

# 生成そのものは gen-setup-policy.sh に任せる (ポリシーの内容の定義元を 1 つに保つ)。
ERR_FILE=$(mktemp)
trap 'rm -f "${ERR_FILE}"' EXIT
if ! POLICY=$("${SCRIPT_DIR}/gen-setup-policy.sh" "${OWNER}" "${PROJECT_NAME}" 2> "${ERR_FILE}"); then
  cat "${ERR_FILE}" >&2
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

echo "==> owner       : ${OWNER}"
echo "==> IAM ユーザー: ${IAM_USER}"
echo "==> ポリシー    : ${POLICY_NAME}"
# 手で登録する運用でも「どの名前向けに作ったか」が分かるように出す。ここが参加者の
# terraform.tfvars の owner とズレると、プレフィックス付きの許可が全滅する (Issue #30)。
echo "==> 許可する名前: ${PREFIX}-*"

# 「ユーザーが無い」と「こちらに IAM の権限が無い」は直し方が全く違うので、混ぜない。
# 参加者の認証情報で実行してしまうのはありがちな間違いで、AccessDenied を
# 「ユーザーが見つかりません」と表示すると、存在するユーザーを探し回ることになる。
if ! GET_USER_ERR=$(aws iam get-user --user-name "${IAM_USER}" 2>&1 > /dev/null); then
  if grep -qE 'AccessDenied|not authorized' <<< "${GET_USER_ERR}"; then
    echo "ERROR: IAM を操作する権限がありません" >&2
    echo "       このスクリプトは管理者権限のある認証情報で実行してください" >&2
    echo "       (いまの認証情報: $(aws sts get-caller-identity --query Arn --output text))" >&2
  else
    echo "ERROR: IAM ユーザー '${IAM_USER}' が見つかりません" >&2
    echo "       先に作成するか、--user で実際のユーザー名を指定してください:" >&2
    echo "         aws iam create-user --user-name ${IAM_USER}" >&2
  fi
  exit 1
fi

# IAM のポリシーバージョンは 5 個までしか保持できない。上限に達していると
# create-policy-version が LimitExceeded で落ちるので、古い方から掃除する。
prune_policy_versions() {
  local count
  count=$(aws iam list-policy-versions --policy-arn "${POLICY_ARN}" \
    --query 'length(Versions)' --output text)
  while ((count >= 5)); do
    local oldest
    # Versions は新しい順。既定バージョンは消せないので除いた上での末尾 = 最古。
    oldest=$(aws iam list-policy-versions --policy-arn "${POLICY_ARN}" \
      --query 'Versions[?!IsDefaultVersion].VersionId' --output text | awk '{print $NF}')
    [[ -n ${oldest} ]] || break
    echo "==> 古いバージョンを削除: ${oldest}"
    aws iam delete-policy-version --policy-arn "${POLICY_ARN}" --version-id "${oldest}"
    count=$((count - 1))
  done
}

if aws iam get-policy --policy-arn "${POLICY_ARN}" > /dev/null 2>&1; then
  DEFAULT_VERSION=$(aws iam get-policy --policy-arn "${POLICY_ARN}" \
    --query 'Policy.DefaultVersionId' --output text)
  CURRENT=$(aws iam get-policy-version --policy-arn "${POLICY_ARN}" \
    --version-id "${DEFAULT_VERSION}" --query 'PolicyVersion.Document' --output json)

  # キー順と空白を揃えて比較する。同じ内容で新バージョンを作ると、意味もなく
  # 5 個の枠を食いつぶす。
  if [[ $(jq -cS . <<< "${CURRENT}") == $(jq -cS . <<< "${POLICY}") ]]; then
    echo "==> ポリシーは最新です (${DEFAULT_VERSION})"
  else
    prune_policy_versions
    NEW_VERSION=$(aws iam create-policy-version --policy-arn "${POLICY_ARN}" \
      --policy-document "${POLICY}" --set-as-default \
      --query 'PolicyVersion.VersionId' --output text)
    echo "==> ポリシーを更新しました (${DEFAULT_VERSION} -> ${NEW_VERSION})"
  fi
else
  aws iam create-policy --policy-name "${POLICY_NAME}" \
    --policy-document "${POLICY}" > /dev/null
  echo "==> ポリシーを作成しました (${POLICY_ARN})"
fi

# アタッチ済みでもエラーにはならない。
aws iam attach-user-policy --user-name "${IAM_USER}" --policy-arn "${POLICY_ARN}"
echo "==> ${IAM_USER} にアタッチしました"

# #25 以前のポリシーが残っていると、ECR の許可が旧名のままで紛らわしい。
# 他の参加者がまだ使っている可能性があるので、外すだけで削除はしない。
LEGACY_ARN=$(aws iam list-attached-user-policies --user-name "${IAM_USER}" \
  --query "AttachedPolicies[?PolicyName=='${LEGACY_POLICY_NAME}'].PolicyArn" --output text)
if [[ -n ${LEGACY_ARN} && ${LEGACY_ARN} != "None" ]]; then
  aws iam detach-user-policy --user-name "${IAM_USER}" --policy-arn "${LEGACY_ARN}"
  echo "==> 旧ポリシー '${LEGACY_POLICY_NAME}' をデタッチしました"
  echo "    (全員から外し終えたら 'aws iam delete-policy --policy-arn ${LEGACY_ARN}' で削除できます)"
fi

cat <<EOF

完了しました。参加者側で権限を確認できます:

  ./scripts/check-aws-permissions.sh ${OWNER}
EOF
