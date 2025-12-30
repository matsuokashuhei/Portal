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

```
Portal/
├── App/
│   ├── PortalApp.swift        # エントリポイント (NSApplicationDelegateAdaptor)
│   └── AppDelegate.swift      # ステータスバー、ホットキー、パネル管理
├── UI/
│   ├── PanelController.swift  # NSPanelフローティングウィンドウ
│   ├── CommandPaletteView.swift
│   ├── SearchFieldView.swift
│   └── ResultsListView.swift
├── Services/
│   ├── HotkeyManager.swift    # NSEvent.addGlobalMonitorForEvents
│   ├── AccessibilityService.swift  # AXIsProcessTrusted
│   ├── MenuCrawler.swift      # AXUIElementメニューバー走査
│   └── FuzzySearch.swift
├── Models/
│   ├── Command.swift          # Protocol
│   └── MenuCommand.swift
└── Settings/
    └── SettingsView.swift
```

## 実装の要点

### Accessibility API
- App Sandboxを`project.pbxproj`で無効化が必要
- `AXUIElementCreateApplication()` でアプリ要素取得
- `kAXMenuBarAttribute` でメニュー走査
- `AXUIElementPerformAction(kAXPressAction)` で実行

### メニューバーアプリ
- Info.plistに `LSUIElement = YES`（Dockアイコン非表示）
- `NSStatusItem` でメニューバー表示
- `NSPanel` の `.nonactivatingPanel` スタイルでフローティングUI

### ホットキー登録
- `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)`
- Option+Space (keyCode 49 + .option修飾キー)

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

## ルール

詳細は `.claude/rules/` を参照。
