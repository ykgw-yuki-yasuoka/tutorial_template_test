# 終章 後片付け

演習が終わったら AWS リソースを削除します。放置してもコストはごく小さい構成
ですが、削除まで含めて演習です。

## AWS リソースの削除

```bash
# 自分のリソースの名前 (gitflow-tutorial-<owner>) を先に控える。
# destroy すると terraform の出力も消えるため、後からでは取れない
PREFIX=$(terraform -chdir=terraform output -raw name_prefix)
echo "${PREFIX}"

terraform -chdir=terraform destroy
```

- ECR は `force_delete = true` なのでイメージごと消えます
- S3 は `force_destroy = true` なのでオブジェクトごと消えます
- CloudFront の削除には数分かかります

完了後、コンソールで残骸がないか確認してください
(CloudWatch Logs のロググループ `/aws/lambda/<PREFIX>-*` は Lambda 削除後も残るため、
気になる場合は手動で削除します)。

```bash
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/lambda/${PREFIX}" \
  --query 'logGroups[].logGroupName' --output text | tr '\t' '\n' \
  | xargs -I{} aws logs delete-log-group --log-group-name {}
```

> [!WARNING]
> プレフィックスから `-<owner>` の部分を落として `/aws/lambda/gitflow-tutorial` で
> 実行しないでください。1 つの AWS アカウントを複数人で共有している場合
> ([管理者ガイド](./90-admin.md))、**他の参加者の
> ロググループまで一覧に入り、まとめて消えます**。最小権限ポリシーを使っていれば
> 他人の分は削除が拒否されますが、`AdministratorAccess` で演習している場合は通ります。

## AWS 認証情報の始末

**AWS 側の認証情報 (IAM ユーザーとアクセスキー) は管理者が削除します**
([管理者ガイド](./90-admin.md#演習後の後片付け))。参加者がやることは、**受け取った値を
自分の GitHub から消す**ことだけです。

**Settings → Secrets and variables → Codespaces** から、登録したものをすべて削除して
ください (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_REGION`、一時認証情報を
渡されていた場合は `AWS_SESSION_TOKEN` も)。

一時認証情報は放っておいても AWS 側で失効しますが、失効するのは認証情報であって、
**secrets に登録した値そのものは残り続けます**。次に Codespace を起動したときに
失効済みの値が環境変数として注入され、`ExpiredToken` の原因になります。

`terraform destroy` の前に消すと後片付けができなくなるので、順番に注意してください。

## GitHub 側

リポジトリごと消すなら操作は不要です。教材として残す場合:

- Rulesets / Environments はコストがかからないのでそのままで問題ありません
- `sync-github-vars.sh` が設定した variables には削除済みリソースの名前が
  残るため、混乱を避けたければ Settings → Secrets and variables → Actions
  から削除してください

## 振り返り

このハンズオンで一周したサイクルを、自分の言葉で説明できるか確認してみて
ください。

1. なぜ main への直 push を禁止し、squash merge に一本化するのか
2. なぜアーティファクトに `-rc.N` を焼き込まないのか
3. GA ワークフローからビルドを排除すると、何が保証できるようになるのか
4. なぜバグ修正は main が先 (upstream first) なのか
5. production の承認ゲートが「手順」ではなく「権限」である、とはどういうことか

すべて第1〜4章のどこかで、エラーメッセージや検品票として実際に目にした
はずです。

---

← [第5章 発展演習](./05-advanced.md) | [目次に戻る](./README.md)
