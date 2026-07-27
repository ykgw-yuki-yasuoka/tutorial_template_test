#!/usr/bin/env bash
# GitHub 側の規約準拠設定 (マージ方式 / Environments / Rulesets) を一括適用する。
#
# 使い方:
#   ./scripts/setup-github.sh solo                # 一人で演習するモード
#   ./scripts/setup-github.sh pair <reviewer>     # ペア/研修モード (規約どおり承認1名)
#
# solo モードの緩和点 (本来の規約との差分):
#   - PR の必須承認数: 1 -> 0 (自分の PR は自己承認できないため)
#   - production Environment: 自分を必須レビュアーにし self-review を許可
# ペアモードでは規約どおりの設定になる。
#
# 前提 (実行時に検証する): gh CLI ログイン済み
#
# 対象リポジトリは既定でこのスクリプトを含むリポジトリ。GH_REPO で上書きできる。
# 非対話実行では確認プロンプトを省略する (SETUP_GITHUB_YES=1 でも省略可)。
# -E: ERR trap を関数内にも継承させる (apply_ruleset の失敗を捕捉するため)
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/preflight.sh
source "${SCRIPT_DIR}/lib/preflight.sh"
# gh repo view は cwd の git remote から対象を決めるため、呼び出し元の
# ディレクトリに引きずられないようリポジトリルートへ移動する。
cd "${SCRIPT_DIR}/.."

# 引数の検証は前提チェックより先に行う。引数なしで実行したときに
# 「gh が未ログイン」と出ると、直すべき箇所が分からない。
MODE="${1:?usage: setup-github.sh solo | pair <reviewer-login>}"
case "${MODE}" in
  solo)
    APPROVALS=0
    PREVENT_SELF_REVIEW=false
    ;;
  pair)
    APPROVALS=1
    REVIEWER_LOGIN="${2:?pair モードではレビュアーの GitHub ログイン名を指定してください}"
    PREVENT_SELF_REVIEW=true
    ;;
  *)
    echo "unknown mode: ${MODE}" >&2
    exit 1
    ;;
esac

require_cmd gh
require_gh_auth

# solo は自分自身をレビュアーにする。gh 認証後でないと引けないため、
# モード判定とは別に、前提チェックを通してから解決する。
if [[ "${MODE}" == solo ]]; then
  REVIEWER_LOGIN=$(gh api user -q .login)
fi

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# 文字列を JSON 文字列リテラルにする。GitHub のジョブ名には空白や記号を
# 使えるため、値をそのまま JSON へ埋め込まない。
json_string() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "${s}"
}

# main / release/* の Ruleset が要求する必須ステータスチェック。
# .github/workflows/ci.yml のジョブ名と一致させること。ここが唯一の定義元。
STATUS_CHECK_CONTEXTS=(pr-title frontend backend shellcheck)

# 空のまま Ruleset を作ると「CI なしでマージできる main」になる。
# printf は引数 0 個でも %s を 1 回展開するため、ここで弾かないと
# [{ "context": "" }] という要求不能なチェックが黙って適用される。
if [[ ${#STATUS_CHECK_CONTEXTS[@]} -eq 0 ]]; then
  echo "ERROR: STATUS_CHECK_CONTEXTS が空です" >&2
  exit 1
fi

# ("a" "b") -> [{ "context": "a" }, { "context": "b" }]
STATUS_CHECK_ITEMS=()
for CONTEXT in "${STATUS_CHECK_CONTEXTS[@]}"; do
  STATUS_CHECK_ITEMS+=("{ \"context\": $(json_string "${CONTEXT}") }")
done
STATUS_CHECKS_JSON=$(IFS=,; printf '[%s]' "${STATUS_CHECK_ITEMS[*]}")

REVIEWER_ID=$(gh api "users/${REVIEWER_LOGIN}" -q .id)

# 途中で落ちたときに、設定が中途半端な状態であることを利用者へ伝える。
trap 'echo "ERROR: 設定の適用が中断されました。保護が不完全な可能性があります。再実行してください" >&2' ERR

# 対象を取り違えていないか事前に確認させる。
echo "対象リポジトリ: ${REPO} (mode=${MODE}, reviewer=${REVIEWER_LOGIN})"
if [[ -t 0 && "${SETUP_GITHUB_YES:-}" != "1" ]]; then
  read -rp "この内容で適用しますか? [y/N] " ANSWER
  [[ "${ANSWER}" == [yY] ]] || { echo "中止しました" >&2; exit 1; }
fi

echo "==> [1/4] マージ方式: squash merge のみ・タイトル=PRタイトル"
gh api -X PATCH "repos/${REPO}" \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F allow_squash_merge=true \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=PR_BODY \
  -F delete_branch_on_merge=true > /dev/null

echo "==> [2/4] Environments: dev / staging / production"
gh api -X PUT "repos/${REPO}/environments/dev" > /dev/null
gh api -X PUT "repos/${REPO}/environments/staging" > /dev/null
# production のみ必須レビュアー承認を要求 (GA デプロイの承認ゲート)
gh api -X PUT "repos/${REPO}/environments/production" \
  --input - > /dev/null <<EOF
{
  "prevent_self_review": ${PREVENT_SELF_REVIEW},
  "reviewers": [{ "type": "User", "id": ${REVIEWER_ID} }]
}
EOF

echo "==> [3/4] ラベル: PR タイトルのプレフィックスに対応するラベルを用意"

# .github/workflows/pr-label.yml が PR タイトルのプレフィックスから付けるラベル。
# 存在しないラベルは付けられないため、ここで先に作っておく。
# ラベル名は pr-label.yml と .github/release.yml (ノートのカテゴリ定義) の
# 3 か所で揃えること。
#
# 名前は Conventional Commits の type と 1:1 の "type: <type>"。GitHub 既定の
# enhancement / bug は流用しない。名前が規約の type と一致していれば、
# PR タイトル -> ラベル -> リリースノートのカテゴリが変換表なしで追える。
#
# "<name>|<color>|<description>" の形。--force で既存ラベルは色と説明を上書き
# するため、何度実行しても同じ状態に収束する (冪等)。
PREFIX_LABELS=(
  "type: feat|a2eeef|新機能 (リリースノート: 🚀 Features)"
  "type: fix|d73a4a|バグ修正 (リリースノート: 🐛 Bug Fixes)"
  "type: docs|0075ca|ドキュメントのみの変更"
  "type: refactor|c5def5|挙動を変えない内部改善"
  "type: perf|fbca04|パフォーマンス改善"
  "type: test|d4c5f9|テストの追加・修正"
  "type: build|e4e669|ビルド設定・依存関係の変更"
  "type: ci|bfd4f2|CI/CD の設定変更"
  "type: chore|fef2c0|その他の雑務"
  "type: revert|b60205|変更の巻き戻し"
)

for LABEL_SPEC in "${PREFIX_LABELS[@]}"; do
  IFS='|' read -r LABEL_NAME LABEL_COLOR LABEL_DESC <<< "${LABEL_SPEC}"
  gh label create "${LABEL_NAME}" \
    --repo "${REPO}" \
    --color "${LABEL_COLOR}" \
    --description "${LABEL_DESC}" \
    --force > /dev/null
  echo "    ${LABEL_NAME}"
done

echo "==> [4/4] Rulesets を適用"

# 適用対象。ここに無い tutorial-* は古い世代とみなし、適用後に削除する。
RULESET_NAMES=(
  tutorial-protect-main
  tutorial-protect-release-branches
  tutorial-protect-release-tags
)

# "<id>\t<name>" の一覧。同名 Ruleset があれば作成ではなく更新する。
# Ruleset 名には空白を含められるため、区切りはタブ。--paginate が無いと
# 既定の 1 ページ分しか見えず、既存を見落として重複作成しうる。
EXISTING_RULESETS=$(gh api "repos/${REPO}/rulesets" --paginate -q '.[] | [.id, .name] | @tsv')

ruleset_id() {
  awk -F'\t' -v name="$1" '$2 == name { print $1; exit }' <<< "${EXISTING_RULESETS}"
}

# 同名があれば PUT で上書き、無ければ POST で作成する。
# 「削除してから作成」にすると失敗時に main が無保護のまま残るため、
# 保護が外れる瞬間を作らない。
apply_ruleset() {
  local name="$1" body="$2" id
  id=$(ruleset_id "${name}")
  if [[ -n "${id}" ]]; then
    gh api -X PUT "repos/${REPO}/rulesets/${id}" --input - > /dev/null <<< "${body}"
    echo "    ${name} (updated)"
  else
    gh api -X POST "repos/${REPO}/rulesets" --input - > /dev/null <<< "${body}"
    echo "    ${name} (created)"
  fi
}

# main と release/* に同一の保護をかける。ブランチ条件だけが異なる。
# ref は素の文字列で受け取り、JSON 化はこの関数が担う。呼び出し側に
# クォートを任せると、付け忘れが不正な JSON になって初めて分かる。
#
# required_status_checks の do_not_enforce_on_create: true は「ブランチの新規作成」
# だけをチェック必須の対象から外す。新しく切った release/* の先端コミットには
# チェック結果がまだ無く、GitHub はこれを「必須チェックが未達」とみなすため、
# これが無いと release ブランチを push した瞬間に GH013 で拒否され、
# そもそもリリースブランチを作れない。作成後の push には従来どおり
# チェックが要求されるので、保護は緩まない。
branch_ruleset_body() {
  local name="$1" ref="$2"
  cat <<EOF
{
  "name": "${name}",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": [$(json_string "${ref}")], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": ${APPROVALS},
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["squash"]
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": true,
        "required_status_checks": ${STATUS_CHECKS_JSON}
      }
    }
  ]
}
EOF
}

# PR 必須 + squash のみ + 必須ステータスチェック + 削除/force push 禁止
apply_ruleset "tutorial-protect-main" \
  "$(branch_ruleset_body "tutorial-protect-main" "~DEFAULT_BRANCH")"
# release/*: main と同等の保護 (バックポートも PR 経由を強制)
apply_ruleset "tutorial-protect-release-branches" \
  "$(branch_ruleset_body "tutorial-protect-release-branches" "refs/heads/release/**")"

# v* タグ: 公開済みタグの削除・付け替えを禁止
apply_ruleset "tutorial-protect-release-tags" "$(cat <<EOF
{
  "name": "tutorial-protect-release-tags",
  "target": "tag",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "update" }
  ]
}
EOF
)"

is_wanted_ruleset() {
  local name="$1" keep
  for keep in "${RULESET_NAMES[@]}"; do
    [[ "${name}" == "${keep}" ]] && return 0
  done
  return 1
}

# 旧世代の tutorial-* が残っていれば削除する。適用の「後」に行うため、
# 保護が外れる時間帯は生じない。
while IFS=$'\t' read -r ID NAME; do
  [[ -n "${NAME}" ]] || continue
  [[ "${NAME}" == tutorial-* ]] || continue
  if ! is_wanted_ruleset "${NAME}"; then
    gh api -X DELETE "repos/${REPO}/rulesets/${ID}" > /dev/null
    echo "    ${NAME} (deleted: 旧世代)"
  fi
done <<< "${EXISTING_RULESETS}"

# 期待した Ruleset が実際に存在するか、API を読み直して検証する。
# 同名が複数あると保護が二重にかかったまま気付けないため、"1 件以上" ではなく
# "ちょうど 1 件" を確認する。
APPLIED=$(gh api "repos/${REPO}/rulesets" --paginate -q '.[].name')
for NAME in "${RULESET_NAMES[@]}"; do
  COUNT=$(grep -cxF "${NAME}" <<< "${APPLIED}" || true)
  if [[ "${COUNT}" -ne 1 ]]; then
    echo "ERROR: Ruleset '${NAME}' が ${COUNT} 件あります (期待: 1 件)" >&2
    echo "       GitHub の Settings > Rules から重複を確認してください" >&2
    exit 1
  fi
done

echo ""
echo "完了 (mode=${MODE}, repo=${REPO})"
echo "次: ./scripts/sync-github-vars.sh で Terraform の出力を GitHub variables へ同期"
