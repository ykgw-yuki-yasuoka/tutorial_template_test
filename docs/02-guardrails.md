# 第2章 ガードレール体験

この章では**わざと違反行為を試みて、仕組みに止められる**体験をします。
ルールを「知っている」のと「破ろうとしても破れないことを確認した」のとでは
安心感がまったく違います。すべての手順で、**エラーが出れば成功**です。

> [!NOTE]
> ここで試すことはすべて安全です。ガードレールが機能していれば何も壊れませんし、
> 万一設定漏れで通ってしまったら、それはセットアップの問題を発見できたということです
> (`./scripts/setup-github.sh` を再実行してください)。

## 💥 2.1 main へ直接 push する

```bash
git switch main && git pull
git commit --allow-empty -m "直接pushのテスト"
git push
```

期待される結果:

```
remote: error: GH013: Repository rule violations found for refs/heads/main.
remote: - Changes must be made through a pull request.
```

**なぜ**: main はデプロイ可能であるべきトランクです。CI を通っていない変更が
入る経路 (直 push) を Ruleset が塞いでいます。後始末をしておきます。

```bash
git reset --hard origin/main
```

## 💥 2.2 main を force push で書き換える

force push は「履歴を書き換えて上書きする」操作なので、まず書き換える対象を
作ります。`git commit --amend` は直前のコミットを作り直す操作で、**すでに
push 済みのコミットに対して行うとコミット ID が変わり、リモートの履歴と
食い違います**。

```bash
git switch main && git pull
git log --oneline -1                       # 書き換える前のコミット ID を控える
git commit --amend -m "履歴を書き換えるテスト"
git log --oneline -1                       # コミット ID が変わっている
git status -sb                             # origin/main と 1 コミットずつ分岐している
```

`git status -sb` の 1 行目が `## main...origin/main [ahead 1, behind 1]` に
なっていれば準備完了です。origin/main の先頭コミットがローカルから消えたので、
通常の push は非 fast-forward として拒否されます。これを力ずくで上書きしようと
するのが force push です。

```bash
git push --force
```

`non_fast_forward` ルールにより拒否されます (直 push 禁止と二重にブロック)。
リモートの履歴は 1 コミットも失われていません。

**なぜ**: force push は共有ブランチの履歴を書き換え、全員の手元との整合性を
破壊します。squash merge 運用では main の履歴そのものが変更管理台帳なので、
書き換え不能であることが台帳としての信頼の根拠になります。

書き換えたローカルの main を元に戻しておきます。

```bash
git reset --hard origin/main
```

## 💥 2.3 規約違反の PR タイトルで出す

```bash
git switch main && git pull
git switch -c feature/title-test
git commit --allow-empty -m "テスト"
git push -u origin feature/title-test
gh pr create --title "修正しました" --body "タイトル検証のテスト"
```

CI の完了を待ちます。

```bash
echo "⏳ CI の完了を待っています..."
while true; do
  # チェックが 1 つも登録されていない間は gh pr checks が失敗するので、出力は空 (= まだ待つ)
  buckets=$(gh pr checks --json bucket --jq '.[].bucket' 2>/dev/null)
  if [ -n "$buckets" ] && ! echo "$buckets" | grep -qx pending; then break; fi
  echo "  ... 実行中です (5 秒後に再確認)"
  sleep 5
done
gh pr checks   # fail があるので非ゼロ終了しますが、それが期待どおりです
```

> [!NOTE]
> `gh pr checks --watch` は、チェックがまだ 1 つも登録されていないタイミング
> (= PR 作成直後) に実行すると、待たずに終了したりエラーになったりします。
> 上のループは「チェックが出そろって pending が 1 つもなくなる」まで待つので、
> PR 作成直後にそのまま貼り付けても取りこぼしません。この後も同じループを使います。

`pr-title` チェックが **fail** します。Actions のログを開くと、許可される
type の一覧 (`feat` / `fix` / `chore` ...) が表示されています。

タイトルを直すとチェックが通ることも確認しましょう。CI は PR のタイトル編集
(`edited`) でも再実行されます。

```bash
gh pr edit --title "test: タイトル検証の動作確認"
sleep 10   # 再実行されたチェックが登録されるのを待つ (先に進むと 1 回目の結果を見てしまう)
```

```bash
echo "⏳ CI の完了を待っています..."
while true; do
  buckets=$(gh pr checks --json bucket --jq '.[].bucket' 2>/dev/null)
  if [ -n "$buckets" ] && ! echo "$buckets" | grep -qx pending; then break; fi
  echo "  ... 実行中です (5 秒後に再確認)"
  sleep 5
done
gh pr checks   # 今度はすべて pass になる
```

**なぜ**: squash merge では PR タイトルがそのまま main のコミットメッセージに
なります。つまりタイトル検証は「main の履歴の品質検査」を PR の段階で
やっていることになります。確認できたら PR はクローズしてください。

```bash
gh pr close feature/title-test --delete-branch
```

## 💥 2.4 merge commit / rebase merge を試す

マージ方式を試すための PR を 1 つ作ります。

```bash
git switch main && git pull
git switch -c feature/merge-method-test
git commit --allow-empty -m "マージ方式テスト"
git push -u origin feature/merge-method-test
gh pr create --title "test: マージ方式の制限を確認" --body "merge commit / rebase merge が選べないことの確認"
```

この PR を GitHub の UI で開き、マージボタンのドロップダウン (▼) を開いて
ください。

```bash
gh pr view --web
```

期待される結果: **Squash and merge しか存在しない**。

CLI でも試します。CI が終わっていないと「必須チェック未通過」の方で先に弾かれ、
マージ方式の制限が確認できないので、2.3 と同じループで待ちます。

```bash
echo "⏳ CI の完了を待っています..."
while true; do
  buckets=$(gh pr checks --json bucket --jq '.[].bucket' 2>/dev/null)
  if [ -n "$buckets" ] && ! echo "$buckets" | grep -qx pending; then break; fi
  echo "  ... 実行中です (5 秒後に再確認)"
  sleep 5
done
gh pr checks   # すべて pass になっている (= マージを止めるものは方式の制限だけ)
```

```bash
gh pr merge --merge
# => Merge commits are not allowed on this repository.
```

**なぜ**: マージ方式を人間の注意力に任せると必ず事故ります。リポジトリ設定で
選択肢そのものを消すのが最も確実なガードレールです。確認できたら PR は
クローズしてください (squash merge なら通ってしまうので、マージはしません)。

```bash
gh pr close feature/merge-method-test --delete-branch
```

## 💥 2.5 CI が落ちる変更をマージしようとする

```bash
git switch main && git pull
git switch -c feature/break-test
```

`backend/app/main.py` の `/api/healthz` の戻り値を書き換えます。

```python
@app.get("/api/healthz")
def healthz() -> dict:
    return {"ok": False}   # ← True から False に変える
```

`backend/tests/test_version.py` が `{"ok": True}` を期待しているので、これで
`uv run pytest` が落ちる = `backend` チェックが fail する状態になります。
push して PR を作ります。

```bash
git add -A && git commit -m "テストを壊す"
git push -u origin feature/break-test
gh pr create --title "test: CI必須チェックの確認" --body "壊れたコードはマージできないことの確認"
```

CI の完了を待ちます (2.3 と同じループです)。

```bash
echo "⏳ CI の完了を待っています..."
while true; do
  buckets=$(gh pr checks --json bucket --jq '.[].bucket' 2>/dev/null)
  if [ -n "$buckets" ] && ! echo "$buckets" | grep -qx pending; then break; fi
  echo "  ... 実行中です (5 秒後に再確認)"
  sleep 5
done
gh pr checks   # backend が fail
```

`backend` チェックが fail し、**マージボタンが押せない**ことを確認してください。

```bash
gh pr merge --squash
# => Pull request is not mergeable: the base branch policy prohibits the merge.
```

**なぜ**: `required_status_checks` により、CI 通過はマージの前提条件です。
「レビューで気をつける」ではなく「通らないと物理的に入らない」が正解です。
確認できたらクローズします。

```bash
gh pr close feature/break-test --delete-branch
```

<details>
<summary>▶ ペア/研修モードの場合: 承認なしマージも試す</summary>

CI がすべて通った PR で、承認が付く前に `gh pr merge --squash` を実行して
ください。レビュー承認数の不足で拒否されます。solo モードでは承認数を
0 に緩和しているため、この体験はできません。

</details>

## 2.6 この章のまとめ

| 試したこと | 止めたもの | 層 |
|---|---|---|
| main へ直 push | Ruleset: pull_request 必須 | Git サーバー |
| force push | Ruleset: non_fast_forward | Git サーバー |
| 雑な PR タイトル | CI: pr-title チェック | CI |
| merge commit | リポジトリ設定 (選択肢が存在しない) | 設定 |
| 壊れたコードのマージ | Ruleset: required_status_checks | Git サーバー × CI |

ポイントは、どれも「気をつけましょう」という運用ルールではなく、
**破れない仕組み**として実装されていることです。レビューは設計や仕様の議論に
集中でき、形式的なチェックは機械に任せられます。

タグの保護 (削除・付け替え禁止) はまだ試せません — タグがないからです。
第3章でリリースした後、第5章で壊しに行きます。

---

← [第1章 フィーチャー開発](./01-feature-flow.md) | [第3章 v1.0 リリース →](./03-release.md)
