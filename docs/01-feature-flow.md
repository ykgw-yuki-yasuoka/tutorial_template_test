# 第1章 フィーチャー開発の日常フロー

もっとも頻度の高い「機能を作って main に入れる」流れを 2 周します。
1 周目はガイドつき、2 周目は自力でやってみましょう。

この章で身につく型:

```mermaid
flowchart LR
    I[Issue] --> B
    subgraph br["feature ブランチ (コミットメッセージは雑で OK)"]
        B[ブランチを切る] --> C[自由にコミット]
        C --> PR[PR を作る<br>タイトルだけ Conventional Commits]
    end
    PR --> CI[CI 通過]
    CI --> SQ{{squash merge}}
    SQ --> M[main<br>きれいな履歴]
    M --> D[dev へ自動デプロイ]
```

## 1.1 Issue を作る

```bash
gh issue create \
  --title "検品票のフッターに環境名を表示する" \
  --body "どの環境を見ているか票の下部でも分かるようにしたい"
```

発行された Issue 番号 (以下 `#1` とします) を控えてください。

## 1.2 feature ブランチを切る

```bash
git switch main && git pull
git switch -c feature/1-footer-env
```

ブランチ名は `feature/<issue番号>-<内容>` の形式にします。

## 1.3 変更してコミットする

`frontend/src/App.tsx` の `<footer>` 内に環境名の表示を足します。

```tsx
      <footer className="slip-foot">
        <p>
          同一タグの staging / production でこの票が完全一致すれば、
          「build once / deploy many」が守られている証拠です。
        </p>
        <p>環境: {env}</p>   {/* ← この行を追加 */}
      </footer>
```

ローカルで確認します。backend と frontend は**それぞれ別のターミナル**で起動し、
どちらも動かしたままにします (`Ctrl+C` で止まります)。

ターミナル1 (backend):

```bash
cd backend
uv sync
uv run uvicorn app.main:app --port 8080
```

ターミナル2 (frontend):

```bash
cd frontend
npm install
npm run dev
```

http://localhost:5173 で表示を確認したらコミットして push します。

```bash
git add frontend/src/App.tsx
git commit -m "wip: フッター表示を試す"
git commit --allow-empty -m "微調整"     # わざと雑なコミットを足しておく
git push -u origin feature/1-footer-env
```

> [!NOTE]
> **ブランチ上のコミットメッセージは雑で構いません**。squash merge で
> ブランチ上のコミットは 1 つに畳まれ、main に残るメッセージは
> PR タイトルになるからです。規約が縛るのは PR タイトルだけ、という
> 割り切りがレビューまでの速度を上げます。

## 1.4 PR を作る

**PR タイトルは Conventional Commits 形式**にします。これがそのまま main の
コミットメッセージになります。

```bash
gh pr create \
  --title "feat: 検品票のフッターに環境名を表示" \
  --body "Closes #1"
```

Actions で 3 つのチェック (`pr-title` / `frontend` / `backend`) が走ります。
`gh pr checks --watch` で完了を待ちましょう。

<details>
<summary>▶ ペア/研修モードの場合</summary>

チェック通過後、相手にレビューを依頼します。

```bash
gh pr edit --add-reviewer <相手のログイン名>
```

レビュアーは Files changed を確認して Approve してください。承認が付くまで
マージボタンは押せません。

</details>

## 1.5 squash merge する

```bash
gh pr merge --squash
```

(UI でマージする場合も、選択肢が Squash and merge しかないことを確認してください)

## 1.6 結果を確認する

**main の履歴** — ブランチ上の雑なコミットが消え、PR タイトルが 1 コミットに
なっていることを確認します。

```bash
git switch main && git pull
git log --oneline -3
```

```
abc1234 feat: 検品票のフッターに環境名を表示 (#2)
...
```

**dev への自動デプロイ** — main への push で `CD (dev)` が起動しています。
完了したら dev の URL を開き、フッターに環境名が出ていること、検品票の
`git_sha` が `abc1234...` に変わっていることを確認してください。

**Issue** — `Closes #1` により Issue が自動クローズされています。

## 1.7 演習: もう1周、今度は自力で

バックエンド側の変更で同じ流れを繰り返してください。お題:

> `/api/version` のレスポンスに `region` フィールド (環境変数 `AWS_REGION` の値、
> 未設定なら `"local"`) を追加する。`backend/tests/test_version.py` のフィールド
> 検証にも `region` を加えること。

チェックリスト:

- [ ] Issue を作った
- [ ] `feature/<番号>-<内容>` ブランチで作業した
- [ ] `uv run pytest` がローカルで通る
- [ ] PR タイトルが `feat: ...` 形式で `pr-title` チェックが通った
- [ ] squash merge 後、main の履歴が 1 コミット増えただけになっている
- [ ] dev の検品票で新しい `git_sha` を確認した

> [!TIP]
> Lambda の実行環境では `AWS_REGION` が自動で設定されるため、dev の
> `/api/version` に実リージョン名が出れば成功です (ブラウザで
> `<devのURL>/api/version` を直接開くと JSON が見られます)。

---

← [第0章 セットアップ](./00-setup.md) | [第2章 ガードレール体験 →](./02-guardrails.md)
