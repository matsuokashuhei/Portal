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

## レビュー対応

PRを作成すると自動的にGitHub Copilotがレビューを行う。また、人間のレビュアーからもコメントが付くことがある。

### 対応するレビュアー

以下のレビュアーからのレビューに対応する:

| レビュアー | 種別 | 備考 |
|-----------|------|------|
| `copilot-pull-request-reviewer[bot]` | 自動 | インラインコメント形式 |
| `matsuokashuhei` | 人間 | インラインコメントまたはレビュー本文 |

**人間レビュアーの場合の注意点:**
- インラインコメントだけでなく、レビュー本文（body）に指摘事項が含まれる場合がある
- レビュー本文に指摘がある場合は、PRコメントで返信する（`gh pr comment`）

### 対応方針

レビュー指摘を受けた場合、機械的に修正するのではなく、以下の観点で対応の要否を判断する:

1. **コードベース全体との整合性**
   - 指摘箇所だけでなく、プロジェクト全体のコンテキストを考慮する
   - 既存のコーディングパターンや設計方針と照らし合わせる
   - 同様のコードが他の箇所でどう書かれているか確認する

2. **指摘の妥当性評価**
   - 指摘が現在のIssueのスコープ内か確認する
   - 将来のIssueで対応予定の内容でないか確認する
   - 指摘された問題が実際にリスクとなるか評価する

3. **対応の判断**
   - **修正する**: 指摘が妥当で、修正によりコード品質が向上する場合
   - **修正しない**: 以下の場合は根拠を示して説明する
     - 既存のパターンと一貫性を保つため
     - 将来のIssueで対応予定のため
     - 指摘が誤解に基づいている場合
     - 過剰な複雑化を招く場合

### 延期した指摘のIssue登録

レビュー指摘への対応を将来に延期する場合、忘れないようにGitHub Issueを作成する。

**Issue作成が必要なケース:**
- 指摘は妥当だが、現在のPRスコープ外
- 対応に時間がかかるため、別途対応したい
- 関連する他の変更と一緒に対応したい

**Issue作成手順:**

```bash
gh issue create \
  --title "<指摘内容の要約>" \
  --body "$(cat <<'EOF'
## 背景

PR #<PR番号> のレビューで指摘された内容。

## 指摘内容

<レビューコメントの内容>

## 対応方針

<対応方針があれば記載>

## 関連

- PR: #<PR番号>
- レビューコメント: <コメントURL>
EOF
)"
```

**レビューコメントへの返信:**

Issue作成後、レビューコメントに返信してリンクする:

```markdown
**対応:** 将来のIssueで対応予定

この指摘は妥当ですが、現在のPRスコープ外のため Issue #<Issue番号> として登録しました。
```

### 対応手順

**Copilot・人間レビュアー共通:**

1. 指摘事項を評価し、対応方針に基づいて修正の要否を判断する
2. 各指摘に対して、同じスレッド内で対応内容を返信する
   - レビューコメントが英語の場合は日本語に翻訳して記載する（日本語の場合は翻訳不要）
   - 修正コミットのURL（例: `https://github.com/{owner}/{repo}/commit/{sha}`）
   - 対応した箇所へのURL（例: `https://github.com/{owner}/{repo}/blob/{sha}/{file}#L{line}`）
3. 返信後、レビューコメントをResolvedにする
4. すべての指摘に対応するまで1-3を繰り返す

### レビューコメントの取得

⚠️ **重要**: `gh api`のデフォルトは30件のみ返却。`--paginate`オプションで全件取得すること。

⚠️ **`--paginate`と`--jq`の注意点**: `--paginate`使用時、`--jq`は各ページに対して個別に適用される。そのため`[...] | last`のような配列操作は各ページの最後の要素を返し、意図しない結果になる。代わりに、各要素を1行ずつ出力し`| tail -1`で最後を取得する。

```bash
# すべてのレビューを一覧表示（--paginateで全件取得）
gh api repos/{owner}/{repo}/pulls/{PR番号}/reviews --paginate \
  --jq '.[] | {id: .id, user: .user.login, state: .state, submitted_at: .submitted_at}'

# 特定のレビューIDに紐づくインラインコメントを取得
gh api repos/{owner}/{repo}/pulls/{PR番号}/reviews/{レビューID}/comments \
  --jq '.[] | {id: .id, path: .path, line: .line, body: .body}'

# レビュー本文（body）を取得（人間レビュアーの場合に重要）
gh api repos/{owner}/{repo}/pulls/{PR番号}/reviews/{レビューID} \
  --jq '{id: .id, state: .state, body: .body, user: .user.login}'

# 最新のCopilotレビューIDを取得してコメントを表示
# ※ --paginateでは配列操作（[...] | last）が各ページに適用されるため、tail -1を使用
REVIEW_ID=$(gh api repos/{owner}/{repo}/pulls/{PR番号}/reviews --paginate \
  --jq '.[] | select(.user.login | contains("copilot")) | .id' | tail -1)
gh api repos/{owner}/{repo}/pulls/{PR番号}/reviews/$REVIEW_ID/comments
```

**注意:** 人間レビュアー（matsuokashuhei等）は、インラインコメントなしでレビュー本文のみに指摘を記載することがある。レビュー本文が空でないか必ず確認すること。

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
**日本語訳:** <レビューコメントが英語の場合のみ翻訳。日本語の場合はこの行を省略>

**対応:** <修正内容または対応しない理由>

- コミット: https://github.com/{owner}/{repo}/commit/{sha}
- 該当箇所: https://github.com/{owner}/{repo}/blob/{sha}/{file}#L{line}
```

### 再レビューリクエスト

修正コミットをプッシュした後:

```bash
gh api repos/{owner}/{repo}/pulls/{PR番号}/requested_reviewers \
  -X POST -f "reviewers[]=copilot-pull-request-reviewer[bot]"
```

### レビュー状態確認

#### 方法1: reviewRequests（シンプル）

```bash
gh pr view {PR番号} --json reviewRequests --jq '.reviewRequests[].login'
```

- `copilot-pull-request-reviewer[bot]`が表示される → レビュー待ち
- 表示されない → レビュー開始済みまたは完了

⚠️ **注意**: レビュー開始後は`reviewRequests`から消えるため、この方法では「レビュー中」と「レビュー完了」を区別できない。

#### 方法2: タイムラインイベント比較（正確）

`copilot_work_started`イベントと最新レビューのタイムスタンプを比較:

```bash
# レビュー開始時刻を取得（--paginateで全件取得、tail -1で最後を取得）
STARTED=$(gh api repos/{owner}/{repo}/issues/{PR番号}/timeline --paginate \
  --jq '.[] | select(.event == "copilot_work_started") | .created_at' | tail -1)

# 最新レビュー完了時刻を取得（--paginateで全件取得、tail -1で最後を取得）
REVIEWED=$(gh api repos/{owner}/{repo}/pulls/{PR番号}/reviews --paginate \
  --jq '.[] | select(.user.login | contains("copilot")) | .submitted_at' | tail -1)

# 判定
if [ -z "$STARTED" ]; then
  echo "Copilotレビュー未開始"
elif [ -z "$REVIEWED" ] || [[ "$STARTED" > "$REVIEWED" ]]; then
  echo "Copilotがレビュー中..."
else
  echo "レビュー完了"
fi
```

#### 判定ロジック

| `copilot_work_started` | 最新レビュー時刻 | 結果 |
|------------------------|-----------------|------|
| なし | - | 未開始 |
| あり | なし | レビュー中 |
| あり | 開始より前 | レビュー中 |
| あり | 開始より後 | 完了 |

### レビュー監視スクリプト

自動的にレビュー完了を監視し、新しいコメントを検出する:

```bash
# 現在の最新レビュー時刻を記録（--paginateで全件取得、tail -1で最後を取得）
LAST_REVIEW=$(gh api repos/{owner}/{repo}/pulls/{PR番号}/reviews --paginate \
  --jq '.[] | select(.user.login | contains("copilot")) | .submitted_at' | tail -1)

# 30秒おきに最大10分間監視
for i in {1..20}; do
  echo "Check $i/20..."

  # タイムラインイベント方式で状態確認（--paginateで全件取得、tail -1で最後を取得）
  STARTED=$(gh api repos/{owner}/{repo}/issues/{PR番号}/timeline --paginate \
    --jq '.[] | select(.event == "copilot_work_started") | .created_at' | tail -1)
  REVIEWED=$(gh api repos/{owner}/{repo}/pulls/{PR番号}/reviews --paginate \
    --jq '.[] | select(.user.login | contains("copilot")) | .submitted_at' | tail -1)

  if [ -z "$STARTED" ]; then
    echo "Copilotレビュー未開始"
    break
  elif [ -z "$REVIEWED" ] || [[ "$STARTED" > "$REVIEWED" ]]; then
    echo "Copilotがレビュー中..."
  else
    # 新しいレビューがあるか確認
    if [ "$REVIEWED" != "$LAST_REVIEW" ]; then
      echo "新しいレビューを検出: $REVIEWED"
      break
    else
      echo "レビュー完了（新規コメントなし）"
      break
    fi
  fi

  sleep 30
done
```

- 10分経過しても状態が変わらない場合は確認を終了
- 新しいコメントがあれば対応し、再度プッシュ

## PRステータス監視

```bash
gh pr view <PR番号>              # PRの状態を確認
gh pr checks <PR番号>            # CIチェックの状況を確認
gh api repos/{owner}/{repo}/pulls/{PR番号}/reviews   # レビュー一覧確認
```

すべてのチェックがパスし、レビュー承認を得るまで対応を続ける。
