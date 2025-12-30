# Pull Request

## PR作成

- PRのタイトルと説明にIssue番号を記載する

## GitHub Copilotレビュー対応

PRを作成すると自動的にGitHub Copilotがレビューを行う。

1. 指摘事項がなくなるまで修正を続ける
2. 各指摘に対して、同じスレッド内で対応内容を返信する
   - 最初にCopilotのレビューコメントを日本語に翻訳して記載する（日本人がレビュー内容を深く理解するため）
   - 修正コミットのURL（例: `https://github.com/{owner}/{repo}/commit/{sha}`）
   - 対応した箇所へのURL（例: `https://github.com/{owner}/{repo}/blob/{sha}/{file}#L{line}`）
3. 返信後、レビューコメントをResolvedにする

### 再レビューリクエスト

修正コミットをプッシュした後:

```bash
gh api repos/{owner}/{repo}/pulls/{PR番号}/requested_reviewers \
  -X POST -f "reviewers[]=copilot-pull-request-reviewer[bot]"
```

### レビュー完了確認

30秒おきに確認:

```bash
gh pr view {PR番号} --json reviewRequests --jq '.reviewRequests[].login'
```

- Copilotが`reviewRequests`にいる場合: レビュー中なので待機を続ける
- Copilotが`reviewRequests`にいない場合: レビュー完了

### レビューコメント取得

```bash
# 最新のCopilotレビューIDを取得
REVIEW_ID=$(gh api repos/{owner}/{repo}/pulls/{PR番号}/reviews \
  --jq '[.[] | select(.user.login | contains("copilot"))] | last | .id')

# そのレビューに紐づくコメントを取得
gh api repos/{owner}/{repo}/pulls/{PR番号}/reviews/$REVIEW_ID/comments
```

- 10分経過しても状態が変わらない場合は確認を終了
- 新しいコメントがあれば対応し、再度プッシュ

## PRステータス監視

```bash
gh pr view <PR番号>              # PRの状態を確認
gh pr checks <PR番号>            # CIチェックの状況を確認
gh api repos/{owner}/{repo}/pulls/{PR番号}/reviews   # レビューコメント確認
gh api repos/{owner}/{repo}/pulls/{PR番号}/comments  # コメント詳細確認
```

すべてのチェックがパスし、レビュー承認を得るまで対応を続ける。
