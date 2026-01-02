# コード品質

PRを作成する前に確認すべき品質チェックリスト。

## 命名の一貫性

**機能を拡張したら、名前も更新する。**

```swift
// NG: メニューとサイドバー両方を扱うのに「menu」という名前
func loadMenuItems() { ... }
var menuItemsResult = ...

// OK: 実際の機能を反映した名前
func loadItems() { ... }
var crawledMenuItems = ...
```

| 変更内容 | 確認事項 |
|---------|---------|
| 機能拡張 | メソッド名、変数名、パラメータ名が新しい機能を反映しているか |
| 型の追加 | 関連するドキュメントコメントが一般化されているか |

## コードの一貫性

**同様の処理は同じパターンで実装する。**

```swift
// NG: メニュー走査では nil 処理があるが、サイドバー走査では省略
if app == nil {
    menuItems = menuCrawler.crawlActiveApplication()  // nil処理あり
}
// サイドバーはappがnilの場合スキップ... ← 一貫性がない

// OK: 両方とも同じパターンで処理
if app == nil {
    menuItems = menuCrawler.crawlActiveApplication()
    sidebarItems = windowCrawler.crawlActiveApplication()
}
```

**確認方法:**
1. 類似の既存コードを検索する
2. edge case（nil、空配列、エラー）の処理を比較する
3. 異なる場合は意図的かどうか確認する

## ドキュメントの追従

**コードを変更したら、関連ドキュメントも更新する。**

```swift
// NG: MenuCrawler固有の説明だが、WindowCrawlerも同様の動作をする
/// The short cache duration (0.5s) in `MenuCrawler` helps mitigate...

// OK: 一般化した説明
/// Crawlers may cache results briefly to improve performance...
```

| 変更内容 | 更新対象 |
|---------|---------|
| 新しいサービス追加 | CLAUDE.md のアーキテクチャセクション |
| 機能拡張 | 関連するドキュメントコメント |
| 新しいテスト追加 | CLAUDE.md のテストセクション |

## 意図的な動作の明示

**バグに見える可能性のある意図的な動作にはコメントを追加する。**

```swift
// NG: 親要素と子要素の両方を追加しているが、重複ではないか疑問が残る
if sidebarItemRoles.contains(role) {
    items.append(item)
}
if hasChildren(element) {
    items.append(contentsOf: crawlChildren(element))
}

// OK: 意図を明示
// Note: Intentionally process both the item and its children.
// Expandable sidebar rows (e.g., collapsible folders) are themselves
// actionable AND contain independent child items. Each has a unique
// path, so no duplicates occur.
if sidebarItemRoles.contains(role) {
    items.append(item)
}
if hasChildren(element) {
    items.append(contentsOf: crawlChildren(element))
}
```

## 未使用コードの削除

**YAGNI原則: 「今必要ないものは作らない」**

```swift
// NG: 将来使うかもしれないヘルパーメソッド
private func getIdentifier(_ element: AXUIElement) -> String? { ... }  // 未使用
private func getActions(_ element: AXUIElement) -> [String] { ... }    // 未使用

// OK: 使用されているメソッドのみ残す
// 必要になった時点で追加する
```

**PR作成前のチェック:**
- 追加したヘルパーメソッドがすべて使用されているか確認
- 未使用のメソッドは削除（必要になったら再追加）

## 重複コードの抽出

**同じロジックが複数箇所に存在する場合は共通化を検討する。**

```swift
// NG: WindowCrawler と CommandExecutor で同じロジック
// WindowCrawler.swift
private func getTitleFromRowChildren(_ element: AXUIElement) -> String? {
    // 50行のロジック...
}

// CommandExecutor.swift
private func getTitleFromChildren(_ element: AXUIElement) -> String? {
    // 同じ50行のロジック...
}

// OK: 共通ユーティリティに抽出
// AccessibilityHelper.swift
enum AccessibilityHelper {
    static func getTitleFromChildren(_ element: AXUIElement) -> String? {
        // 共通ロジック
    }
}
```

**判断基準:**
- 3行以上の同一ロジックが2箇所以上 → 抽出を検討
- 将来的に変更が必要になりそうな箇所 → 抽出を検討
- 現在のPRスコープ外の場合 → Issueを作成して追跡

## PR作成前チェックリスト

- [ ] 新しいメソッド/変数の名前が実際の機能を反映しているか
- [ ] 類似の既存コードと同じパターンで実装しているか
- [ ] 関連するドキュメントコメントを更新したか
- [ ] 意図的だが紛らわしい動作にコメントを追加したか
- [ ] 未使用のコードを削除したか
- [ ] 重複コードがないか確認したか（ある場合はIssue作成）
