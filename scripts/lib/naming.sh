#!/usr/bin/env bash
# owner / project_name / リソース名プレフィックスの解決と検証。source して使う。単体では実行しない。
#
# terraform の local.name_prefix ("${project_name}-${owner}") と対になる。ここがズレると
# 「ポリシーは A という名前を許可、実際のリソースは B」で AccessDenied になるため、
# ポリシーを作る側 (gen-setup-policy.sh / apply-setup-policy.sh) と、権限を確かめる側
# (check-aws-permissions.sh) で同じ 1 つの実装を使う。
#
# 呼び出す前にリポジトリルートへ cd しておくこと (terraform/ を相対で読む)。

NAMING_VARIABLES_TF="terraform/variables.tf"
NAMING_TFVARS="terraform/terraform.tfvars"

# terraform.tfvars から変数を 1 つ拾う。terraform が実際に使う値をここでも使うため。
naming_from_tfvars() {
  local key="$1"
  [[ -f ${NAMING_TFVARS} ]] || return 0
  awk -F'=' -v key="${key}" '$1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
    gsub(/[[:space:]"]/, "", $2); print $2; exit
  }' "${NAMING_TFVARS}"
}

naming_owner_from_tfvars() {
  naming_from_tfvars owner
}

# project_name は terraform.tfvars > variables.tf の既定値、の順で決める。terraform 自身と
# 同じ優先順位にすること。tfvars の上書きを見落とすと、terraform が作るリソース名と
# こちらが組み立てる名前がズレて、正しいポリシーでも AccessDenied に見える (Issue #30)。
naming_default_project_name() {
  local from_tfvars
  from_tfvars=$(naming_from_tfvars project_name)
  if [[ -n ${from_tfvars} ]]; then
    printf '%s\n' "${from_tfvars}"
    return 0
  fi
  # 既定値の定義元は terraform/variables.tf ただ 1 つ。ここに独自の既定値を書くと、
  # terraform 側を変えたときに黙ってズレる。
  awk '
    /^variable "project_name"/ { in_block = 1; next }
    in_block && $1 == "default" { gsub(/"/, "", $3); print $3; exit }
    in_block && /^}/            { exit }
  ' "${NAMING_VARIABLES_TF}"
}

# owner / project_name を検証し、OWNER / PROJECT_NAME / PREFIX を設定する。
#   resolve_naming <owner> [project_name]
resolve_naming() {
  OWNER=${1:-}
  if [[ -z ${OWNER} ]]; then
    echo "ERROR: owner が指定されていません" >&2
    return 1
  fi

  # terraform 側の variable "owner" の validation と同じ規則。ここで弾いておかないと、
  # ポリシーだけ先に作れて apply で初めて落ちる。
  if ! [[ ${OWNER} =~ ^[a-z0-9]([a-z0-9-]{0,11}[a-z0-9])?$ ]]; then
    echo "ERROR: owner が不正です: '${OWNER}'" >&2
    echo "       英小文字・数字・ハイフンのみ、1〜13 文字 (先頭と末尾はハイフン不可)" >&2
    return 1
  fi

  PROJECT_NAME=${2:-$(naming_default_project_name)}
  if [[ -z ${PROJECT_NAME} ]]; then
    echo "ERROR: ${NAMING_VARIABLES_TF} から project_name の既定値を読み取れません" >&2
    echo "       第 2 引数で明示してください" >&2
    return 1
  fi

  # owner と同じ文字種に制限する。ECR / S3 / Lambda の名前に入る以上どのみち必要な制約だが、
  # gen-setup-policy.sh の sed の安全性も兼ねている: '/' は区切り文字と衝突し、'&' は
  # 置換先で「マッチ全体」に化けるため、素通しにすると黙って壊れたポリシーが出来上がる。
  if ! [[ ${PROJECT_NAME} =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
    echo "ERROR: project_name が不正です: '${PROJECT_NAME}'" >&2
    echo "       英小文字・数字・ハイフンのみ (先頭と末尾はハイフン不可)" >&2
    return 1
  fi

  PREFIX="${PROJECT_NAME}-${OWNER}"

  # S3 バケット名 (63 文字) が最も厳しい制約。terraform の s3.tf も同じ検査をするが、
  # あちらは apply 時。ポリシーを配る前に気付けるよう、ここでも見る。
  # 末尾はグローバル一意化のためのアカウント ID 12 桁。
  local bucket_suffix="-production-frontend-" # 環境名は production が最長
  local longest=$(( ${#PREFIX} + ${#bucket_suffix} + 12 ))
  if (( longest > 63 )); then
    echo "ERROR: S3 バケット名が ${longest} 文字になり、63 文字を超えます" >&2
    echo "       ('${PREFIX}-production-frontend-<アカウントID>')" >&2
    echo "       owner か project_name を短くしてください" >&2
    return 1
  fi
}
