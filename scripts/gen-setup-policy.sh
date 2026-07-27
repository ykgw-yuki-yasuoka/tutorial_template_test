#!/usr/bin/env bash
# 参加者ごとの最小権限ポリシー (IAM ポリシー JSON) を生成し、標準出力に書く。
#
# 1 つの AWS アカウントを複数人で共有して演習するとき、参加者ごとに owner を変えて
# 実行すれば、「自分のリソースにしか触れない」IAM ユーザー用のポリシーが手に入る。
# 許可範囲を絞る手掛かりは 2 つ:
#   - リソース名のプレフィックス <project_name>-<owner>-  (ECR / S3 / Lambda / IAM / Logs)
#   - Owner タグ                                          (CloudFront の変更・削除。名前で絞れないため。
#                                                          参照はタグでも絞れず、全体に開いている)
# どちらも terraform 側 (local.name_prefix と provider の default_tags) と対になっている。
#
# 生成するだけで、IAM への登録はしない。登録・更新・アタッチまで面倒を見るのは
# apply-setup-policy.sh (こちらを内部で呼ぶ)。
#
# 使い方:
#   ./scripts/gen-setup-policy.sh <owner> [project_name] > setup-policy.json
#
# 絞りきれない箇所については docs/00-setup.md の「必要な権限」を参照。
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/preflight.sh
source "${SCRIPT_DIR}/lib/preflight.sh"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/naming.sh
source "${SCRIPT_DIR}/lib/naming.sh"
cd "${SCRIPT_DIR}/.."

require_cmd jq

TEMPLATE="docs/assets/setup-policy.template.json"

usage() {
  cat >&2 <<'EOF'
使い方: ./scripts/gen-setup-policy.sh <owner> [project_name]

  owner        リソースの所有者を表す識別子。terraform.tfvars の owner と同じ値にすること
               (英小文字・数字・ハイフン、13 文字以内)
  project_name 省略時は terraform/variables.tf の既定値。
               terraform.tfvars で project_name を上書きした場合だけ、その値を渡す

例:
  ./scripts/gen-setup-policy.sh alice > /tmp/setup-policy-alice.json
EOF
}

if [[ -z ${1:-} ]]; then
  usage
  exit 1
fi

resolve_naming "$@"

if [[ ! -f ${TEMPLATE} ]]; then
  echo "ERROR: テンプレートが見つかりません: ${TEMPLATE}" >&2
  exit 1
fi

# _comment はテンプレートの読み手向け。IAM は不明なトップレベルキーを拒否するため落とす。
# owner / project_name は resolve_naming が書式検証済みなので、sed を壊す文字は入らない。
POLICY=$(
  sed -e "s/__PREFIX__/${PREFIX}/g" -e "s/__OWNER__/${OWNER}/g" "${TEMPLATE}" \
    | jq 'del(._comment)'
)

# 置換漏れ = テンプレートに新しいプレースホルダが増えたのに、こちらが追随していない。
# 気付かずに登録すると、リテラル "__FOO__" という名前にしか許可が出ないポリシーになる。
if grep -q '__[A-Z_]\+__' <<< "${POLICY}"; then
  echo "ERROR: 置換されなかったプレースホルダが残っています:" >&2
  grep -o '__[A-Z_]\+__' <<< "${POLICY}" | sort -u >&2
  exit 1
fi

printf '%s\n' "${POLICY}"

cat >&2 <<EOF

生成しました (owner=${OWNER}, リソース名のプレフィックス=${PREFIX}-)
このポリシーで作成・変更・削除できるのは ${PREFIX}-* という名前のリソースと、
Owner=${OWNER} タグの付いた CloudFront ディストリビューションだけです。
(CloudFront の参照はタグで絞れないため、他の参加者のディストリビューションも
 設定を読めてしまいます。変更・削除はできません。docs/00-setup.md の「絞りきれない箇所」参照)

IAM への登録とアタッチは、管理者権限のある認証情報で:

  ./scripts/apply-setup-policy.sh ${OWNER}

参加者側の terraform.tfvars には owner = "${OWNER}" を書いてください。
EOF
