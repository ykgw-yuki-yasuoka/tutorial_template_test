# 第5章 発展演習

基礎編を完走した人向けの演習集です。独立しているので、興味のあるものだけ
選んでください。💥 は「失敗すれば成功」の実験です。

## 💥 5.1 公開済みタグを消してみる

第2章でやり残したタグ保護の確認です。

```bash
git push --delete origin v1.0.0
```

Ruleset `tutorial-protect-release-tags` に拒否されます。付け替えも試します。

```bash
git tag -f v1.0.0 HEAD~1        # ローカルでは付け替えられるが...
git push --force origin v1.0.0  # 拒否される
git tag -d v1.0.0 && git fetch origin tag v1.0.0   # ローカルを元に戻す
```

**なぜ**: `v1.0.0` は Release・ECR タグ・監査記録・顧客への案内すべてが参照する
公開識別子です。指す先が変わったり消えたりした瞬間、「v1.0.0 とは何か」に
複数の答えが生まれてしまいます。ECR 側も `IMMUTABLE` 設定なので、同名タグの
再 push はレジストリでも拒否されます。

## 💥 5.2 GA の同一コミット検証をわざと失敗させる

「RC で検証したものと違うものを GA にしようとしたら?」を実験します。

```bash
git switch release/v1.0 && git pull
git commit --allow-empty -m "RC後にこっそり足された変更(という設定)"
git push   # ← あれ?
```

......そう、まず**リリースブランチへの直 push 自体が拒否されます**(第一の防壁)。
実験のために、この空コミットを PR 経由で入れてください
(`test: GA検証実験用の空コミット` など)。

その後、RC を打たずにいきなり GA タグを打ちます。

```bash
git switch release/v1.0 && git pull
git tag v1.0.2 && git push origin v1.0.2
```

`Release GA` の `Find matching RC & verify same commit` ステップが fail します
(第二の防壁)。`v1.0.2-rc.*` が存在しないからです。では過去の RC を流用したら?
残念ながら `v1.0.1-rc.1` は `v1.0.2` とコミットが違うので、そちらの経路でも
検証に落ちます。

**なぜ**: 「staging で検証した物」と「本番に出る物」の同一性は、この 2 段の
検証 (RC の存在 + 同一コミット) が保証しています。すり抜けるには RC からやり直す
しかない——それが正しい手順そのものです。

> [!NOTE]
> 後始末: `v1.0.2` タグは保護されていて消せません。実験でゴミタグを作った場合は、
> リポジトリの Settings → Rules → `tutorial-protect-release-tags` を一時的に
> Disabled にして削除 → 必ず Active に戻す、という管理者操作が必要です。
> 「消すのに管理者権限と 3 手かかる」こと自体が保護の実感です。

## 5.3 ロールバック演習

v1.0.1 に問題が見つかった想定で、production を v1.0.0 に戻します。
build once の世界では、ロールバックは「昔のアーティファクトを再デプロイする」
だけです。再ビルドは不要どころか禁止です。

### 手で戻してみる

まず、何が起きるのかを手で確かめます。**戻し先の中身を作り直す作業がどこにも
無い**ことに注目してください。

```bash
# v1.0.0 の digest を調べる (GA のときに push されたイメージ。今も ECR にある)
REPO=$(terraform -chdir=terraform output -raw ecr_repository_name)
aws ecr describe-images \
  --repository-name "${REPO}" \
  --image-ids imageTag=v1.0.0 \
  --query 'imageDetails[0].imageDigest' --output text

# backend: update-function-code --image-uri <repo>@<digest>
# frontend: gh release download v1.0.0 -p 'dist-*.tar.gz' → sha256sum -c → s3 sync
```

### ワークフローで戻す

同じことを `Rollback production` ワークフロー
([`.github/workflows/rollback.yml`](../.github/workflows/rollback.yml)) が行います。
**Actions → Rollback production → Run workflow** で、戻し先タグ (`v1.0.0`) を
入力して実行してください。

`production` 環境を使うので、GA と同じく**承認ゲートで止まります**。ロールバックは
本番を書き換える操作である以上、通る門は同じです。承認すると v1.0.0 の digest が
そのまま Lambda に載り、v1.0.0 の tar.gz が S3 に同期されます。

終わったら production の検品票を開いて、`version` と `image_digest` が v1.0.0 の
ものに戻っていることを確認します。

### 読みどころ

- **`docker build` も `npm run build` も無い。** GA と同じく、ロールバックも「既に
  あるものを指し直す」だけの操作です
- **`contents: read`。** 新しい Release を作らないので、書き込み権限すら要りません
- **`concurrency: group: release`。** リリースとロールバックが交差して、production に
  中途半端な組み合わせが載るのを防いでいます
- **GA タグしか受け付けない。** RC タグや、Release の無いタグ、Pre-release には戻せません。
  「production に載ってよいのは GA だけ」という規約は、緊急時にも緩みません

> [!NOTE]
> ロールバックしても Git のタグや Release は動きません (`v1.0.1` は Release として
> 残ったままです)。**出荷の履歴は記録なので、書き換えない**のが正しい姿です。動かすのは
> 「今どれが載っているか」だけ。修正版は `v1.0.2` として前に進めます (5.4 の設計演習へ)。

発展課題: このワークフローを `environment` も入力にして staging にも戻せるように
してみてください。「どの環境に、どの承認者で」が入力次第で変わることになります —
それは安全でしょうか?

## 5.4 ホットフィックスの設計を考える

「staging 検証を待てないほど緊急の本番障害」への対応を設計する思考演習です。

現在のパイプラインは GA の前提として RC を要求します。これは緊急時も**外すべき
ではありません** — このパイプラインでは RC → staging デプロイ → GA まで
10 分程度であり、「検証を省略する」独自経路を作るより、**正規の経路を全力で
走る**方が安全かつ十分に速いからです。

考えてみてください:

1. 障害修正の cherry-pick から production 反映まで、正規経路での最短手順を
   書き出すと何分かかるか (実測してみましょう)
2. それでも遅すぎるケースとは何か。その場合に守るべき最低限の検証は何か
3. 「緊急時は手動デプロイ OK」という例外を作った組織で何が起きるか

## 5.5 チャレンジ: Fargate 化

Lambda を ECS Fargate + ALB に置き換えると、実際の SaaS 構成にぐっと近づきます。
ワークフロー側の変更が「`update-function-code` → `ecs update-service` +
タスク定義の image を digest で更新」に変わるだけで、**リリースフローの構造は
一切変わらない**ことを確認するのがこの課題の狙いです。

主な変更点: Terraform (VPC / ALB / ECS クラスタ・サービス ×3、CloudFront の
オリジンを ALB に変更)、IAM (ecs:UpdateService 等)、デプロイステップ。
常時課金 (Fargate 0.25vCPU ×3 で月 $25 前後) が発生する点に注意してください。

---

← [第4章 バックポート](./04-backport.md) | [終章 後片付け →](./99-cleanup.md)
