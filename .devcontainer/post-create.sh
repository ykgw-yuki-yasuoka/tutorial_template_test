#!/usr/bin/env bash
# devcontainer 作成後の初期化。再実行しても安全なように書くこと。
set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT=$(pwd)
SHELL_ENV="${REPO_ROOT}/.devcontainer/shell-env.sh"

# jq はベースイメージに含まれる。terraform / aws / gh / docker は feature 側。

# --------------------------------------------------------------------------
# 1) 空の AWS_* を取り除く設定を、シェルの全起動経路に仕込む
#
# これを uv sync / npm ci より先に行う。このスクリプトは set -e で走るので、
# ネットワーク都合で npm ci が落ちると以降が丸ごとスキップされる。認証が通らない
# 状態でコンテナが出来上がるのが一番困るため、壊れやすい処理より前に置く。
#
# 実体は shell-env.sh 1 つ。各起動経路からはそれを source するだけにする。
# 経路ごとに読まれるファイルが違うので、1 つ仕込むだけでは足りない。
#   対話 bash        -> ~/.bashrc            (VS Code のターミナル)
#   非対話 bash      -> $BASH_ENV            (bash -c / VS Code タスク / 自作スクリプト)
#   ログインシェル   -> /etc/profile.d/      (gh cs ssh / docker exec -l)
#   zsh (対話/非対話)-> ~/.zshenv            (ベースイメージ同梱の zsh に切り替えた場合)
#   リポジトリの script -> scripts/lib/preflight.sh が source する
#
# Ubuntu の ~/.bashrc は冒頭で「非対話シェルなら return」するため、~/.bashrc だけでは
# 対話シェルしか直らない。BASH_ENV は devcontainer.json の containerEnv で指している。
# --------------------------------------------------------------------------
echo "==> shell: 空の AWS_* 環境変数を取り除く設定を仕込む"

marker="# >>> devcontainer: strip empty AWS_* >>>"
snippet="${marker}
# 空の AWS_* を取り除く (詳細: .devcontainer/shell-env.sh, docs/00-setup.md)
[ -r \"${SHELL_ENV}\" ] && . \"${SHELL_ENV}\"
# <<< devcontainer: strip empty AWS_* <<<"

# ~/.bashrc (対話 bash) と ~/.zshenv (zsh は対話・非対話とも読む)。
# ファイルが無いベースイメージでも grep がエラーを吐かないよう stderr を捨てる
# (追記側がファイルを作るので、追記自体は問題なく動く)。
for rc in "${HOME}/.bashrc" "${HOME}/.zshenv"; do
  if ! grep -qF "${marker}" "${rc}" 2> /dev/null; then
    printf '\n%s\n' "${snippet}" >> "${rc}"
  fi
done

# ログインシェル。/etc は root 所有なので sudo で書く。
sudo tee /etc/profile.d/10-strip-empty-aws-env.sh > /dev/null <<EOF
${snippet}
EOF

# --------------------------------------------------------------------------
# 2) 依存関係
# --------------------------------------------------------------------------
if ! command -v uv > /dev/null 2>&1; then
  echo "==> install uv"
  # /usr/local/bin に入れて PATH の追加設定を不要にする
  curl -LsSf https://astral.sh/uv/install.sh \
    | sudo env UV_INSTALL_DIR=/usr/local/bin sh
fi

echo "==> backend: uv sync"
(cd backend && uv sync)

echo "==> frontend: npm ci"
(cd frontend && npm ci --no-audit --no-fund)

echo "==> done. docs/00-setup.md から始めてください"
