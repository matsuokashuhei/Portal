# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

PortalはmacOS向けVimiumライクなキーボードナビゲーションツール。Accessibility APIを使用してアクティブアプリのウィンドウ要素をヒントラベルで操作する。

- **デフォルトホットキー**: Fキー（修飾キーなし、設定画面で変更可能）
- **機能**: ウィンドウ要素のヒント表示とクリック

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
│   ├── AppDelegate.swift      # ステータスバー、ホットキー管理
│   ├── Notifications.swift    # アプリ全体の通知名定義
│   └── TestConfiguration.swift # テスト用起動引数設定
├── Models/
│   ├── MenuItem.swift         # ウィンドウ要素のデータモデル
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
│   ├── WindowCrawler.swift    # ウィンドウ要素走査サービス（サイドバー/ツールバー/コンテンツ）
│   └── CommandExecutor.swift  # ウィンドウ要素実行
└── Settings/
    ├── HotkeyConfiguration.swift   # ホットキー設定モデル
    └── SettingsView.swift          # 設定画面UI
```

## 実装の要点

### Accessibility API
- [x] App Sandboxを無効化（#43）
- [x] `AXIsProcessTrusted()` 権限チェック（#47）
- [x] `AXUIElementCreateApplication()` アプリ要素取得（#48）
- [x] `AXUIElementPerformAction()` 実行（#50）

### メニューバーアプリ
- [x] `LSUIElement = YES`（#43）
- [x] `NSStatusItem` メニューバー表示（#44）

### ホットキー登録
- [x] `addGlobalMonitorForEvents`（#45）
- [x] `addLocalMonitorForEvents`（#45）
- [x] Fキーでヒントモード起動（#104, #107）
- [x] ホットキー設定変更（#51, #107）
- [x] @AppStorage永続化（#51）

### ウィンドウ要素サポート
- [x] `WindowCrawler` 統合ウィンドウ要素走査（#101）
- [x] `kAXMainWindowAttribute` ウィンドウ取得（#84）
- [x] サイドバー（`AXOutline`/`AXSourceList`/`AXRow`）走査（#84）
- [x] ツールバー/セグメントコントロール（`AXToolbar`/`AXSegmentedControl`）走査（#95, #101）
- [x] コンテンツ領域（`AXButton`/`AXGroup`/`AXRadioButton`）走査（#91, #95）
- [x] チェックボックス/スイッチ（`AXCheckBox`/`AXSwitch`）実行（#109）

### ヒントモード（Vimiumライク）
- [x] ホットキーでヒントモード起動（#104, #107）
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
├── HintLabelGeneratorTests.swift        # ヒントラベル生成テスト
├── HotkeyConfigurationTests.swift       # ホットキー設定テスト
└── MenuItemTests.swift                  # MenuItemテスト

PortalUITests/
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
| `--skip-accessibility-check` | 権限チェックスキップ |

## ルール

詳細は `.claude/rules/` を参照。
