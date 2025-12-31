# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

PortalはmacOS向けUniversal Command Palette。Accessibility APIを使用してアクティブアプリのメニュー項目を検索・実行する。

- **デフォルトホットキー**: Option+Space
- **MVPスコープ**: メニューコマンド検索・実行のみ

## 技術スタック

- Swift 5.0 / SwiftUI + AppKit
- Accessibility API (AXUIElement)
- macOS 15.0+ (Sequoia)
- Xcode 16.2+

## ビルドコマンド

```bash
# ビルド
xcodebuild -project Portal.xcodeproj -scheme Portal build

# テスト実行
xcodebuild -project Portal.xcodeproj -scheme Portal test

# 単一テスト実行 (Swift Testing framework)
xcodebuild -project Portal.xcodeproj -scheme Portal test -only-testing:PortalTests/PortalTests/testExample

# クリーンビルド
xcodebuild -project Portal.xcodeproj -scheme Portal clean build
```

ビルド出力先: `~/Library/Developer/Xcode/DerivedData/Portal-*/Build/Products/Debug/Portal.app`

## アーキテクチャ

### 現在の実装

```
Portal/
├── PortalApp.swift            # エントリポイント (NSApplicationDelegateAdaptor)
├── Info.plist                 # LSUIElement = YES
├── Assets.xcassets/
├── App/
│   ├── AppDelegate.swift      # ステータスバー、ホットキー、パネル管理
│   └── TestConfiguration.swift # テスト用起動引数設定
├── Services/
│   ├── HotkeyManager.swift    # Option+Space検出
│   └── AccessibilityService.swift  # 権限チェック・リクエスト
└── UI/
    ├── PanelController.swift  # NSPanel + パネル管理
    ├── CommandPaletteView.swift    # ルートビュー
    ├── CommandPaletteViewModel.swift # 状態管理
    ├── SearchFieldView.swift       # 検索フィールド
    ├── FocusableTextField.swift    # NSTextField wrapper
    ├── ResultsListView.swift       # 結果リスト
    └── VisualEffectBlur.swift      # ブラー背景
```

### 未実装コンポーネント

| ファイル | 目的 | Issue |
|---------|------|-------|
| UI/CommandPaletteViewModel.swift | 状態管理 | #46 |
| Services/MenuCrawler.swift | メニュー走査 | #48 |
| Services/FuzzySearch.swift | 検索アルゴリズム | #49 |
| Models/Command.swift | コマンドProtocol | #50 |
| Models/MenuCommand.swift | メニューコマンド | #50 |
| Settings/SettingsView.swift | 設定画面 | #51 |

## 実装の要点

### Accessibility API
- [x] App Sandboxを無効化（#43）
- [x] `AXIsProcessTrusted()` 権限チェック（#47）
- [ ] `AXUIElementCreateApplication()` アプリ要素取得（#48）
- [ ] `kAXMenuBarAttribute` メニュー走査（#48）
- [ ] `AXUIElementPerformAction()` 実行（#50）

### メニューバーアプリ
- [x] `LSUIElement = YES`（#43）
- [x] `NSStatusItem` メニューバー表示（#44）
- [x] `NSPanel` フローティングUI（#45）
- [x] `NSVisualEffectView` ブラー背景（#45）

### ホットキー登録
- [x] `addGlobalMonitorForEvents`（#45）
- [x] `addLocalMonitorForEvents`（#45）
- [x] Option+Space検出（#45）
- [x] Escapeキーでパネル非表示（#45）

### 検索・実行
- [ ] FuzzySearch実装（#49）
- [ ] 50msデバウンス（#49）
- [ ] キーボードナビゲーション（#50）
- [ ] メニュー実行（#50）

## パフォーマンス目標

| 指標 | 目標 |
|------|------|
| ホットキー→表示 | <10ms |
| メモリ | <30MB |
| CPU（アイドル時） | 0% |

## 開発トラッキング

GitHub Project: https://github.com/users/matsuokashuhei/projects/3

- 親Issue: #53 (Phase 1: MVP)
- 子Issues: #43-#52

## テスト

### テストファイル

```
PortalTests/
├── PortalTests.swift                    # テンプレート
└── CommandPaletteViewModelTests.swift   # ViewModelテスト（5テスト）

PortalUITests/
├── PortalUITests.swift                  # パネルUIテスト（8テスト）
└── PortalUITestsLaunchTests.swift       # 起動テスト

docs/
└── manual-test-checklist.md             # 手動テストチェックリスト
```

### テストコマンド

```bash
# 全テスト実行（Swift Testing + XCUITest）
xcodebuild -project Portal.xcodeproj -scheme Portal test

# ユニットテストのみ
xcodebuild -project Portal.xcodeproj -scheme Portal test -only-testing:PortalTests

# UIテストのみ
xcodebuild -project Portal.xcodeproj -scheme Portal test -only-testing:PortalUITests
```

### テスト用起動引数

| 引数 | 説明 |
|------|------|
| `--show-panel-on-launch` | パネル自動表示（XCUITest用） |
| `--skip-accessibility-check` | 権限チェックスキップ |
| `--disable-panel-auto-hide` | フォーカス喪失時の自動非表示を無効化 |

## ルール

詳細は `.claude/rules/` を参照。
