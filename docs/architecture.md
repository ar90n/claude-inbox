# アーキテクチャ設計書: claude-inbox

## 1. アーキテクチャ概要

### 1.1 設計思想

claude-inbox は以下の原則に基づいて設計されている:

1. **ステートレス**: 受信ブリッジは状態を持たない（DB 不要）
2. **アトミック**: 全ファイル操作は rename(2) によるカーネルレベルのアトミック性
3. **シンプル**: bash + curl + jq + python3（uuid5のみ）、特別なランタイム不要
4. **分離**: エージェント返信とシステム監視は別チャンネル
5. **Progressive Disclosure**: スキルはエージェントが自動選択

### 1.2 システム構成図

```
┌─────────────────────────────────────────────────┐
│                  外部サービス                      │
│  ┌─────────┐  ┌─────────┐  ┌─────────────────┐  │
│  │Telegram  │  │ HN API  │  │ GitHub API      │  │
│  │Bot API   │  │         │  │                 │  │
│  └────┬─────┘  └────┬────┘  └───────┬─────────┘  │
│       │             │               │             │
└───────┼─────────────┼───────────────┼─────────────┘
        │             │               │
┌───────┼─────────────┼───────────────┼─────────────┐
│       │        claude-inbox         │             │
│  ┌────▼─────┐       │               │             │
│  │inbox-recv│  ┌────▼───────────────▼──────────┐  │
│  │(bridge)  │  │  Claude Code Agent            │  │
│  └────┬─────┘  │  ┌──────────┐ ┌────────────┐ │  │
│       │        │  │web-collect│ │notebooklm  │ │  │
│  ┌────▼─────┐  │  └──────────┘ └────────────┘ │  │
│  │  Maildir │  │  ┌──────────┐ ┌────────────┐ │  │
│  │  Queue   │  │  │notify-   │ │create-task │ │  │
│  │  (files) │◄─┤  │telegram  │ │            │ │  │
│  └────┬─────┘  │  └──────────┘ └────────────┘ │  │
│       │        └───────────────────────────────┘  │
│  ┌────▼─────┐       ▲                            │
│  │worker.sh │───────┘                            │
│  └──────────┘                                    │
│       │                                          │
│  ┌────▼──────────┐  ┌──────────────┐             │
│  │claude-inbox.sh│  │lib/observe.sh│──► 監視通知  │
│  │(process mgr)  │  │              │             │
│  └───────────────┘  └──────────────┘             │
└──────────────────────────────────────────────────┘
```

---

## 2. レイヤー構成

### 2.1 レイヤー一覧

| レイヤー | 責務 | コンポーネント |
|---|---|---|
| エントリポイント | プロセス管理 | claude-inbox.sh |
| ブリッジ | 外部チャット → キュー変換 | inbox-recv |
| CLI | ローカルタスク投入 | inbox-add |
| キュー | タスクの永続化・排他制御 | lib/task.sh + Maildir ディレクトリ |
| ワーカー | タスク実行エンジン | worker.sh |
| エージェント | AI タスク実行 | Claude Code CLI + system.md |
| スキル | ドメイン知識 | skills/**/SKILL.md |
| 監視 | システム状態通知 | lib/observe.sh |

### 2.2 依存関係

```
claude-inbox.sh
  └── worker.sh
        ├── lib/task.sh
        ├── lib/observe.sh
        ├── system.md
        └── claude CLI
              └── skills/
                    ├── web-collect
                    ├── notebooklm
                    ├── notify-telegram
                    ├── notify-slack
                    └── create-task
                          └── lib/task.sh

inbox-recv
  ├── lib/task.sh
  └── lib/observe.sh

inbox-add
  └── lib/task.sh
```

---

## 3. データフロー

### 3.1 タスクのライフサイクル

```
[生成]                  [待機]        [処理中]         [完了/失敗]
inbox-recv/inbox-add → tmp/*.task → new/*.task → cur/{wid}/*.task → done/ or failed/
                       (write)     (mv atomic)  (mv atomic)        (mv atomic)
```

### 3.2 ファイルシステム構造

```
$CLAUDE_INBOX/                     # デフォルト: ~/.claude-inbox
├── tmp/                           # 書き込み用一時領域
│   └── {task_id}.task             # 書き込み中のタスク
├── new/                           # 待機中タスク（ワーカーが取得する）
│   └── {priority}.{timestamp}.{hex}.task
├── cur/                           # 処理中タスク
│   └── {worker_id}/
│       └── {task_id}.task
├── done/                          # 完了タスク（ログ）
│   ├── {task_id}.task
│   └── {task_id}.result
├── failed/                        # 失敗タスク
│   ├── {task_id}.task
│   └── {task_id}.result
├── state/                         # ワーカー状態
├── log/                           # ログ
└── .recv-offset-{channel}         # ブリッジのポーリング位置
```

### 3.3 タスクファイル形式

```
[from=UserName channel=telegram chat_id=12345 msg_id=200 session_id=xxxx-xxxx]

ユーザーのメッセージ本文（複数行可）
```

- 1行目: メタデータ（`[` `]` で囲む、key=value スペース区切り）
- 空行
- 本文: ユーザーのプロンプト

---

## 4. 並行性・排他制御

### 4.1 複数ワーカーの排他制御

```
Worker A: find new/ → task.1234.task
Worker B: find new/ → task.1234.task  (同じタスクを発見)

Worker A: mv new/task.1234.task cur/wA/task.1234.task  → 成功 (獲得)
Worker B: mv new/task.1234.task cur/wB/task.1234.task  → 失敗 (ファイルなし)
Worker B: リトライ → 別のタスクを取得
```

- POSIX `mv` は同一FS上で `rename(2)` = カーネルレベルでアトミック
- flock / ロックファイル不要
- 最大3回リトライ（`task_claim()`）

### 4.2 タスク可視性の保証

```
# 書き込み途中のファイルが new/ に見えることはない
printf '%s\n' "$prompt" > "tmp/$id.task"   # tmp/ に書き込み
mv "tmp/$id.task" "new/$id.task"           # atomic: ここで初めて可視化
```

### 4.3 クラッシュ時の挙動

| クラッシュタイミング | 状態 | リカバリ |
|---|---|---|
| tmp/ 書き込み中 | tmp/ にゴミ | 無害、起動時に清掃可能 |
| new/ → cur/ 移動後 | cur/ にタスク | task_recover() で new/ に戻す |
| claude 実行中 | cur/ にタスク | task_recover() で new/ に戻す |
| result 書き込み中 | tmp/ にゴミ + cur/ にタスク | task_recover() で再実行 |
| done/ 移動後 | 完了状態 | リカバリ不要 |

---

## 5. セッション管理アーキテクチャ

### 5.1 決定論的 session_id

```python
# 純粋関数: 同じ入力 → 常に同じ出力
uuid5(NAMESPACE_URL, f"telegram:{chat_id}")
```

- DB不要、ファイル不要、外部ステート不要
- inbox-recv も worker.sh も同じ計算で同じ結果を得る
- チャンネル種別ごとの計算ロジック差し替えが可能

### 5.2 セッションストレージ

```
~/.claude/projects/
  └── {project_hash}/
      └── sessions/
          └── {session_id}   # Claude Code が管理（約30日保持）
```

- Claude Code CLI が自動管理
- claude-inbox は直接操作しない
- `--resume` で自動的にロード

### 5.3 resume フォールバックパターン

```
inbox-recv                    worker.sh
    │                            │
    │  session_id=uuid5(...)     │
    ├────────────────────────────►│
    │                            │
    │                            ├── claude --resume $sid -p "..."
    │                            │     │
    │                            │     ├── 成功 → セッション継続
    │                            │     │
    │                            │     └── 失敗（セッション未存在）
    │                            │           │
    │                            │           └── claude --session-id $sid -p "..."
    │                            │                 └── 新規セッション作成
```

---

## 6. 通知アーキテクチャ

### 6.1 2チャンネル分離

```
┌──────────────────┐     ┌──────────────────┐
│ エージェント返信   │     │ システム監視       │
│                  │     │                  │
│ notify-telegram  │     │ lib/observe.sh   │
│ スキル           │     │                  │
│                  │     │                  │
│ Bot: @MyBot      │     │ Bot: @MonitorBot │
│ Chat: user_chat  │     │ Chat: ops_chat   │
│                  │     │                  │
│ エージェントが判断 │     │ bash が決定的実行  │
└──────────────────┘     └──────────────────┘
```

| 項目 | エージェント返信 | システム監視 |
|---|---|---|
| 実行者 | Claude エージェント | bash (worker.sh, claude-inbox.sh) |
| 判断 | エージェントが自動 | 条件に基づき決定的 |
| 環境変数 | TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID | OBSERVE_TELEGRAM_BOT_TOKEN, OBSERVE_TELEGRAM_CHAT_ID |
| 用途 | タスク結果の返信 | ワーカー死亡、失敗通知 |
| 分離可能 | Yes（別 Bot/Chat を使用可） | Yes |

---

## 7. スキルアーキテクチャ

### 7.1 Progressive Disclosure

```
worker.sh
  │
  ├── claude --add-dir skills/ -p "..."
  │
  └── Claude Agent
        │
        ├── skills/ ディレクトリをスキャン
        │     ├── web-collect/SKILL.md      → frontmatter 読み取り
        │     ├── notebooklm/SKILL.md       → frontmatter 読み取り
        │     ├── notify-telegram/SKILL.md  → frontmatter 読み取り
        │     ├── notify-slack/SKILL.md     → frontmatter 読み取り
        │     └── create-task/SKILL.md      → frontmatter 読み取り
        │
        ├── タスク内容と description をマッチング
        │
        └── 適切なスキルを自動ロード・実行
```

### 7.2 スキルの構造

```
skills/
└── {skill-name}/
    └── SKILL.md          # YAML frontmatter + 手順書
```

frontmatter:
```yaml
---
name: skill-name
description: >
  This skill should be used when...
---
```

---

## 8. デプロイメントアーキテクチャ

### 8.1 systemd 統合

```
systemctl --user
  └── claude-inbox.service
        └── claude-inbox.sh (Type=simple)
              ├── worker.sh (fork, PID tracked)
              ├── worker.sh (fork, PID tracked)
              └── ... (WORKERS=N)
```

### 8.2 環境変数

```
~/.config/environment.d/claude-inbox.conf

CLAUDE_INBOX=/home/user/.claude-inbox
WORKERS=1
CLAUDE_INBOX_WORKDIR=/path/to/workdir
OBSERVE_TELEGRAM_BOT_TOKEN=...
OBSERVE_TELEGRAM_CHAT_ID=...
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...
```

### 8.3 セキュリティ境界

```
systemd sandbox:
  ├── NoNewPrivileges=true
  ├── ProtectSystem=strict
  └── ReadWritePaths=
        ├── ~/.claude-inbox    (Maildir)
        ├── ~/.claude          (セッションストレージ)
        └── $XDG_RUNTIME_DIR   (ソケット等)
```

---

## 9. 技術スタック

| カテゴリ | 技術 | 用途 |
|---|---|---|
| 言語 | Bash (POSIX sh 互換) | 全コンポーネント |
| AI | Claude Code CLI (`claude`) | タスク実行 |
| メッセージング | Telegram Bot API | 受信・通知 |
| キュー | Maildir (ファイルシステム) | タスク管理 |
| プロセス管理 | systemd | デーモン化 |
| ファイル監視 | inotifywait / fswatch | タスク到着通知（オプション） |
| JSON処理 | jq | API レスポンスのパース |
| UUID生成 | Python3 (uuid モジュール) | session_id 計算 |
| HTTP | curl | API 呼び出し |
| Podcast | nlm CLI (notebooklm-mcp-cli) | 音声生成 |

---

## 10. 設計判断の記録

| 判断 | 採用 | 却下案 | 理由 |
|---|---|---|---|
| コンテキスト管理 | Claude session (`--resume`) | task_id + read-task | Claude が覚えてるので不要 |
| セッション単位 | 1 chat_id = 1 session | スレッド単位 | Telegram にスレッドがない |
| session_id 計算 | uuid5 (決定論的) | DB に保存 | ステートレスが最良 |
| ステート管理 | なし（完全ステートレス） | SQLite (bridge.db) | chat_id → session_id は計算で出る |
| スキル選択 | エージェント自動判断 | タスクに --skill 指定 | Claude Code と同じ progressive disclosure |
| 通知 | 2チャンネル分離 | 1チャンネル | エージェント返信とシステム監視は別の関心事 |
| 排他制御 | mv(2) rename | flock | rename はカーネルアトミック、ロック管理不要 |
| 結果の永続化 | Claude session + done/ ログ | done/ のみ | session が primary、ファイルは backup |
| reply-to チェーン | 不採用 | uuid5("telegram:{chat_id}:{origin_msg_id}") | origin_msg_id を取得できない |
| Bot message に session_id 埋め込み | 不採用 | 不可視テキスト | ハック、メッセージ編集で壊れる |
