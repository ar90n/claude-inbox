# 開発ガイドライン: claude-inbox

## 1. 言語・スタイル

### 1.1 Bash スクリプト

- **シェバン:** `#!/bin/bash`
- **安全設定:** 全スクリプトの先頭に `set -euo pipefail`
- **POSIX 互換:** 可能な限り POSIX sh 互換の構文を使用
  - 例外: `declare -A`（連想配列）は claude-inbox のワーカー管理で使用

### 1.2 コーディング規約

```bash
# 変数名: snake_case
local task_file session_id worker_id

# 関数名: snake_case（プレフィックス付き）
task_claim()
task_complete()
observe()

# 定数: UPPER_SNAKE_CASE
CLAUDE_INBOX
WORKER_ID
SKILLS_DIR

# ログ関数: log()
log() { printf '[%s] [%s] %s\n' "$(date -Is)" "$WORKER_ID" "$*" >&2; }
```

### 1.3 インデント

- **インデント:** スペース4つ
- **行の長さ:** 100文字目安（厳密な制限なし）

### 1.4 コメント

```bash
# ファイルヘッダー: 役割と使い方を簡潔に
#!/bin/bash
# claude-inbox-worker: inbox からタスクを取得して claude で実行する

# セクションコメント: --- で区切り
# --- メタデータ抽出 ---

# 関数コメント: 直前に目的を記述
# claim: new/ から1件取得して cur/$WORKER_ID/ に移動
task_claim() {
```

---

## 2. アトミック操作パターン

### 2.1 基本パターン: write-to-tmp + mv

全てのファイル操作はこのパターンに従う:

```bash
# 1. tmp/ に書き込み（この時点では他プロセスから見えない）
printf '%s\n' "$content" > "$CLAUDE_INBOX/tmp/$id.file"

# 2. 目的ディレクトリに mv（rename(2) = カーネルレベルでアトミック）
mv "$CLAUDE_INBOX/tmp/$id.file" "$CLAUDE_INBOX/new/$id.file"
```

### 2.2 禁止パターン

```bash
# NG: 直接 new/ に書き込む（書き込み途中のファイルが見える）
printf '%s\n' "$content" > "$CLAUDE_INBOX/new/$id.file"

# NG: flock を使う（ロックファイル管理のバグを排除するため）
flock /tmp/lockfile command

# NG: echo で書き込む（末尾改行の挙動がシェル依存）
echo "$content" > file  # printf '%s\n' を使う
```

### 2.3 排他制御

```bash
# mv が成功した worker が勝ち
if mv "$task" "$cur_dir/$bname" 2>/dev/null; then
    # 獲得成功
else
    # 他 worker が先取り → リトライ
fi
```

---

## 3. エラーハンドリング

### 3.1 基本方針

- `set -euo pipefail` でエラーを即座に検出
- trap EXIT/INT/TERM でクリーンアップ
- curl 失敗は `|| true` でプロセスを止めない（監視通知など）

### 3.2 パターン

```bash
# 外部コマンドの失敗をキャッチ
result=$(command 2>&1) || rc=$?

# 環境変数の必須チェック
: "${CLAUDE_INBOX:?CLAUDE_INBOX is not set}"

# ファイル存在チェック
[ -f "$task_file" ] || { echo "ERROR: $task_file not found" >&2; return 2; }

# 通知の失敗は無視（プロセスを止めない）
curl -sf ... >/dev/null 2>&1 || true
```

### 3.3 終了コード

| コード | 意味 | 使用場面 |
|---|---|---|
| 0 | 成功 | 正常完了 |
| 1 | 一般エラー | タスクなし、処理失敗 |
| 2 | 使用方法エラー | 引数不正、ファイル未存在 |

---

## 4. テスト方針

### 4.1 手動テスト

```bash
# タスク投入テスト
bin/claude-inbox-add "hello world"
ls ~/.claude-inbox/new/

# ワーカーテスト（別ターミナルで）
bin/claude-inbox-worker
# → new/ のタスクが処理され done/ に移動

# ブリッジテスト
TELEGRAM_BOT_TOKEN=xxx bin/claude-inbox-bridge-telegram
# → Telegram メッセージが new/ に投入される
```

### 4.2 アトミック性テスト

```bash
# 複数ワーカーの排他制御テスト
# 同時に複数の claude-inbox-worker を起動し、同じタスクが重複処理されないことを確認
WORKERS=3 bin/claude-inbox
for i in $(seq 1 10); do bin/claude-inbox-add "task $i"; done
# done/ のタスク数が10であることを確認
```

### 4.3 セッション継続テスト

```bash
# セッション ID の決定論的計算
python3 -c "import uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, 'telegram:12345'))"
# → 毎回同じ UUID が出力されること

# --resume フォールバック
sid=$(python3 -c "import uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, 'test:999'))")
claude --session-id "$sid" -p "Remember: my name is Test" --output-format json
claude --resume "$sid" -p "What is my name?" --output-format json
# → 2回目で「Test」と答えること
```

---

## 5. スキル開発ガイドライン

### 5.1 SKILL.md の構造

```markdown
---
name: skill-name
description: >
  This skill should be used when the user asks to "...", "...", or needs to ...
---

# Skill Title

説明テキスト

## Prerequisites
前提条件

## Workflow
手順（コード例付き）

## Error Handling
エラーハンドリング表

## Output
出力形式
```

### 5.2 description の書き方

- エージェントがタスク内容とマッチングするために使用
- ユーザーが言いそうなフレーズを列挙する
- 「This skill should be used when...」で始める

### 5.3 スキルの責務

- スキルはドメイン知識を提供するだけ
- インフラ操作（ファイル移動、プロセス管理）はしない
- 外部 API の呼び出し手順を記述する
- エラーハンドリングの方針を示す

---

## 6. 環境変数

### 6.1 必須

| 変数 | 説明 | デフォルト |
|---|---|---|
| `CLAUDE_INBOX` | Maildir のベースディレクトリ | `~/.claude-inbox` |

### 6.2 オプション（通知系）

| 変数 | 説明 |
|---|---|
| `TELEGRAM_BOT_TOKEN` | エージェント返信用 Bot トークン |
| `TELEGRAM_CHAT_ID` | エージェント返信用 Chat ID |
| `OBSERVE_TELEGRAM_BOT_TOKEN` | システム監視用 Bot トークン |
| `OBSERVE_TELEGRAM_CHAT_ID` | システム監視用 Chat ID |
| `SLACK_WEBHOOK_URL` | Slack Incoming Webhook URL |

### 6.3 オプション（実行系）

| 変数 | 説明 | デフォルト |
|---|---|---|
| `WORKERS` | ワーカー数 | 1 |
| `CLAUDE_INBOX_WORKDIR` | claude -p の作業ディレクトリ | なし（カレント） |
| `GITHUB_TOKEN` | GitHub API 認証トークン | なし |

---

## 7. Git 運用

### 7.1 ブランチ戦略

- `main`: 安定版
- feature ブランチ: 機能開発用

### 7.2 コミットメッセージ

```
<type>: <description>

<body (optional)>
```

type:
- `feat`: 新機能
- `fix`: バグ修正
- `refactor`: リファクタリング
- `docs`: ドキュメント
- `chore`: 雑務（設定変更等）

### 7.3 .gitignore

ランタイムディレクトリ（`$CLAUDE_INBOX`）はリポジトリに含めない。
`.claude/` 内のローカル設定もリポジトリに含めない。

---

## 8. 依存関係

### 8.1 必須

| ツール | 用途 | インストール |
|---|---|---|
| bash | スクリプト実行 | OS 標準 |
| curl | HTTP リクエスト | OS 標準 |
| jq | JSON 処理 | `apt install jq` |
| python3 | uuid5 計算 | OS 標準 |
| claude | AI タスク実行 | Claude Code CLI |

### 8.2 オプション

| ツール | 用途 | インストール |
|---|---|---|
| inotifywait | ファイル監視（Linux） | `apt install inotify-tools` |
| fswatch | ファイル監視（macOS） | `brew install fswatch` |
| nlm | Podcast 生成 | `npm install -g notebooklm-mcp-cli` |
| systemd | デーモン管理 | OS 標準（Linux） |

---

## 9. セキュリティ注意事項

- `--dangerously-skip-permissions` はサーバー環境での自動実行専用
- Bot トークンは環境変数で管理し、ソースコードにハードコードしない
- `.gitignore` でトークンを含むファイルを除外する
- systemd の `NoNewPrivileges`, `ProtectSystem=strict` を有効にする
- `ReadWritePaths` で書き込み可能なパスを最小限に制限する
