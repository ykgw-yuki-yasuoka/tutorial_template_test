# shellcheck shell=bash
# 空の AWS_* 環境変数を取り除く。source して使う (実行はしない)。
#
# devcontainer.json の remoteEnv はホストの値をコンテナへ引き渡すが、ホスト側で未設定の
# ${localEnv:X} は「素通し」されず 空文字列 として注入される (仕様: Unset variables are
# left blank)。つまりコンテナ内は「セットされているが中身が空」になる。
# AWS CLI / terraform はその空の名前をそのまま使おうとして失敗する。
#   AWS_PROFILE=""       -> The config profile () could not be found
#   AWS_REGION=""        -> Invalid endpoint: https://sts..amazonaws.com
#   AWS_SESSION_TOKEN="" -> 署名時に空のトークンを送って認証エラー
# 値が入っているものはそのまま残すので、ホストで AWS_PROFILE を使う運用は壊さない。
#
# ${localEnv:...} には「空なら注入しない」という書き方が無いため、コンテナ側で受け止める
# しかない。この処理はシェルの全起動経路から読まれる必要がある (詳細は post-create.sh)。
# 何度読まれても同じ結果になるよう、冪等に書くこと。
#
# bash からも zsh からも source されるので、bash 専用の間接展開 ${!v} は使わない。
# eval + ${VAR+x} なら両方で動く。
for __aws_v in AWS_PROFILE AWS_REGION AWS_SESSION_TOKEN AWS_SDK_LOAD_CONFIG \
               AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
  eval "__aws_set=\${${__aws_v}+x}"   # セットされているか (空文字列でも x)
  eval "__aws_val=\${${__aws_v}-}"    # 中身
  if [ -n "${__aws_set}" ] && [ -z "${__aws_val}" ]; then
    unset "${__aws_v}"
  fi
done
unset __aws_v __aws_set __aws_val

# リージョン未指定なら terraform/variables.tf の既定値に合わせる。
# 上の unset で AWS_REGION が消えているとリージョン未設定で terraform が落ちるため、
# ここまで含めて 1 セット。
export AWS_REGION="${AWS_REGION:-ap-northeast-1}"
