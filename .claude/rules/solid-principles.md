# SOLID原則

オブジェクト指向設計の5つの基本原則。保守性・拡張性・テスト容易性の高いコードを書くために遵守する。

## S: 単一責任の原則 (Single Responsibility Principle)

**クラスは1つの責任のみを持つべき。変更理由は1つだけであるべき。**

```swift
// NG: 複数の責任を持つ
class MenuItemManager {
    func fetchMenuItems() -> [MenuItem] { ... }
    func filterItems(_ items: [MenuItem], query: String) -> [MenuItem] { ... }
    func saveToCache(_ items: [MenuItem]) { ... }
    func formatForDisplay(_ item: MenuItem) -> String { ... }
}

// OK: 責任ごとに分離
class MenuCrawler {
    func fetchMenuItems() -> [MenuItem] { ... }
}

class FuzzySearch {
    func filter(_ items: [MenuItem], query: String) -> [MenuItem] { ... }
}

class MenuItemCache {
    func save(_ items: [MenuItem]) { ... }
}
```

## O: 開放閉鎖の原則 (Open/Closed Principle)

**拡張に対して開いており、修正に対して閉じているべき。**

```swift
// NG: 新しい検索アルゴリズム追加時に既存コードを修正
class SearchService {
    func search(_ query: String, type: SearchType) -> [MenuItem] {
        switch type {
        case .fuzzy: return fuzzySearch(query)
        case .exact: return exactSearch(query)
        // 新しいタイプを追加するたびにここを修正
        }
    }
}

// OK: プロトコルで拡張可能に
protocol SearchAlgorithm {
    func search(_ query: String, in items: [MenuItem]) -> [MenuItem]
}

class FuzzySearchAlgorithm: SearchAlgorithm { ... }
class ExactSearchAlgorithm: SearchAlgorithm { ... }
// 新しいアルゴリズムは新クラスを追加するだけ
```

## L: リスコフの置換原則 (Liskov Substitution Principle)

**サブタイプは基底タイプと置換可能であるべき。**

```swift
// NG: サブクラスが基底クラスの契約を破る
class MenuItem {
    func execute() { ... }
}

class DisabledMenuItem: MenuItem {
    override func execute() {
        fatalError("Cannot execute disabled item") // 契約違反
    }
}

// OK: 適切な型階層
protocol Executable {
    func execute()
}

struct EnabledMenuItem: Executable {
    func execute() { ... }
}

struct DisabledMenuItem {
    // executeを持たない
}
```

## I: インターフェース分離の原則 (Interface Segregation Principle)

**クライアントは使用しないメソッドへの依存を強制されるべきではない。**

```swift
// NG: 大きすぎるプロトコル
protocol MenuService {
    func crawl() -> [MenuItem]
    func search(_ query: String) -> [MenuItem]
    func execute(_ item: MenuItem)
    func cache(_ items: [MenuItem])
}

// OK: 役割ごとに分離
protocol MenuCrawling {
    func crawl() -> [MenuItem]
}

protocol MenuSearching {
    func search(_ query: String, in items: [MenuItem]) -> [MenuItem]
}

protocol MenuExecuting {
    func execute(_ item: MenuItem)
}
```

## D: 依存性逆転の原則 (Dependency Inversion Principle)

**上位モジュールは下位モジュールに依存すべきではない。両者は抽象に依存すべき。**

```swift
// NG: 具象クラスに直接依存
class CommandPaletteViewModel {
    private let crawler = MenuCrawler() // 具象に依存

    func loadItems() {
        let items = crawler.fetchMenuItems()
    }
}

// OK: プロトコルを介して依存
protocol MenuCrawling {
    func fetchMenuItems() async -> [MenuItem]
}

class CommandPaletteViewModel {
    private let crawler: MenuCrawling // 抽象に依存

    init(crawler: MenuCrawling) {
        self.crawler = crawler
    }
}

// テスト時にモックを注入可能
class MockMenuCrawler: MenuCrawling {
    func fetchMenuItems() async -> [MenuItem] {
        return [MenuItem(title: "Test")]
    }
}
```

## 適用ガイドライン

| 原則 | 適用タイミング | 注意点 |
|------|---------------|--------|
| SRP | クラス設計時 | 過度な分割は避ける |
| OCP | 機能拡張が予想される箇所 | 予測不能な拡張に備えすぎない |
| LSP | 継承・プロトコル準拠時 | Swiftでは構造体+プロトコルを優先 |
| ISP | プロトコル定義時 | 1-3メソッド程度が目安 |
| DIP | テスト容易性が必要な箇所 | 全てに適用する必要はない |

## 実用的な判断基準

- **現在の要件を満たす最小限の設計**を優先する
- 将来の拡張のために**現時点で必要ない抽象化は避ける**
- テストが困難な場合に**DIPを適用**する
- クラスが大きくなってきたら**SRPを検討**する
