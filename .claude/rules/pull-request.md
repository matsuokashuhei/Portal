# Pull Request

## PR作成

- PRのタイトルと説明にIssue番号を記載する
- 以下のテンプレートを使用する

### PRテンプレート

```markdown
## Summary
<変更内容の要約（1-3箇条書き）>

## Review scope
このPRでレビューしてほしいこと:
- <Issue番号で解決する内容に関連する項目>

このPRでレビュー不要なこと:
- <未実装の機能は今後のIssueで対応予定のため、指摘不要>
  - 例: 検索結果の実装 (Issue #49)
  - 例: キーボードナビゲーション (Issue #50)

## Test plan
- [ ] <テスト項目>

Closes #<Issue番号>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### Review scopeの書き方

**レビューしてほしいこと**: 現在のIssueで解決すべき内容
- コードの品質、バグ、セキュリティ、パフォーマンス
- 現在のIssueの要件を満たしているか

**レビュー不要なこと**: 未来のIssueで解決予定の内容
- TODOコメントで明示した将来の実装
- 空の実装やプレースホルダー
- 関連するが別Issueでスコープ外の機能

これにより、Copilotが将来の実装予定に対して指摘することを防ぎ、レビューの効率を上げる。

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

### レビュー監視スクリプト

自動的にレビュー完了を監視し、新しいコメントを検出する:

```bash
# 現在の最新レビュー時刻を記録
LAST_REVIEW=$(gh api repos/{owner}/{repo}/pulls/{PR番号}/reviews \
  --jq '[.[] | select(.user.login | contains("copilot"))] | sort_by(.submitted_at) | last | .submitted_at')

# 30秒おきに最大10分間監視
for i in {1..20}; do
  echo "Check $i/20..."

  # レビュー待ち状態を確認
  PENDING=$(gh pr view {PR番号} --json reviewRequests \
    --jq '[.reviewRequests[].login] | map(select(contains("copilot"))) | length')

  if [ "$PENDING" -gt 0 ]; then
    echo "Copilotがレビュー中..."
  else
    # 新しいレビューがあるか確認
    LATEST=$(gh api repos/{owner}/{repo}/pulls/{PR番号}/reviews \
      --jq '[.[] | select(.user.login | contains("copilot"))] | sort_by(.submitted_at) | last | .submitted_at')

    if [ "$LATEST" != "$LAST_REVIEW" ]; then
      echo "新しいレビューを検出: $LATEST"
      break
    fi
  fi

  sleep 30
done
```

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

### レビューコメントへの返信

`gh api`を使用してスレッド内に返信する:

```bash
gh api repos/{owner}/{repo}/pulls/{PR番号}/comments \
  -X POST \
  -f body="返信内容" \
  -F in_reply_to={コメントID}
```

返信内容のフォーマット:
```markdown
**日本語訳:** <Copilotのコメントを日本語に翻訳>

**対応:** <修正内容または対応しない理由>

- コミット: https://github.com/{owner}/{repo}/commit/{sha}
- 該当箇所: https://github.com/{owner}/{repo}/blob/{sha}/{file}#L{line}
```

## PRステータス監視

```bash
gh pr view <PR番号>              # PRの状態を確認
gh pr checks <PR番号>            # CIチェックの状況を確認
gh api repos/{owner}/{repo}/pulls/{PR番号}/reviews   # レビューコメント確認
gh api repos/{owner}/{repo}/pulls/{PR番号}/comments  # コメント詳細確認
```

すべてのチェックがパスし、レビュー承認を得るまで対応を続ける。
