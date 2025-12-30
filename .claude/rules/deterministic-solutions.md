# 決定的な解決策を優先する

非同期処理やタイミングに依存する問題を解決する際のルール。

## 原則

**時間ベースの回避策よりも、イベント駆動の決定的なアプローチを優先する。**

## 避けるべきパターン

```swift
// NG: 任意の遅延時間に依存
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    doSomething()
}

// NG: マジックナンバーによる待機
Thread.sleep(forTimeInterval: 0.5)
await Task.sleep(nanoseconds: 100_000_000)
```

### 問題点

- 遅延時間は環境によって不十分な場合がある
- 必要以上に待機する可能性がある
- 根本原因を隠蔽する
- テストが困難

## 推奨パターン

```swift
// OK: デリゲートコールバック
func windowDidBecomeKey(_ notification: Notification) {
    focusTextField()
}

// OK: NotificationCenterによる通知
NotificationCenter.default.publisher(for: .someEvent)
    .sink { _ in doSomething() }

// OK: Combineによるリアクティブな状態監視
$isReady
    .filter { $0 }
    .first()
    .sink { _ in doSomething() }

// OK: async/awaitによる明示的な待機
await someAsyncOperation()
doSomething()
```

### 利点

- 実際の状態変化に基づいて動作
- 環境に依存しない
- 意図が明確
- テスト可能

## 適用例

| シナリオ | 避ける | 推奨 |
|---------|--------|------|
| ウィンドウ表示後の処理 | `asyncAfter` | `windowDidBecomeKey` |
| View表示後の処理 | `asyncAfter` | `onAppear` + 通知 |
| データ読み込み完了後 | `sleep` | Completion handler / async-await |
| アニメーション完了後 | `asyncAfter` | `withAnimation` completion |
