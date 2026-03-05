# claude-inbox: CLAUDE.md

## これは何か

claude-inbox はファイルベースのタスクキューで、Claude Code エージェントに非同期でタスクを実行させるシステム。
Telegram などのチャットアプリを入口にして、ユーザーのメッセージを受け取り、Claude Code の `claude -p` でタスクを実行し、結果をチャットに返す。

**価値は「スマホから・移動中に・非同期で」。** CLI で直接 Claude Code を使えばいいものはここに含めない。

Maildir 形式のジョブキュー + Claude Code のセッション管理を組み合わせることで、チャットアプリ上でステートフルな会話型エージェントを実現する。

---

## アーキテクチャ概要

```
Telegram Chat (chat_id=12345)
  ↕
bin/claude-inbox-bridge-telegram (ステートレス)
  ↓ task_submit (.task ファイル)
new/*.task → bin/claude-inbox-preprocessor → tasks/{job_id}/ → bin/claude-inbox-worker → claude --resume → done/{job_id}/
  ↑ task_claim (atomic mv)                                                                  ↓
  skills/notify-telegram (結果をチャットに返信)                                             Telegram Chat
```

**ファイル添付の流れ（bridge 不要でも動作）:**
```
ユーザー: mv scan.pdf ~/.claude-inbox/new/ocr/
  → preprocessor: tasks/{job_id}/ (prompt.txt + scan.pdf)
  → worker: claude -p "OCR this file..." → done/{job_id}/result
```

**Docker 構成:**
```
claude-mem        — 永続メモリサービス (Bun, port 37777)
chrome            — kasmweb/chrome (VNC :6901 + CDP)
chrome-cdp        — socat relay (CDP localhost → 0.0.0.0)
preprocessor      — inbox → task 変換
worker            — タスク処理 × N（Chrome なし、CDP で chrome コンテナに接続）
bridge-telegram   — Telegram ロングポーリング
cron              — スケジュール実行
url-watch         — URL 変更検知
```

---

## コア設計原則

### 1. 1チャンネル = 1 Claude セッション

Telegram の private chat にはスレッドがない（LINE と同じフラット構造）。
reply-to は1段の参照しか持たず、root message まで遡る API もない。

そのため、**chat_id 単位で1つの Claude セッションを持つ** 設計にした。

```python
session_id = uuid5(NAMESPACE_URL, f"telegram:{chat_id}")
```

- 全メッセージが同じセッションに入る
- reply-to の解析不要
- bridge.db 不要（完全ステートレス）
- ユーザーが何か送るたびに `--resume` するだけ

### 2. session_id は決定論的に計算する（ステートレス）

`uuid5` は純粋関数 — 同じ入力から常に同じ UUID が出る。
bridge はメッセージを受け取るたびに `chat_id` から `session_id` を計算するだけ。

初回は `--session-id` で新規作成、以降は常に `--resume`。
`--resume` が失敗（セッション未存在）したら `--session-id` にフォールバック。

### 3. コンテキストは Claude のセッションストレージが保持する

`--resume` で Claude 自身が前のターンを覚えているため、done/ の .result を読んで復元する必要はない。

- `~/.claude/projects/` 以下に Claude がセッション履歴を保存（ローカル、約30日保持）
- ユーザーが「さっきのをPodcastにして」と言えば、Claude は前のターンで何をしたか知っている
- .result はあくまでログ。コンテキスト復元には使わない

### 4. inbox / task 分離 + Maildir ベースのキュー

**inbox** (`new/`): ユーザーがリクエストを投入する場所。単一ファイルまたは .task ファイル。
**task** (`tasks/`): エージェントが処理する単位。自己完結したディレクトリ。
**preprocessor**: inbox → task を変換する専用ワーカー。

```
new/                 inbox（bridge/CLI が投入、ファイル直置きも可）
  ├── *.task         テキストプロンプト（bridge/CLI が生成）
  ├── ocr/           アクションディレクトリ（prompt.txt + ファイル投入）
  ├── transcribe/    同上
  └── *.{jpg,pdf}    ルート直置き（拡張子からデフォルト推論）
tasks/{job_id}/      preprocessor が生成した自己完結タスク
  ├── prompt.txt     処理指示（必須）
  ├── meta           メタデータ k=v（optional）
  └── *.{jpg,pdf}    添付ファイル（0個以上）
cur/{wid}/{job_id}/  処理中（worker が claim したもの）
done/{job_id}/       完了（prompt.txt + meta + result + 添付ファイル）
failed/{job_id}/     失敗（同上）
tmp/                 write-to-tmp 用（atomic rename の元）
```

### 5. スキル ≠ インフラ

- `lib/` — インフラ層。worker が source して使う。エージェントは触らない
  - `task.sh`: atomic なタスク操作 (claim, complete, fail, submit, recover)
  - `observe.sh`: システム監視通知（エージェント非経由、bash が決定的に実行）
- `skills/` — 知識層。Claude Code 仕様準拠の SKILL.md
  - `--add-dir skills/` でエージェントに渡す
  - エージェントが frontmatter の description を見て自動ロード（progressive disclosure）

### 6. 通知チャンネルは2つに分離

**エージェント返信** (`skills/notify-telegram`):
- タスクの結果をユーザーに届ける
- エージェントが判断して実行
- 環境変数: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`

**システム監視** (`lib/observe.sh`):
- ワーカー死亡、起動/停止、認証切れ
- bash が決定的に実行（エージェント非経由）
- 環境変数: `OBSERVE_TELEGRAM_BOT_TOKEN`, `OBSERVE_TELEGRAM_CHAT_ID`

### 7. アトミック性の保証

全操作は **write-to-tmp + mv(2) rename** パターン。

- POSIX `mv` は同一 FS 上で `rename(2)` = カーネルレベルでアトミック
- flock 不要（ロックファイル管理のバグを排除）
- 複数 worker の排他制御: `mv` が成功した worker が勝ち、失敗した worker はリトライ

---

## ファイル構成（現在）

```
claude-inbox/
├── Dockerfile
├── docker-compose.yml
├── .env.example
├── bin/
│   ├── claude-inbox-worker       # ワーカー本体（tasks/ → claude → done/）
│   ├── claude-inbox-preprocessor # inbox 変換（new/ → tasks/）
│   ├── claude-inbox-add          # タスク投入 CLI（--file 対応）
│   ├── claude-inbox-bridge-telegram  # Telegram ブリッジ（ファイル DL 対応）
│   ├── claude-inbox-cron         # cron スケジューラ
│   ├── claude-inbox-url-watch    # URL 変更検知
│   └── claude-inbox-setup        # 初回セットアップ
├── lib/
│   ├── task.sh                   # アトミックなタスク操作（ディレクトリベース）
│   ├── util.sh                   # 共通ユーティリティ（session_id 生成、FS イベント待機）
│   ├── notify.sh                 # Telegram 直接送信（進捗通知用）
│   ├── observe.sh                # システム監視通知
│   └── cron.sh                   # cron スケジュール解析
├── prompts/
│   ├── system.md                 # エージェント用 system prompt
│   └── CLAUDE.md                 # エージェント用 CLAUDE.md
├── skills/
│   ├── browser-use/SKILL.md      # ブラウザ自動操作 (Playwright MCP + CDP)
│   ├── create-task/SKILL.md      # フォローアップタスク投入
│   ├── manage-inbox/SKILL.md     # タスクキュー管理
│   ├── notebooklm/SKILL.md       # NotebookLM Podcast 生成
│   ├── notify-telegram/SKILL.md  # Telegram 通知
│   ├── notify-slack/SKILL.md     # Slack 通知 (P2)
│   ├── schedule-task/SKILL.md    # cron ジョブ登録
│   ├── google-workspace/SKILL.md  # Google Workspace (Gmail, Calendar, Drive, Sheets, Docs)
│   ├── switchbot/SKILL.md        # SwitchBot デバイス操作
│   ├── url-watch/SKILL.md        # URL 監視登録
│   └── web-collect/SKILL.md      # HN + GitHub Trending 収集
├── systemd/
│   ├── claude-inbox.service
│   └── bridge-telegram.service
└── test/
    ├── task.bats
    ├── worker.bats
    └── ...
```

---

## 各コンポーネントの詳細

### bin/claude-inbox-preprocessor

inbox (`new/`) を監視し、自己完結したタスクディレクトリ (`tasks/`) を生成する。

**3種類の入力を処理:**
1. `.task` ファイル（bridge/CLI が生成）→ メタデータ分離 + prompt.txt 生成
2. アクションディレクトリ内のファイル（`new/ocr/scan.pdf`）→ テンプレート prompt 適用
3. ルート直置きファイル（`new/photo.jpg`）→ 拡張子からデフォルト推論

**デフォルトアクション:** 起動時に `ocr/`, `transcribe/` を `prompt.txt` テンプレート付きで自動作成。
ユーザーが `new/` にカスタムアクションディレクトリを追加することも可能。

### bin/claude-inbox-bridge-telegram

ステートレスな受信ブリッジ。Telegram Bot API をロングポーリングし、
メッセージを受け取るたびに `.task` ファイルを生成して `new/` に投入する。
ファイル添付（画像・文書・音声・動画）にも対応し、DL して `files=` メタデータで参照する。

**session_id の計算:**
```bash
session_id=$(generate_session_id "telegram:${chat_id}")  # lib/util.sh の uuid5
```

**タスクのメタデータ形式:**
```
[from=UserName channel=telegram chat_id=12345 msg_id=200 session_id=xxxx-xxxx]

ユーザーのメッセージ本文
```

- `msg_id` はユーザーのメッセージ ID（notify-telegram が reply_to する用）
- `/haiku`, `/sonnet`, `/opus` プレフィックスでモデル指定可

**オプション:** `--skip-pending` で起動時の未処理メッセージをスキップ（デフォルト有効）

### bin/claude-inbox-worker

メインのワーカープロセス。`tasks/` からディレクトリを claim し、claude を実行する。

**タスク処理の流れ:**
1. `task_claim` で `tasks/{job_id}/` を `cur/{wid}/{job_id}/` にアトミック移動
2. `prompt.txt` を読み込み、`meta` からメタデータ（session_id, channel, chat_id 等）を取得
3. メタデータヘッダを prompt に復元（エージェントが chat_id 等を参照できるように）
4. 添付ファイルのパスと MIME タイプを prompt に追記
5. `run_claude` で実行（`--resume` → `--session-id` フォールバック）
6. 結果を `done/` または `failed/` に移動

**モデル選択:**
- 環境変数 `CLAUDE_MODEL` でデフォルトモデル指定
- タスクメタデータ `model=haiku` でタスク単位の上書き
- Telegram メッセージの `/haiku`, `/sonnet`, `/opus` プレフィックスでも指定可

### bin/claude-inbox-setup

初回セットアップ用 CLI:

```bash
claude-inbox-setup login       # Claude Code 認証（claude_dot volume に保存）
claude-inbox-setup nlm-login   # NotebookLM 認証（kasmweb Chrome + CDP 経由、VNC でログイン）
claude-inbox-setup claude-mem  # claude-mem MCP を ~/.claude/settings.json に登録
claude-inbox-setup status      # セットアップ状態確認
```

### lib/task.sh

ディレクトリベースのアトミックなタスク操作。
```
task_claim    — tasks/ から1件取得して cur/$WORKER_ID/ にアトミック移動
task_complete — result 書き込み + done/ にディレクトリ移動
task_fail     — result 書き込み + failed/ にディレクトリ移動
task_submit   — .task ファイルを new/ に投入（preprocessor が変換）
task_recover  — cur/{wid}/ の孤児を tasks/ に戻す（クラッシュ復旧）
```

**セッションロック:** `flock` で同一 session_id への並行アクセスを防止。
プロセス死亡時にカーネルが自動解放。

**タスク ID:** `{YYYYMMDD-HHMMSS}.{random_hex}`（preprocessor が生成）
**投入時 ID:** `{priority}.{YYYYMMDD-HHMMSS}.{random_hex}`（task_submit が生成、.task ファイル名）

### Docker サービス

| サービス | 役割 | ボリューム |
|---|---|---|
| `claude-mem` | 永続メモリ (Bun, port 37777) | `claude_mem_data` |
| `chrome` | kasmweb/chrome:1.15.0 (VNC :6901 + CDP) | `chrome_profile` |
| `chrome-cdp` | socat relay (CDP localhost → 0.0.0.0:9222) | (chrome と network NS 共有) |
| `preprocessor` | inbox → task 変換 | inbox |
| `worker` | タスク処理 × N（CDP で chrome に接続） | `claude_dot`, inbox, workdir, `nlm_auth`, `gws_config` |
| `bridge-telegram` | Telegram 受信（ファイル DL 対応） | inbox |
| `cron` | スケジュール実行 | inbox |
| `url-watch` | URL 変更検知 | inbox |

**UID/GID リマッピング:** コンテナはビルド時に UID 1000 で作成。起動時に `docker-entrypoint.sh` が `DOCKER_UID`/`DOCKER_GID` に合わせて `/etc/passwd` を書き換え、`gosu` で権限を落とす。これにより pre-built イメージが任意のホスト UID/GID で動作する。

**claude-mem の仕組み:** `mcp-server.cjs` (stdio, Claude Code が起動) ↔ HTTP ↔ `worker-service.cjs` (Bun, 常駐)。環境変数 `CLAUDE_MEM_WORKER_HOST=claude-mem` でコンテナ間通信。

---

## スキル詳細

### browser-use

Playwright MCP 経由で kasmweb Chrome (CDP) に接続してブラウザを自動操作。

- Chrome は `kasmweb/chrome` 別コンテナで動作（worker にはインストール不要）
- CDP relay (socat) 経由で worker → chrome:9222 に接続
- Chrome の GUI は `https://localhost:6901` で VNC アクセス可能
- Chrome プロファイルは `chrome_profile` volume で永続化

### create-task

フォローアップタスクを inbox キューに投入する。
session_id を渡せば次の worker が `--resume` でコンテキストを引き継げる。

### web-collect

HN API + GitHub Search API からテックニュースを収集。認証不要。

### notebooklm

`nlm` CLI (pip: notebooklm-mcp-cli) で Podcast 生成。
認証: `bin/claude-inbox-setup nlm-login`（kasmweb Chrome に CDP 接続、VNC でログイン操作）。Cookie ベース、2-4週間持続。credentials は `nlm_auth` volume に永続化。

### google-workspace

`gws` CLI (`@googleworkspace/cli`) で Gmail, Calendar, Drive, Sheets, Docs を操作。
認証: `bin/claude-inbox-setup gws-login`（gcloud CLI + OAuth）。credentials は `gws_config` volume に永続化。

### notify-telegram

Telegram Bot API でメッセージ送信。4096文字制限 → 分割送信。Markdown v1。

### notify-slack

Slack Incoming Webhook。P2。最小実装のみ。

---

## 機能ロードマップ

### コア拡張

| 機能 | 概要 | 状態 |
|---|---|---|
| **cron スケジューラ** | 定期的に task_submit。`schedule/cron.d/*.job` | 実装済み |
| **URL ウォッチ** | URL ポーリング → 変化検知 → diff 要約して通知 | 実装済み |
| **ファイル添付処理** | inbox にファイル配置 → OCR/要約/文字起こし。アクションディレクトリ対応 | 実装済み |
| **進捗通知** | 長いタスクの途中経過を Telegram に流す | 実装済み（開始時 "..." 送信） |
| **タスクキャンセル** | `manage-inbox` スキルで `tasks/` から削除 | 実装済み |

### スキル / 連携

| スキル | 概要 | 状態 |
|---|---|---|
| **SwitchBot 連携** | REST API v1.1 経由でデバイス操作 | 実装済み |
| **GitHub 連携** | PR・Issue・リポジトリの URL を貼る → 自動で要約・レビュー・関連調査 | 未実装 |
| **Matter 連携** | SwitchBot と同様の IoT 制御。デバイス未所持のためペンディング | 未実装 |

### memory 活用

| 機能 | 概要 |
|---|---|
| **セッション間コンテキスト共有** | CLI で作業した内容を Telegram から参照。1 claude-inbox = 1 WORKDIR = 1 memory 空間 |
| **日報・週報自動生成** | memory に蓄積された作業履歴から生成 |

### 将来の bridge

| チャンネル | セッション粒度 | 備考 |
|---|---|---|
| Telegram private | chat_id 単位 | 実装済み |
| Telegram Forum Topics | topic (thread) 単位 | `message_thread_id` が使える |
| Slack | thread_ts 単位 | P1。スレッド単位で session 分離可能 |

---

## 未解決の課題

### P0: notify-telegram SKILL.md の更新

`origin_msg_id` / reply threading の古い設計が残っている。
現設計では `msg_id`（ユーザーの最新メッセージ）に reply するだけでよい。
必須ではないが、UX のために直近のユーザーメッセージに reply する形に更新する。

### P1: セッションの寿命管理

`~/.claude/projects/` のローカル保持はデフォルト約30日。
セッションが肥大化すると token 消費が増える。
定期的な `/compact` 相当の処理が必要かもしれない。

### P1: Slack bridge

`session_id = uuid5("slack:{channel_id}:{thread_ts}")` でスレッド単位の管理が可能。
bridge のチャンネル種別ごとに session_id 計算ロジックを差し替えられる設計にする。

### P2: done/failed の定期削除

タスクディレクトリが蓄積する。古い `done/`, `failed/` を定期削除する cron ジョブが必要。

---

## 設計判断の早見表

| 判断 | 採用 | 却下 | 理由 |
|---|---|---|---|
| コンテキスト管理 | Claude session (`--resume`) | task_id + read-task | Claude が覚えてるので不要 |
| セッション単位 | 1 chat_id = 1 session | スレッド単位 | Telegram にスレッドがない |
| session_id 計算 | uuid5 (決定論的) | DB に保存 | ステートレスが最良 |
| ステート | なし（完全ステートレス） | SQLite (bridge.db) | chat_id → session_id は計算で出る |
| スキル選択 | エージェント自動判断 | タスクに --skill 指定 | Claude Code と同じ progressive disclosure |
| 通知 | 2チャンネル分離 | 1チャンネル | エージェント返信とシステム監視は別 |
| アトミック性 | mv(2) rename + flock（セッションロック） | DB ロック | rename はカーネルアトミック、flock はプロセス死亡時自動解放 |
| 結果の永続化 | Claude session + done/ ログ | done/ のみ | session が primary、ファイルは backup |
| ブラウザ操作 | kasmweb/chrome + CDP relay | worker 内蔵 Chrome | Chrome 分離でイメージ軽量化 + VNC でデバッグ可 |
| cross-session memory | claude-mem (別コンテナ) | Claude session のみ | 複数チャンネル間で共有できる |

---

## Claude Code の CLI フラグ（重要）

```bash
# 新規セッション（UUID 指定）
claude --session-id <uuid> -p "..."

# セッション継続
claude --resume <session_id> -p "..."

# --resume フォールバックパターン（worker で採用）
claude --resume "$sid" -p "..." 2>/dev/null || claude --session-id "$sid" -p "..."

# スキルディレクトリを追加（progressive disclosure）
claude --add-dir skills/ -p "..."

# 自動実行用
claude --dangerously-skip-permissions -p "..."
```

- `--session-id` は valid UUID が必須
- `--resume` は存在しないセッションだとエラー（→ フォールバック必須）
- `--output-format json` で `session_id` フィールドが返る
- セッション履歴は `~/.claude/projects/` にローカル保存（約30日）

---

## Telegram Bot API メモ

- Private chat: スレッドなし。`reply_to_message` は1段の参照のみ
- Forum Topics (Group + Topics): `message_thread_id` が使える = Slack のスレッドに近い
- `message_thread_id` は private chat では使えない → chat_id 単位で割り切り

---

## Docker 運用

```bash
# セットアップ
cp .env.example .env && vim .env
docker compose pull

# 初回認証
docker compose run --rm worker bin/claude-inbox-setup login
docker compose run --rm worker bin/claude-inbox-setup claude-mem

# 起動
docker compose up -d

# ログ
docker compose logs -f worker
docker compose logs -f bridge-telegram

# タスク投入
docker compose exec worker bin/claude-inbox-add "今日のニュースを集めてPodcastにして"

# 状態確認
docker compose exec worker bin/claude-inbox-setup status
```

**オプション機能（.env で設定）:**

| 機能 | 設定 |
|---|---|
| kasmweb Chrome VNC パスワード | `KASM_VNC_PW=password` |
| kasmweb Chrome VNC ポート | `KASM_PORT=6901` |

---

## コマンド例

```bash
# タスク投入
docker compose exec worker bin/claude-inbox-add "今日のテックニュースを集めてPodcastにしてTelegramで送って"
docker compose exec worker bin/claude-inbox-add --priority 1 "緊急: nlm の認証状態を確認して"
docker compose exec worker bin/claude-inbox-add --file report.pdf "この PDF を要約して"

# ファイル添付（bridge 不要）
cp scan.pdf ~/.claude-inbox/new/ocr/        # OCR
cp meeting.mp3 ~/.claude-inbox/new/transcribe/  # 文字起こし
cp photo.jpg ~/.claude-inbox/new/           # デフォルト推論（Describe this image.）

# タスク状態確認
ls ~/.claude-inbox/new/       # inbox（preprocessor が変換待ち）
ls ~/.claude-inbox/tasks/     # 処理待ち
ls ~/.claude-inbox/cur/       # 処理中
ls ~/.claude-inbox/done/      # 完了
ls ~/.claude-inbox/failed/    # 失敗
```
