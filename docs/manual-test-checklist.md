# Portal 手動テストチェックリスト

このドキュメントは、自動テストでカバーできない機能の手動テスト手順を記載しています。

## 前提条件

- macOS 15.0 (Sequoia) 以上
- Xcode 16.2 以上
- Portal.app がビルド済み

## 1. ステータスバーテスト

### 1.1 ステータスバーアイコン表示

- [x] アプリ起動後、メニューバーにアイコンが表示される
- [x] アクセシビリティ権限がない場合: 警告アイコン (exclamationmark.triangle) が表示される
- [ ] アクセシビリティ権限がある場合: command アイコンが表示される

### 1.2 ステータスバーメニュー

- [x] アイコンをクリックするとメニューが表示される
- [x] メニューに "Settings..." が表示される (Command+, ショートカット表示あり)
- [x] メニューに "Quit Portal" が表示される (Command+Q ショートカット表示あり)
- [x] アクセシビリティ権限がない場合: "Grant Accessibility Permission..." が表示される

### 1.3 メニュー項目の動作

- [ ] "Settings..." をクリックすると設定ウィンドウが開く
- [ ] "Quit Portal" をクリックするとアプリが終了する
- [ ] "Grant Accessibility Permission..." をクリックするとシステム設定が開く

## 2. ホットキーテスト

### 2.1 パネル表示 (Option+Space)

- [ ] Option+Space を押すとコマンドパレットが表示される
- [ ] アクセシビリティ権限がある状態で動作確認
- [ ] 既にパネルが表示されている場合、Option+Space で非表示になる

### 2.2 パネル非表示 (Escape)

- [x] パネル表示中に Escape を押すと非表示になる
- [x] 修飾キーなしの Escape のみが有効

### 2.3 権限がない場合のホットキー動作

- [ ] アクセシビリティ権限がない状態で Option+Space を押す
- [ ] 権限リクエストダイアログが表示される
- [ ] 5秒以内に再度押すとビープ音が鳴る（クールダウン中）

## 3. コマンドパレットテスト

### 3.1 UI要素

- [ ] パレットが画面中央上部に表示される
- [ ] 背景にブラー効果がある
- [ ] 角丸の枠で表示される
- [ ] ドラッグで移動できる

### 3.2 検索フィールド

- [ ] 検索フィールドが自動フォーカスされる
- [ ] プレースホルダー "Search commands..." が表示される
- [ ] テキスト入力が可能

### 3.3 結果リスト

- [ ] 初期状態で "Type to search commands..." が表示される
- [ ] (検索実装後) 入力に応じて結果がフィルタリングされる

## 4. フォーカス・ウィンドウ管理テスト

### 4.1 フォーカス動作

- [ ] パネル表示時にアプリがアクティブになる
- [ ] パネルがキーウィンドウになる
- [ ] 検索フィールドがファーストレスポンダーになる

### 4.2 パネル非表示トリガー

- [ ] Escape キーでパネルが閉じる
- [ ] パネル外クリックでパネルが閉じる (windowDidResignKey)
- [ ] 他のアプリをアクティブにするとパネルが閉じる

## 5. パフォーマンステスト

### 5.1 起動時間

- [ ] ホットキーからパネル表示まで体感で瞬時（<10ms目標）

### 5.2 リソース使用量

- [ ] Activity Monitor でアイドル時のCPU使用率が0%に近い
- [ ] メモリ使用量が30MB以下

---

## 6. 自動テストのカバレッジ

以下の代表的な項目はXCUITestで自動化済みです（最新の一覧は PortalUITests.swift を参照）:

- [x] パネル表示（testCommandPaletteViewExists）
- [x] Escapeキーでパネル非表示（testEscapeKeyHidesPanel）
- [x] 検索フィールド存在確認（testSearchFieldExists）
- [x] 検索フィールドプレースホルダー（testSearchFieldHasPlaceholder）
- [x] 検索フィールドフォーカス（testSearchFieldHasFocusOnLaunch）
- [x] 検索フィールド入力（testSearchFieldAcceptsInput）
- [x] 結果リスト存在確認（testResultsListExists）

---

## テスト記録

| 項目 | 値 |
|------|-----|
| テスト実行日 | |
| テスト実行者 | |
| macOS バージョン | |
| Portal バージョン | |
| 結果 | Pass / Fail |

## 既知の制限事項

### XCUITest 初回テストタイムアウト

XCUITestフレームワークの初期化に60-90秒かかるため、最初に実行されるテストがタイムアウトする場合があります。
これはXCUITestの既知の制限であり、Portalアプリのバグではありません。

**回避策:**
- ローカル開発: テストを2回連続実行すると、2回目は全テスト通過
- CI/CD: `-retry-tests-on-failure` オプションを使用

```bash
# 失敗したテストを自動リトライ
xcodebuild -project Portal.xcodeproj -scheme Portal test -retry-tests-on-failure
```

## 備考
