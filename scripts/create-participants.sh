#!/usr/bin/env bash
# 参加者 (owner=userN, IAM ユーザー=git-workflow-tutorial-userN) を連番でまとめて作る。
# 管理者ガイド (docs/90-admin.md) の「参加者ごとに IAM ユーザーとポリシーを作る」を
# 範囲指定で一括実行するもの。管理者権限のある認証情報で、リポジトリの中で実行する。
#
# 各 N について次を順に行う (すべて冪等):
#   1. aws iam create-user   … 既にあれば飛ばす
#   2. apply-setup-policy.sh … 最小権限ポリシーの生成・登録・アタッチ
#   3. aws iam create-access-key … アクセスキーが 1 つも無いときだけ発行し、CSV に保存
#
# 使い方:
#   ./scripts/create-participants.sh            # 既定で 1〜15
#   ./scripts/create-participants.sh 1 15       # 開始 終了 を指定
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "${SCRIPT_DIR}/.."

START=${1:-1}
END=${2:-15}

if ! [[ ${START} =~ ^[0-9]+$ && ${END} =~ ^[0-9]+$ ]] || ((START > END)); then
  echo "使い方: ./scripts/create-participants.sh [開始番号] [終了番号] (既定: 1 15)" >&2
  exit 1
fi

command -v aws > /dev/null || { echo "ERROR: aws CLI が必要です" >&2; exit 1; }
command -v jq  > /dev/null || { echo "ERROR: jq が必要です" >&2; exit 1; }

# 管理者権限で動いているかの目安。IAM ユーザーの認証情報だと create-user で落ちる。
CALLER=$(aws sts get-caller-identity --query Arn --output text)
echo "==> 実行中の認証情報: ${CALLER}"
echo "==> 作成範囲: user${START} 〜 user${END}"
echo

# アクセスキーは秘密情報。リポジトリに入らない場所 (gitignore 済み) にだけ書く。
# ファイル名に日時を入れたいところだが、再実行時に取り違えないよう固定名で追記する。
CRED_DIR="credentials"
mkdir -p "${CRED_DIR}"
CRED_FILE="${CRED_DIR}/participant-access-keys.csv"
if [[ ! -f ${CRED_FILE} ]]; then
  echo "owner,iam_user,access_key_id,secret_access_key" > "${CRED_FILE}"
  chmod 600 "${CRED_FILE}"
fi

created_users=0
new_keys=0

for ((N = START; N <= END; N++)); do
  OWNER="user${N}"
  IAM_USER="git-workflow-tutorial-user${N}"
  echo "==================== ${OWNER} (${IAM_USER}) ===================="

  # 1. IAM ユーザー。既にあれば作らない (冪等)。
  if aws iam get-user --user-name "${IAM_USER}" > /dev/null 2>&1; then
    echo "==> ユーザーは既に存在します"
  else
    aws iam create-user --user-name "${IAM_USER}" > /dev/null
    echo "==> ユーザーを作成しました"
    created_users=$((created_users + 1))
  fi

  # 2. 最小権限ポリシーの登録とアタッチ。owner と IAM ユーザー名は別物なので --user で渡す。
  ./scripts/apply-setup-policy.sh "${OWNER}" --user "${IAM_USER}"

  # 3. アクセスキー。IAM は 1 ユーザー 2 個までなので、再実行で増やさないよう
  #    「1 つも無いとき」だけ発行する。既にあれば手を触れない。
  KEY_COUNT=$(aws iam list-access-keys --user-name "${IAM_USER}" \
    --query 'length(AccessKeyMetadata)' --output text)
  if ((KEY_COUNT == 0)); then
    KEY_JSON=$(aws iam create-access-key --user-name "${IAM_USER}")
    AKID=$(jq -r '.AccessKey.AccessKeyId'     <<< "${KEY_JSON}")
    SECRET=$(jq -r '.AccessKey.SecretAccessKey' <<< "${KEY_JSON}")
    printf '%s,%s,%s,%s\n' "${OWNER}" "${IAM_USER}" "${AKID}" "${SECRET}" >> "${CRED_FILE}"
    echo "==> アクセスキーを発行しました (${AKID}) → ${CRED_FILE}"
    new_keys=$((new_keys + 1))
  else
    echo "==> アクセスキーは既にあります (${KEY_COUNT} 個)。新規発行はしません"
  fi
  echo
done

cat <<EOF
==================== 完了 ====================
新規ユーザー   : ${created_users}
新規アクセスキー: ${new_keys}
認証情報       : ${CRED_FILE}

参加者に渡すのは owner (userN) と、CSV の access_key_id / secret_access_key、
それに AWS_REGION (例: ap-northeast-1) です。CSV は渡し終えたら削除してください。
シークレットキーはこのタイミングでしか取得できません。
EOF
