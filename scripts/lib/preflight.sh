#!/usr/bin/env bash
# 各スクリプトが source して使う前提チェック。単体では実行しない。
#
# 前提が満たされないまま進むと、依存ツールの生のエラーが処理の途中で出る。
# 何を直せばよいかが分かるメッセージを、副作用が起きる前に出すのが目的。

# devcontainer の remoteEnv が注入する「空の」AWS_* を取り除く。
# 実体は .devcontainer/shell-env.sh (理由と対象変数はそちらのコメントを参照)。
#
# devcontainer 側は BASH_ENV / ~/.bashrc / /etc/profile.d / ~/.zshenv からこれを読ませて
# いるが、スクリプトは devcontainer の外 (CI や素の shell) でも走りうる。そこでは
# BASH_ENV が設定されていないので、ここでも自分で読む。冪等なので二重に読んでも問題ない。
__PREFLIGHT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../../.devcontainer/shell-env.sh
source "${__PREFLIGHT_DIR}/../../.devcontainer/shell-env.sh"
unset __PREFLIGHT_DIR

# 必要なコマンドが PATH にあるか。足りないものをまとめて報告する。
require_cmd() {
  local missing=() cmd
  for cmd in "$@"; do
    command -v "${cmd}" > /dev/null 2>&1 || missing+=("${cmd}")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: 次のコマンドが見つかりません: ${missing[*]}" >&2
    echo "       docs/00-setup.md の前提ツールを確認してください" >&2
    return 1
  fi
}

# gh がログイン済みか (GH_TOKEN 等による認証も gh auth status が判定する)。
require_gh_auth() {
  if ! gh auth status > /dev/null 2>&1; then
    echo "ERROR: gh CLI が未ログインです" >&2
    echo "       'gh auth login' を実行してください" >&2
    return 1
  fi
}

# Docker daemon に接続できるか。docker build の直前に確認する。
require_docker_daemon() {
  if ! docker info > /dev/null 2>&1; then
    echo "ERROR: Docker daemon に接続できません" >&2
    echo "       Docker Desktop / dockerd が起動しているか確認してください" >&2
    return 1
  fi
}

# 指定した terraform 出力が取得できるか = 該当リソースが apply 済みか。
require_terraform_output() {
  local name="$1"
  if ! terraform -chdir=terraform output -raw "${name}" > /dev/null 2>&1; then
    echo "ERROR: terraform の出力 '${name}' を取得できません" >&2
    echo "       terraform apply は完了していますか?" >&2
    return 1
  fi
}
