# GitHub Issue管理ルール

## Sub-Issues（子Issue）の作成方法

親子関係のあるIssueを作成する場合は、GitHubのネイティブSub-Issues機能を使用する。

**正しい方法:**
1. 親Issueと子Issueをそれぞれ個別に作成
2. GitHubのUIでSub-Issues関係を設定
3. 参考: https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-sub-issues

**禁止事項:**
- Issue本文に `**Parent Issue:** #XX` のような手動参照を記載しない
- Issue本文に `## Sub-Issues` セクションとチェックリストを手動で記載しない

**理由:**
- GitHubのネイティブSub-Issues機能を使うと、UIで親子関係が自動的に表示される
- 手動参照は二重管理になり、同期が取れなくなる
