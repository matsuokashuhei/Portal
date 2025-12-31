# Issue駆動開発

GitHub Issueに取り組む際のルール。

## ブランチ作成

mainブランチから新しいブランチを作成する。

- 命名規則: `feature/#<issue番号>-<簡潔な説明>` または `fix/#<issue番号>-<簡潔な説明>`
- 例: `feature/#43-project-settings`

## コミットメッセージ

- Issue番号を含める（例: `#43 Add project settings`）

## CLAUDE.md更新

開発中にCLAUDE.mdの更新が必要か確認し、必要であれば同じPRに含める。

- 新しいファイルやディレクトリ追加時: アーキテクチャセクションを更新
- 新しいコマンド追加時: ビルドコマンドセクションを更新
- 新しい技術的要点がある場合: 実装の要点セクションを更新

## テスト

### テストコードの作成

新機能や修正には必ずテストコードを作成する。

- ユニットテスト: ビジネスロジック、ViewModel、Serviceクラス
- UIテスト: ユーザーインタラクション、画面遷移

### コミット前の確認

コミット前に必ずすべてのテストを実行し、パスすることを確認する。

```bash
# 全テスト実行
xcodebuild -project Portal.xcodeproj -scheme Portal test -retry-tests-on-failure
```

### テストが失敗した場合

- 失敗したテストを修正してから再度コミットする
- 既存テストを壊す変更は許容しない
