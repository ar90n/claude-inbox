# 機能設計書: claude-inbox

## 1. システムフロー

### 1.1 全体フロー

```
Telegram Chat (chat_id=12345)
  ↕ Bot API (getUpdates / sendMessage)
inbox-recv (bridge, ステートレス)
  ↓ task_submit()
new/*.task
  ↓ task_claim() (atomic mv)
cur/{wid}/*.task → worker.sh → claude -p / --resume
  ↓ task_complete() / task_fail()
done/*.task + done/*.result  (or failed/)
  ↓ notify-telegram スキル (エージェントが実行)
Telegram Chat (結果を返信)
```

### 1.2 メッセージ受信フロー

1. ユーザーが Telegram Bot にメッセージを送信
2. `inbox-recv` が `getUpdates` ロングポーリングで受信
3. `chat_id` から `session_id` を決定論的に計算
   ```
   session_id = uuid5(NAMESPACE_URL, "telegram:{chat_id}")
   ```
4. メタデータ付きタスクファイルを生成
5. `task_submit()` で `tmp/` → `new/` にアトミック移動

### 1.3 タスク実行フロー

1. `worker.sh` のメインループが `task_claim()` を呼び出し
2. `new/` から最古のタスクを `cur/{worker_id}/` にアトミック移動
3. タスクファイルからメタデータを抽出（session_id, chat_id 等）
4. Claude Code CLI の引数を組み立て:
   - まず `--resume $session_id` を試行
   - 失敗時は `--session-id $session_id` にフォールバック
   - `--system-prompt`, `--add-dir skills/`, `--dangerously-skip-permissions` を付与
5. 実行結果に応じて `task_complete()` or `task_fail()` を呼び出し
6. 失敗時は `observe()` でシステム監視通知

### 1.4 結果通知フロー

1. Claude エージェントが `notify-telegram` スキルを自動選択
2. `TELEGRAM_BOT_TOKEN` と `TELEGRAM_CHAT_ID`（メタデータから取得）で送信
3. 4096文字超はパラグラフ境界で分割送信
4. Markdown v1 でフォーマット

---

## 2. コンポーネント詳細設計

### 2.1 inbox-recv（受信ブリッジ）

**役割:** チャットアプリ → タスクキューのブリッジ

**入力:** Telegram Bot API の getUpdates レスポンス

**出力:** タスクファイル（`new/*.task`）

**メタデータ形式（v3.1）:**
```
[from=UserName channel=telegram chat_id=12345 msg_id=200 session_id=xxxx-xxxx]

ユーザーのメッセージ本文
```

| フィールド | 必須 | 説明 |
|---|---|---|
| `from` | Yes | ユーザー名 |
| `channel` | Yes | チャンネル種別（telegram） |
| `chat_id` | Yes | チャット ID |
| `msg_id` | No | ユーザーのメッセージ ID（reply_to 用） |
| `session_id` | Yes | 決定論的に計算されたセッション ID |

**旧フィールド（v3.1 で廃止）:**
- `origin_msg_id`: 不要（chat_id 単位でセッション固定のため）
- `resume`: 不要（worker 側で自動判定するため）

**処理フロー:**
1. `TELEGRAM_BOT_TOKEN` の存在確認
2. offset ファイルから前回位置を読み込み
3. `getUpdates?offset={offset}&timeout=30` でポーリング
4. 各 update から text, chat_id, msg_id, user_name を抽出
5. session_id を計算: `uuid5(NAMESPACE_URL, "telegram:{chat_id}")`
6. `task_submit()` でキューに投入
7. offset を更新

### 2.2 worker.sh（ワーカー）

**役割:** タスクの取得・実行・結果保存

**メインループ:**
```
while true:
  wait_for_task() (inotifywait / fswatch / sleep)
  task_file = task_claim(worker_id)
  metadata = extract_meta(task_file)
  args = build_claude_args(metadata)
  result = execute_claude(args)
  if success: task_complete(task_file, result)
  else: task_fail(task_file, result); observe(error)
```

**--resume フォールバック（v3.1 新規）:**
```bash
# session_id がある場合:
# 1. まず --resume を試行（既存セッション）
# 2. 失敗したら --session-id で新規作成
if claude --resume "$session_id" -p "..." 2>/dev/null; then
    # 成功
elif claude --session-id "$session_id" -p "..."; then
    # 新規セッション作成
fi
```

**Claude CLI 引数:**

| 引数 | 値 | 条件 |
|---|---|---|
| `-p` | タスク内容 | 常に |
| `--resume` | session_id | セッション存在時 |
| `--session-id` | session_id | resume 失敗時 |
| `--dangerously-skip-permissions` | - | 常に |
| `--system-prompt` | prompts/system.md の内容 | 存在時 |
| `--add-dir` | skills/ | skills/ 存在時 |

**メタデータ抽出:**
```bash
extract_meta() {
    local content="$1" key="$2"
    echo "$content" | head -1 | grep -oP "${key}=\K[^ \]]*" || true
}
```

### 2.3 lib/task.sh（タスク操作ライブラリ）

**アトミック性の保証:** 全操作は write-to-tmp + mv(2) rename パターン

| 関数 | 操作 | アトミック性 |
|---|---|---|
| `task_claim()` | new/ → cur/{wid}/ | mv が成功した worker が獲得 |
| `task_complete()` | result → tmp/ → done/, task → done/ | rename(2) |
| `task_fail()` | result → tmp/ → failed/, task → failed/ | rename(2) |
| `task_submit()` | content → tmp/ → new/ | rename(2) |
| `task_recover()` | cur/{wid}/*.task → new/ | 孤児回収 |

**タスク ID 命名規則:** `{priority}.{YYYYMMDD-HHMMSS}.{random_hex}`
- priority: 0=最高、9=最低、default=5
- timestamp: ソート順（FIFO）
- random: 衝突回避（4バイト hex）

### 2.4 lib/observe.sh（システム監視通知）

**役割:** エージェント非経由の決定的な監視通知

**環境変数:**
- `OBSERVE_TELEGRAM_BOT_TOKEN`: 監視用 Bot トークン
- `OBSERVE_TELEGRAM_CHAT_ID`: 監視用チャット ID

**フォールバック:** 環境変数未設定時は stderr 出力のみ

**通知対象イベント:**
- ワーカー死亡・再起動
- タスク失敗
- システム起動・停止
- 認証切れ検出（nlm 等）

### 2.5 claude-inbox.sh（エントリポイント）

**役割:** ワーカープロセスの管理

**機能:**
- `WORKERS=N` 環境変数でワーカー数を指定
- 各ワーカーをバックグラウンドプロセスとして起動
- 5秒間隔で死亡チェック → 自動再起動
- SIGINT/SIGTERM で全ワーカーを停止

### 2.6 prompts/（エージェントプロンプト）

**役割:** 本番エージェントの振る舞いを定義（`prompts/system.md` + `prompts/CLAUDE.md`）

**主要ルール:**
1. セッション継続性: `--resume` 時は前のターンの文脈がある
2. 自律実行: 確認を求めずに完了まで遂行
3. スキル自動選択: description マッチでエージェントが判断

---

## 3. スキル詳細設計

### 3.1 web-collect

**トリガー:** 「ニュース集めて」「HN のトップ教えて」「GitHub Trending」等

**データソース:**

| ソース | API | 認証 | レート制限 |
|---|---|---|---|
| Hacker News | Firebase API | 不要 | なし |
| GitHub Trending | Search API | 任意（`$GITHUB_TOKEN`） | 10 req/min (認証なし), 30 req/min (認証あり) |

**出力:** Markdown（HN Top 10 + GitHub Trending + Summary）

### 3.2 notebooklm

**トリガー:** 「Podcastにして」「音声にして」等

**ワークフロー:**
1. `nlm notebook create --title "..."` → notebook_id
2. `nlm source add $id --text "..."` → ソース追加
3. 10-30秒待機（ソース処理）
4. `nlm audio create $id --confirm` → 音声生成（2-5分）
5. `nlm audio get $id` → 音声 URL 取得

**エラーハンドリング:**
- 401: 認証切れ → observe() で監視通知
- タイムアウト: 10分でタイムアウト → 失敗報告
- ソース過大: 5000語に切り詰めてリトライ

### 3.3 notify-telegram

**トリガー:** タスク完了時（エージェントが自動判断）

**API:** `POST https://api.telegram.org/bot{token}/sendMessage`

**メッセージ送信ルール:**
- chat_id: メタデータから取得
- parse_mode: Markdown（v1）
- 4096文字超: パラグラフ境界で分割
- reply_to_message_id: msg_id（オプション、UX改善用）

**エラーハンドリング:**
- 429: `retry_after` 待機 → リトライ1回
- 400: parse_mode なしでリトライ
- ネットワークエラー: 5秒後にリトライ1回
- 2回失敗: エラー報告、リトライ停止

### 3.4 create-task

**トリガー:** 複数ステップのタスクで後続処理をキューに投入する場合

**使用方法:**
```bash
source "$CLAUDE_INBOX/lib/task.sh"
task_submit --prompt "[Context: session_id=$CURRENT_SESSION_ID]
後続タスクのプロンプト"
```

**session_id の引き継ぎ:**
- session_id あり: 次の worker が `--resume` でコンテキスト継続
- session_id なし: self-contained なプロンプトが必要

### 3.5 notify-slack（P2）

**トリガー:** Slack 通知が要求された場合

**API:** Slack Incoming Webhook

**現状:** 最小実装（mrkdwn テキスト送信のみ）

---

## 4. セッション管理設計

### 4.1 セッション ID の計算

```python
import uuid
session_id = uuid.uuid5(uuid.NAMESPACE_URL, f"telegram:{chat_id}")
```

| チャンネル | 計算式 | 単位 |
|---|---|---|
| Telegram (private) | `uuid5("telegram:{chat_id}")` | chat 単位 |
| Slack (将来) | `uuid5("slack:{channel_id}:{thread_ts}")` | スレッド単位 |

### 4.2 セッションライフサイクル

1. **初回:** `claude --session-id $sid -p "..."` で新規作成
2. **継続:** `claude --resume $sid -p "..."` でセッション再開
3. **判定:** worker が自動判定（resume 試行 → 失敗時に session-id）
4. **保存:** `~/.claude/projects/` にローカル保存（約30日保持）
5. **肥大化:** 将来的に `/compact` 相当の処理が必要（P1）

### 4.3 コンテキストの流れ

```
Turn 1: "今日のテックニュースを集めて"
  → Claude セッション作成、web-collect 実行、結果をセッションに保存

Turn 2: "それをPodcastにして"
  → --resume で Turn 1 の文脈あり、notebooklm 実行

Turn 3: "Telegramで送って"
  → --resume で Turn 1-2 の文脈あり、notify-telegram 実行
```

---

## 5. エラーハンドリング設計

### 5.1 エラー分類

| レベル | 対象 | 処理 | 通知先 |
|---|---|---|---|
| タスクエラー | claude -p 失敗 | failed/ に保存 | observe (システム監視) |
| ワーカーエラー | worker.sh クラッシュ | task_recover + 自動再起動 | observe |
| ブリッジエラー | API 通信失敗 | リトライ + sleep | stderr |
| スキルエラー | 外部 API 失敗 | エージェントが判断 | エージェント返信 |
| 認証エラー | nlm 401 | 報告のみ | observe |

### 5.2 クラッシュリカバリ

- ワーカー停止時: `task_recover()` が cur/ の孤児を new/ に戻す
- trap EXIT/INT/TERM でクリーンアップ
- claude-inbox.sh が5秒間隔でワーカー死亡を検知し再起動

### 5.3 アトミック性による整合性保証

- `tmp/` にゴミが残る可能性あり → 無害（起動時に清掃可能）
- `new/`, `done/`, `failed/` は常に整合状態
- `cur/{wid}/` のタスクはワーカーが処理中 or 孤児（recover 対象）
