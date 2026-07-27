# 第0章 セットアップ

AWS リソースの作成と GitHub 側の設定を行います。CloudFront の作成に数分かかるので、
`terraform apply` を流している間に第1章の冒頭を読んでおくのがおすすめです。

## 0.1 前提条件

このリポジトリには devcontainer が入っています。**自分で用意するのは AWS アカウントと
認証情報だけ**で、Terraform / Docker / jq / gh / Node 22 / uv はコンテナ側に揃っています。

このテンプレートリポジトリの **Use this template → Create a new repository** で作った
**自分のリポジトリ**を、次のどちらかで開いてください (Rulesets や Environments の設定は
自分のリポジトリに対して行うので、テンプレート側を直接開くと 0.3 で失敗します)。

- GitHub の **Code → Codespaces → Create codespace**
- 手元に clone して VS Code で開き、**Reopen in Container**

コンテナが立ち上がったら、ツールが揃っていることを確認します。

```bash
node -v            # v22.x
terraform version  # 1.7 以上
aws --version
uv --version
```

### AWS 認証情報を設定する

**研修などで演習する場合、管理者から次の 4 つを受け取ります。** AWS の画面を触る必要は
ありません。

| 受け取るもの | 例 |
|---|---|
| `AWS_ACCESS_KEY_ID` | `AKIA...` (20 文字) |
| `AWS_SECRET_ACCESS_KEY` | 40 文字 |
| `AWS_REGION` | `ap-northeast-1` |
| `owner` | `alice` (あなた専用の目印。[0.2](#02-aws-リソースの作成) で使います) |

上の 3 つ (`AWS_` で始まるもの) をコンテナに渡します。`owner` は [0.2](#02-aws-リソースの作成)
で `terraform.tfvars` に書くので、ここでは使いません。

| 開き方 | 渡し方 |
|---|---|
| **Codespaces** | リポジトリの **Settings → Secrets and variables → Codespaces** に登録する (一時認証情報を渡された場合は `AWS_SESSION_TOKEN` も) |
| ローカルの VS Code | ホストの `~/.aws` が読み取り専用でマウントされます。ホスト側で `aws configure` を済ませてあれば、何もしなくて OK |

> [!NOTE]
> Codespaces secrets は起動時に環境変数として注入されます。**すでに起動している
> Codespace には反映されない**ので、登録後に再起動してください。

設定できたか確認します。

```bash
aws sts get-caller-identity   # Account / Arn が返れば OK
```

`InvalidClientTokenId` や `ExpiredToken` が返る場合は、キーの貼り間違いか、一時認証情報の
期限切れです。

`terraform apply` に必要な権限が揃っているかは、`owner` を書いたあとの
[0.2](#02-aws-リソースの作成) の手順 2 でまとめて確認します。

> [!CAUTION]
> アクセスキーはパスワードと同じです。リポジトリにコミットしない (`.gitignore` 済みの
> `terraform.tfvars` にも書かない)、Slack やメールに貼らない。演習が終わったら
> [終章](./99-cleanup.md) で Codespaces secrets を削除します (AWS 側のキーは管理者が
> 消します)。

<details>
<summary>▶ <b>自分の AWS アカウントで演習する場合 / 演習環境を用意する側の場合</b></summary>

IAM ユーザーの作り方、必要な権限、1 つの AWS アカウントを複数人で共有する方法は
**[管理者ガイド](./90-admin.md)** にまとめました。

- 自分のアカウントで一人で演習する → [一人で演習する場合](./90-admin.md#一人で演習する場合)
- 研修環境を用意する → [管理者ガイド](./90-admin.md) 全体
- IAM Identity Center (AWS SSO) を使っている → [該当節](./90-admin.md#iam-identity-center-aws-sso-を使っている組織の場合)

用意ができたら、上と同じように認証情報をコンテナに渡してください。

</details>

<details>
<summary>▶ <code>config profile ()</code> や <code>sts..amazonaws.com</code> というエラーが出る場合</summary>

キーは正しいのに、次のようなエラーが出ることがあります。

```
aws: [ERROR]: The config profile () could not be found
aws: [ERROR]: Invalid endpoint: https://sts..amazonaws.com
```

どちらも**空の環境変数**が原因です。括弧の中とホスト名の途中が空欄になっているのが
その印で、AWS CLI は「空のプロファイル名」「空のリージョン名」をそのまま使おうとして
失敗しています。

`.devcontainer/devcontainer.json` の `remoteEnv` はホストの値をコンテナへ引き渡しますが、
**ホスト側でその変数が未設定だと `${localEnv:...}` は空文字列に展開されます** (未設定の
まま素通しにはなりません)。結果、コンテナ内では「セットされているが中身が空」という
状態になります。`AWS_PROFILE` を使わず環境変数だけで認証する Codespaces で起きがちです。

これは `.devcontainer/shell-env.sh` が自動で取り除くので、**通常は起きません**。
それでも出る場合は、コンテナ作成時の `post-create.sh` が最後まで走らなかった可能性が
高いです。コマンドパレットから **Rebuild Container** を実行してください。

急ぐ場合は、開いているシェルで直接消しても通ります。

```bash
unset AWS_PROFILE AWS_SESSION_TOKEN     # B の恒久キーなら SESSION_TOKEN は不要
export AWS_REGION=ap-northeast-1        # terraform/variables.tf の既定値
aws sts get-caller-identity
```

どの変数が空かは、値を表示せずに長さだけで確認できます。

```bash
for v in AWS_PROFILE AWS_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  val="${!v}"
  if   [ -z "${!v+x}" ]; then echo "$v: 未設定 (OK)"
  elif [ -z "$val"    ]; then echo "$v: 空 <-- これが原因"
  else echo "$v: 設定あり (${#val} 文字)"; fi
done
```

`AWS_ACCESS_KEY_ID` が 20 文字、`AWS_SECRET_ACCESS_KEY` が 40 文字あれば認証情報そのものは
正しく渡っています。

</details>

> [!IMPORTANT]
> Rulesets と Environment 保護ルールを無料プランで使うには、リポジトリを
> **パブリック**にする必要があります。プライベートで演習したい場合は
> GitHub Team 以上のプランの Organization を使ってください。

> [!WARNING]
> Codespaces に既定で入っている `gh` のトークン (環境変数 `GITHUB_TOKEN`) には
> Rulesets を作る権限がありません。`gh` は保存済みの認証情報より環境変数を優先するため、
> `gh auth login` の前に `unset GITHUB_TOKEN` が必要です。手順は 0.3 に書いています。
> 外し忘れると `Resource not accessible by integration (HTTP 403)` で失敗します。

<details>
<summary>▶ devcontainer を使わず、ローカルに直接そろえる場合</summary>

以下をインストールしてください。

- AWS アカウントと認証情報 (`aws sts get-caller-identity` が通ること)
- Terraform >= 1.7 / Docker / jq
- gh CLI (`gh auth status` でログイン済みであること)
- Node.js 22 / [uv](https://docs.astral.sh/uv/)

Node のバージョンは CI (`.github/workflows/ci.yml`) と揃えてください。ズレていると
「手元では通るのに CI で落ちる」が起きます。

</details>

## 0.2 AWS リソースの作成

Lambda はコンテナイメージがないと作成できないため、「ECR だけ先に作る → 初期イメージを
push → 全体を apply」の 3 段階で進めます。**1 つずつ、順番に実行してください** (`terraform`
は数分かかるものがあります)。

**1. Terraform の変数を書く**

```bash
cat > terraform/terraform.tfvars <<EOF
github_repository = "<GitHubアカウント>/<リポジトリ名>"
owner             = "<自分の識別子>"
EOF
```

`owner` は作られるリソースの名前とタグに入る、あなた専用の目印です (英小文字・数字・
ハイフン、13 文字以内)。**管理者から `owner` を伝えられている場合は、その値を一字一句
同じに書いてください。**ズレていると、名前もタグも許可範囲の外に出るため `terraform apply`
が `AccessDenied` で落ちます。自分のアカウントで一人で演習するなら好きな値で構いません。

**2. 権限が揃っているか確かめる** (読み取りだけ。何も作りません)

```bash
./scripts/check-aws-permissions.sh
```

ここで `権限なし` が出たら、先に進んでも `terraform apply` の途中で `AccessDenied` になる
だけです。表示された内容に従うか、管理者に伝えてください。

**3. Terraform を初期化する**

```bash
terraform -chdir=terraform init
```

**4. ECR リポジトリだけ先に作る**

```bash
terraform -chdir=terraform apply -target=aws_ecr_repository.backend
```

**5. 初期イメージ (`:bootstrap`) を push する**

```bash
./scripts/bootstrap-image.sh
```

**6. 残り全体を作る** (CloudFront の作成に数分かかります)

```bash
terraform -chdir=terraform apply
```

<details>
<summary>▶ <b><code>terraform apply</code> の途中でターミナルが切れた / Codespace が再起動した場合</b></summary>

CloudFront の作成に数分かかるため、この apply は途中でネットワークが切れたり、ブラウザの
タブを閉じてしまったりしがちです。**作りかけのリソースは AWS 側に残っています**が、
Terraform は state に書き切れていない可能性があります。次の順で確認してください。

**1. ロックを外す**

apply し直すと `Error acquiring the state lock` が出ることがあります。前のプロセスが
掴んだままのロックが残っているためです。エラーに表示される Lock ID で外します。

```bash
terraform -chdir=terraform force-unlock <LOCK_ID>
```

> [!WARNING]
> 外してよいのは**その apply が確実に死んでいる場合だけ**です。別のターミナルでまだ
> apply が動いているなら、それが終わるのを待ってください。生きているプロセスから
> ロックを奪うと、state が壊れます。

**2. どこまで作られたかを見る**

state と実物を突き合わせます。

```bash
terraform -chdir=terraform plan
```

差分が出れば、それが「まだ作られていないもの」です。**そのまま apply を流し直せば残りが
作られます** (Terraform は作成済みのものを作り直しません)。

**3. 完了していたか分からないとき**

output が取れれば apply は完走しています。

```bash
terraform -chdir=terraform output
```

空やエラーになるなら未完了です。apply を流し直してください。

</details>

**7. state ファイルを管理者に提出する**

> [!CAUTION]
> `terraform/terraform.tfstate` は `terraform destroy` に**必須**のファイルです。
> Codespace を削除すると state も一緒に消え、**リソースを一括削除する手段が失われます**
> (残骸を 1 つずつ手で消すことになります)。**apply が成功したら、その場で提出してください。**

`terraform/terraform.tfstate` をダウンロードし (VS Code のエクスプローラでファイルを右クリック →
**Download**)、管理者の指定する場所 (共有ドライブなど) に置いてください。管理者が受領を確認して
から次に進みます。自分の AWS アカウントで一人で演習している場合は、Codespace の外に控えて
おけば十分です。

> [!NOTE]
> state に AWS の認証情報は入りませんが、リソース ID や ARN が並ぶため構成は読み取れます。
> 演習の範囲外に共有しないでください。

作成されるもの: ECR リポジトリ ×1、環境別 (dev / staging / production) に
IAM ロール・Lambda・S3 バケット・CloudFront ディストリビューション各 ×3。すべて
`gitflow-tutorial-<owner>-...` という名前で、`Owner=<owner>` タグが付きます。

> [!IMPORTANT]
> GitHub の OIDC プロバイダ (`token.actions.githubusercontent.com`) は、URL ごとに
> AWS アカウントで 1 つしか作れない**アカウント共有リソース**です。プロジェクト単位の
> リソースとは寿命が違うため、既定 (`create_oidc_provider = false`) では Terraform は
> **既存のものを参照するだけ**で、作成も削除もしません。うっかり管理下に置くと、
> 演習後の `terraform destroy` で他プロジェクトの OIDC 連携ごと消してしまうためです。
>
> 誰かと共用している AWS アカウントで受講するなら、既定のままで OK です。
> **自分専用のまっさらなアカウント**で、まだプロバイダが無い場合だけ `terraform.tfvars` に
> `create_oidc_provider = true` を足してください。判断に迷ったら、まず既定のまま apply して
> エラーメッセージで判断できます。
>
> | 状況 | 設定 | 間違えると |
> |---|---|---|
> | プロバイダが既にある | `false` (既定) | `true` にすると `EntityAlreadyExists` (409) |
> | プロバイダが無い | `true` | `false` のままだと `NoSuchEntity` |

> [!NOTE]
> IAM ロールは GitHub Actions の OIDC トークンでのみ assume でき、しかも
> `sub` クレームを `environment:<env>` に限定しています。つまり **GitHub Environments
> の保護ルールを通過しないと、その環境の AWS 権限が手に入らない**構造です。
> この意味は第3章で体感します。

## 0.3 GitHub 側の設定

Codespaces では、まず `gh` を自分のアカウントでログインし直します。環境変数を先に外さないと、
`gh` はそちらを優先し続けます。

```bash
unset GITHUB_TOKEN
gh auth login   # GitHub.com → HTTPS → Authenticate Git: Yes → スコープは既定のまま
gh auth status  # 末尾が (GITHUB_TOKEN) 以外になっていれば成功
```

`unset` はそのターミナルにだけ効きます。別のターミナルを開くと `GITHUB_TOKEN` が復活するので、
その場合は下のコマンドを `env -u GITHUB_TOKEN ./scripts/setup-github.sh solo` の形で実行してください。

次に、演習モードを選んでスクリプトを実行します。

```bash
./scripts/setup-github.sh solo
```

<details>
<summary>▶ ペア/研修モードの場合</summary>

```bash
./scripts/setup-github.sh pair <レビュアーのGitHubログイン名>
```

pair モードは PR の必須承認数 1、production デプロイの承認者は指定した相手、
自己承認は不可、という**本来の運用どおり**の設定になります。

</details>

> [!WARNING]
> `solo` モードは一人で演習を完走するために 2 点を緩和しています。
> **本来の運用は pair モードの設定**です。
> - PR の必須承認数: 1 → 0 (GitHub では自分の PR を自己承認できないため)
> - production の必須レビュアー: 自分自身 + self-review 許可

このスクリプトが設定する内容:

| 設定 | 内容 | 守っているもの |
|---|---|---|
| マージ方式 | squash のみ、コミットタイトル = PR タイトル | main の履歴 1 PR = 1 コミット |
| Ruleset `tutorial-protect-main` | 直 push / force push / 削除禁止、PR + CI 必須 | トランクの健全性 |
| Ruleset `tutorial-protect-release-branches` | `release/**` に同上 | リリースブランチの健全性 |
| Ruleset `tutorial-protect-release-tags` | `v*` タグの削除・付け替え禁止 | 公開済みタグの不変性 |
| Environments | dev / staging / production (本番のみ承認必須) | 本番デプロイの承認ゲート |
| ラベル | `type: feat` / `type: fix` など (Conventional Commits の type と 1:1) | PR タイトルからの自動付与 → リリースノートのカテゴリ分け |

続けて、Terraform の出力 (ロール ARN、関数名、バケット名など) を GitHub の
variables に流し込みます。

```bash
./scripts/sync-github-vars.sh
```

最後に各環境の URL が表示されます。**メモしておいてください** (以降の章で使います)。

この時点では、まだどの環境にもアプリは載っていません (Lambda は `:bootstrap` イメージの
まま)。最初のデプロイは第1章の PR がそのまま担うので、ここでは URL を控えるだけで
次に進んでください。

<details>
<summary>▶ <b>CD が <code>Not authorized to perform sts:AssumeRoleWithWebIdentity</code> で失敗する場合</b></summary>

**ここまで (0.3) を終える前に main へ push していたなら、その失敗は想定内です。**
AWS ロールを作るのは 0.2、その ARN を GitHub の variables に入れるのは 0.3 の
`sync-github-vars.sh` です。この間に走った CD には渡すべきロールがまだ無いので、必ず落ちます。

0.3 まで完了しているなら、**失敗した run を再実行するだけで通ります** (再実行は現在の
variables を読み直します)。

```bash
gh run list --workflow=cd-dev.yml --limit 5
gh run rerun <RUN_ID> --failed
```

再実行しても同じエラーが出るなら、設定のどこかが食い違っています。AWS はロールの存在を
呼び出し側に漏らさないため、この 1 文は「ロールが無い」「信頼ポリシーの条件が合わない」
「プロバイダが違う」のどれでも同じ文言になります。権限の問題に見えますが、実際にはほぼ
名前の食い違いです。上から順に潰してください。

**1. variables のロール ARN が自分のものか**

```bash
gh variable list --env dev
echo "$(terraform -chdir=terraform output -raw name_prefix)-dev-deploy"
```

`AWS_ROLE_ARN` の末尾が下の行と一致していること。違っていれば `./scripts/sync-github-vars.sh`
を実行し直します。

**2. 信頼ポリシーの `sub` が、GitHub の送る値と一致するか**

```bash
aws iam get-role \
  --role-name "$(terraform -chdir=terraform output -raw name_prefix)-dev-deploy" \
  --query 'Role.AssumeRolePolicyDocument' --output json

echo "repo:$(gh repo view --json nameWithOwner -q .nameWithOwner):environment:dev"
```

出力の `sub` の `repo:<owner>/<repo>` の部分と、下の行が一致していること。ズレていたら
`terraform/terraform.tfvars` の `github_repository` を実際のリポジトリ名に直し、
`terraform -chdir=terraform apply` の後に `./scripts/sync-github-vars.sh` を実行し直して
ください。

`aws iam get-role` が `NoSuchEntity` を返す場合は、0.2 の `terraform apply` が完走して
いません。0.2 に戻ってください。

**3. GitHub の不変 ID (immutable ID) で `sub` がズレていないか**

名前は一致しているのに落ちる場合、これが原因のことがあります。GitHub は OIDC の `sub` の
リポジトリ部分を、名前ではなく数値の**不変 ID** で発行するアカウントがあります
(`repo:<owner>@<数値>/<repo>@<数値>:...`)。名前は一致して見えるのに数値 ID の部分だけ
食い違うため、最も気付きにくい経路です。

```bash
gh api "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/actions/oidc/customization/sub" \
  -q .sub_claim_prefix
```

出力に `@<数値>` が入っていれば、あなたのアカウントは不変 ID の対象です。信頼ポリシー
([`terraform/oidc.tf`](../terraform/oidc.tf)) は名前ベースと不変 ID の両形式を許可して
いるので、**この tutorial の最新の Terraform を apply していれば通ります**。古い版で
作ったロールが残っているなら、`terraform -chdir=terraform apply` で信頼ポリシーを
更新してください。

**4. OIDC プロバイダが `sts.amazonaws.com` を受け付けるか**

```bash
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn \
    "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):oidc-provider/token.actions.githubusercontent.com" \
  --query '{url:Url, audiences:ClientIDList}'
```

`audiences` に `sts.amazonaws.com` が無ければ原因はこれです。ただしプロバイダは
**アカウント共有のリソース**なので、AWS アカウントを共有して受講している場合は自分では
直せません (同じアカウントの参加者全員が同時に落ちているはずです)。管理者に連絡してください。

</details>

---

← [目次](./README.md) | [第1章 フィーチャー開発 →](./01-feature-flow.md)
