# Git ワークフローチュートリアル テンプレートリポジトリ

開発規約 (trunk-based + バージョン駆動リリース + build once/deploy many + upstream first)
に準拠した開発〜リリースのワークフローを、AWS 上で実際に体験するためのテンプレートです。

**チュートリアル本文は [`docs/`](./docs/README.md) にあります。**
このリポジトリだけで教材・アプリ・インフラ・CI/CD が完結します。

## 構成

```
CloudFront (環境ごとに 1 ディストリビューション × dev / staging / production)
 ├── デフォルト  → S3 (React SPA, OAC)
 └── /api/*     → Lambda Function URL (FastAPI コンテナ, ECR digest 参照デプロイ)
```

```
.
├── frontend/     # Vite + React。/version.json (ビルド時生成) と /api/version を並べて検品するダッシュボード
├── backend/      # FastAPI + Lambda Web Adapter。APP_VERSION / GIT_SHA はビルド時に焼き込み
├── terraform/    # ECR / OIDC ロール×3 / Lambda×3 / S3×3 / CloudFront×3
├── scripts/      # check-aws-permissions.sh / bootstrap-image.sh / setup-github.sh / sync-github-vars.sh
├── .devcontainer/ # Node 22 / Python 3.12 / uv / Terraform / AWS CLI / gh / docker-in-docker
└── .github/
    └── workflows/
        ├── ci.yml           # PR: タイトル検証 (Conventional Commits) + frontend/backend チェック
        ├── cd-dev.yml       # main push → dev 自動デプロイ
        ├── release-rc.yml   # v*-rc.* タグ → 唯一のビルド → Pre-release → staging
        ├── release-ga.yml   # v* タグ → 検証と昇格のみ (再ビルドなし) → production (承認ゲート)
        └── rollback.yml     # 手動起動 → 過去の GA タグを再デプロイ (再ビルドなし) → production (承認ゲート)
```

## ワークフローと規約の対応

| 規約 | このリポジトリでの実装 |
|---|---|
| squash merge + PR タイトル = コミットメッセージ | リポジトリ設定 (`squash_merge_commit_title=PR_TITLE`) + `pr-title` チェック |
| main / release/* の保護 | Rulesets (`setup-github.sh` が作成) |
| RC タグは release/* 上のコミットのみ | `release-rc.yml` のブランチ包含チェック |
| build once | ビルドは `release-rc.yml` のみ。GA はビルドステップ自体が存在しない |
| deploy many (digest 参照) | Lambda へ `repo@sha256:...` でデプロイ。GA は `crane tag` で digest にタグ追加 |
| アーティファクトに rc サフィックスを焼き込まない | ビルド引数 `APP_VERSION` に基底バージョンを渡す |
| 公開済みタグの不変性 | Rulesets (tag deletion/update 禁止) + ECR `IMMUTABLE` |
| ロールバックも再ビルドしない | `rollback.yml` は過去の GA タグの digest / Release アセットを再デプロイするだけ (build ステップが存在しない) |
| 本番デプロイの承認 | GitHub Environment `production` の必須レビュアー (`release-ga.yml` / `rollback.yml` とも) |
| 環境別の権限分離 | OIDC `sub = repo:<repo>:environment:<env>` 条件付き IAM ロール |
| upstream first / バックポート | `?template=backport.md` の PR テンプレート + `git cherry-pick -x` |

## セットアップ手順

前提: **AWS 認証情報のみ** (設定方法は [第0章 0.1](./docs/00-setup.md#aws-認証情報を設定する))。
Terraform / Docker / gh CLI / jq / Node 22 / uv は
[`.devcontainer/`](./.devcontainer/) に揃っているので、Codespaces か VS Code の
*Reopen in Container* で開いてください。devcontainer を使わない場合は自分で用意します
(詳細は [第0章](./docs/00-setup.md))。

**演習環境を用意する側の人** (研修の主催者、または自分の AWS アカウントで一人で演習する人) は
[管理者ガイド](./docs/90-admin.md) を参照してください。IAM ユーザーの作り方、必要な権限、
1 つの AWS アカウントを複数人で共有する方法、
[演習後の後片付け](./docs/90-admin.md#演習後の後片付け) をまとめています。

> [!IMPORTANT]
> Rulesets と Environment 保護ルールを無料で使うには**パブリックリポジトリ**にするか、
> GitHub Team 以上のプランの Organization を使ってください。

```bash
# 0. このテンプレートから自分のリポジトリを作成して clone

# 1. Terraform 変数を設定
cat > terraform/terraform.tfvars <<EOF
github_repository = "<GitHubアカウント>/<リポジトリ名>"
owner             = "<自分の識別子>"   # リソース名とタグに入る。1 アカウントを複数人で共有する場合はここで分ける
# project_name / aws_region は必要に応じて上書き
EOF

# 2. AWS の権限が揃っているか確認 (読み取りだけ。何も作らない)
./scripts/check-aws-permissions.sh

# 3. ECR だけ先に作成 → bootstrap イメージ push → 全体を apply
terraform -chdir=terraform init
terraform -chdir=terraform apply -target=aws_ecr_repository.backend
./scripts/bootstrap-image.sh
terraform -chdir=terraform apply   # CloudFront 作成に数分かかります

# 4. GitHub 側の設定 (どちらかを選択)
./scripts/setup-github.sh solo                 # 一人で演習する場合
./scripts/setup-github.sh pair <reviewer名>    # ペア/研修で規約どおりにする場合

# 5. Terraform 出力を GitHub variables に同期
./scripts/sync-github-vars.sh

# 6. 動作確認: main に空コミットを push できないこと (Ruleset)、
#    PR を作って merge すると dev に自動デプロイされることを確認
```

`solo` モードは必須承認数を 0 にし、production の必須レビュアーを自分自身
(self-review 許可) にします。**本来の規約は承認 1 名以上**です。差分の意味は
チュートリアル本文で解説します。

## ローカル開発

```bash
# backend
cd backend && uv sync && uv run uvicorn app.main:app --port 8080

# frontend (別ターミナル。/api は 8080 へプロキシされる)
cd frontend && npm install && npm run dev
```

## リリースの流れ (チュートリアル第3章の要約)

```bash
git switch main && git pull
git switch -c release/v1.0 && git push -u origin release/v1.0

git tag v1.0.0-rc.1 && git push origin v1.0.0-rc.1   # → ビルド + staging
# staging の画面で検品したら、同一コミットに GA タグ
git tag v1.0.0 && git push origin v1.0.0             # → 承認後 production
```

## コストと後片付け

常時課金はほぼゼロ (Lambda / S3 / CloudFront は無料枠内、ECR ストレージが数十円/月程度)。
演習が終わったら必ず削除してください:

```bash
terraform -chdir=terraform destroy
```
