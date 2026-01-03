# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

PortalはmacOS向けUniversal Command Palette。Accessibility APIを使用してアクティブアプリのメニュー項目を検索・実行する。

- **デフォルトホットキー**: Option+Space（設定画面で変更可能）
- **MVPスコープ**: メニューコマンド検索・実行 + ウィンドウ要素ナビゲーション

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
│   ├── Notifications.swift    # アプリ全体の通知名定義
│   └── TestConfiguration.swift # テスト用起動引数設定
├── Models/
│   ├── MenuItem.swift         # コマンド項目のデータモデル（メニュー/ウィンドウ）
│   └── CommandExecutionError.swift # 実行エラー型
├── HintMode/
│   ├── HintLabel.swift            # ヒントラベルのデータモデル
│   ├── HintLabelGenerator.swift   # A-Z, AA-AZ式ラベル生成
│   ├── HintOverlayView.swift      # SwiftUIラベル描画
│   ├── HintOverlayWindow.swift    # オーバーレイウィンドウ管理
│   └── HintModeController.swift   # ヒントモード全体制御
├── Services/
│   ├── HotkeyManager.swift    # 設定可能なホットキー検出
│   ├── AccessibilityService.swift  # 権限チェック・リクエスト
│   ├── AccessibilityHelper.swift   # 位置情報取得ユーティリティ
│   ├── MenuCrawler.swift      # メニューバー走査サービス
│   ├── WindowCrawler.swift    # ウィンドウ要素走査サービス（サイドバー/ツールバー/コンテンツ）
│   ├── FuzzySearch.swift      # スコアベース曖昧検索
│   └── CommandExecutor.swift  # コマンド実行（メニュー/ウィンドウ対応）
├── Settings/
│   ├── HotkeyConfiguration.swift   # ホットキー設定モデル
│   └── SettingsView.swift          # 設定画面UI
├── Testing/
│   └── MockMenuItemFactory.swift # テスト用モックMenuItem生成
└── UI/
    ├── PanelController.swift  # NSPanel + パネル管理
    ├── CommandPaletteView.swift    # ルートビュー
    ├── CommandPaletteViewModel.swift # 状態管理
    ├── FilterSegmentView.swift     # タイプ別絞り込みセグメント
    ├── SearchFieldView.swift       # 検索フィールド
    ├── FocusableTextField.swift    # NSTextField wrapper
    ├── ResultsListView.swift       # 結果リスト
    └── VisualEffectBlur.swift      # ブラー背景
```

## 実装の要点

### Accessibility API
- [x] App Sandboxを無効化（#43）
- [x] `AXIsProcessTrusted()` 権限チェック（#47）
- [x] `AXUIElementCreateApplication()` アプリ要素取得（#48）
- [x] `kAXMenuBarAttribute` メニュー走査（#48）
- [x] `AXUIElementPerformAction()` 実行（#50）

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
- [x] ホットキー設定変更（#51）
- [x] @AppStorage永続化（#51）

### 検索・実行
- [x] FuzzySearch実装（#49）
- [x] 50msデバウンス（#49）
- [x] Unicode/CJK対応（#74）
- [x] キーボードナビゲーション（#50）
- [x] メニュー実行（#50）

### ウィンドウ要素サポート
- [x] `CommandType` enum（menu/window）（#84, #101）
- [x] `WindowCrawler` 統合ウィンドウ要素走査（#101）
- [x] `kAXMainWindowAttribute` ウィンドウ取得（#84）
- [x] サイドバー（`AXOutline`/`AXSourceList`/`AXRow`）走査（#84）
- [x] ツールバー/セグメントコントロール（`AXToolbar`/`AXSegmentedControl`）走査（#95, #101）
- [x] コンテンツ領域（`AXButton`/`AXGroup`/`AXRadioButton`）走査（#91, #95）
- [x] タイプ別アイコン表示（#84）
- [x] タイプ別フィルタ（Cmd+1/2）（#89, #101）

### ヒントモード（Vimiumライク）
- [x] 単独Fキーでヒントモード起動（#104）
- [x] `WindowCrawler`で操作可能要素取得（#104）
- [x] `kAXPositionAttribute`/`kAXSizeAttribute`で位置取得（#104）
- [x] A-Z, AA-AZ式ラベル生成（#104）
- [x] オーバーレイウィンドウでラベル表示（#104）
- [x] キー入力で要素選択・実行（#104）
- [x] ESCで終了、Backspaceで入力クリア（#104）

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
├── CommandPaletteViewModelTests.swift   # ViewModelテスト
├── FuzzySearchTests.swift               # 検索アルゴリズムテスト
├── HintLabelGeneratorTests.swift        # ヒントラベル生成テスト
├── HotkeyConfigurationTests.swift       # ホットキー設定テスト
└── MenuItemTests.swift                  # MenuItemテスト

PortalUITests/
├── PortalUITests.swift                  # パネルUIテスト（7テスト）
├── ScrollBehaviorUITests.swift          # スクロール動作テスト（5テスト）
└── PortalUITestsLaunchTests.swift       # 起動テスト

docs/
└── manual-test-checklist.md             # 手動テストチェックリスト
```

### テストコマンド

```bash
# 全テスト実行（Swift Testing + XCUITest）
xcodebuild -project Portal.xcodeproj -scheme Portal test

# 失敗したテストを自動リトライ（XCUITest初回タイムアウト対策）
xcodebuild -project Portal.xcodeproj -scheme Portal test -retry-tests-on-failure

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
| `--use-mock-menu-items=<count>` | モックメニュー項目を使用（スクロールテスト用） |

## ルール

詳細は `.claude/rules/` を参照。
