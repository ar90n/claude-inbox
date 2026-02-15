# プロダクト要求定義書 (PRD): claude-inbox

## 1. プロダクト概要

### 1.1 プロダクト名
claude-inbox

### 1.2 概要
claude-inbox は、ファイルベースのタスクキューを通じて Claude Code エージェントに非同期でタスクを実行させるシステムである。Telegram などのチャットアプリを入口にして、ユーザーのメッセージを受け取り、Claude Code の `claude -p` でタスクを実行し、結果をチャットに返す。

Maildir 形式のジョブキュー + Claude Code のセッション管理を組み合わせることで、チャットアプリ上でステートフルな会話型エージェントを実現する。

### 1.3 ターゲットユーザー
- 開発者・テクニカルユーザー
- Claude Code CLI を日常的に使用しているユーザー
- チャットアプリ（Telegram）から非同期でAIタスクを実行したいユーザー

### 1.4 解決する課題
- Claude Code CLI はターミナルに張り付いている必要がある
- モバイルや外出先から Claude Code にタスクを投げたい
- タスクの実行結果をチャットアプリで受け取りたい
- 複数ステップのタスク（ニュース収集 → Podcast生成 → 通知）を自動チェーンしたい

---

## 2. ユーザーストーリー

### US-1: 基本的なタスク実行
**As a** ユーザー
**I want to** Telegram からメッセージを送って Claude Code にタスクを実行させたい
**So that** ターミナルに張り付かずに AI タスクを実行できる

**受け入れ条件:**
- Telegram Bot にメッセージを送ると、タスクがキューに投入される
- ワーカーがタスクを取得し、`claude -p` で実行する
- 実行結果が Telegram に返信される

### US-2: セッション継続（ステートフルな会話）
**As a** ユーザー
**I want to** 前のメッセージの文脈を保ったまま追加の指示を出したい
**So that** 「さっきのをPodcastにして」のような短い指示で連続タスクを実行できる

**受け入れ条件:**
- 同一 chat_id のメッセージは同じ Claude セッションに紐づく
- 2回目以降のメッセージは `--resume` でセッションを継続する
- ユーザーが前のタスクの結果を参照できる

### US-3: CLI からのタスク投入
**As a** 開発者
**I want to** コマンドラインから直接タスクを投入したい
**So that** cron ジョブやスクリプトからタスクをスケジュールできる

**受け入れ条件:**
- `inbox-add "プロンプト"` でタスクを投入できる
- `--priority` で優先度を指定できる
- stdin からプロンプトを読み込める

### US-4: テックニュース収集
**As a** ユーザー
**I want to** 「今日のテックニュースを集めて」と言うだけでニュースダイジェストを取得したい
**So that** 毎日のニュースチェックを自動化できる

**受け入れ条件:**
- Hacker News Top 10 と GitHub Trending が収集される
- Markdown 形式でサマリーが生成される
- 結果が Telegram に通知される

### US-5: Podcast 生成
**As a** ユーザー
**I want to** 収集したコンテンツから Podcast を生成したい
**So that** 通勤中に音声でニュースを聞ける

**受け入れ条件:**
- NotebookLM (`nlm` CLI) で Podcast が生成される
- 音声 URL が Telegram に通知される
- 認証切れの場合はシステム監視で通知される

### US-6: 複数ステップのタスクチェーン
**As a** ユーザー
**I want to** 「ニュース集めてPodcastにしてTelegramで送って」と一言で全ステップを実行したい
**So that** 複雑なワークフローを手動で管理しなくて済む

**受け入れ条件:**
- エージェントがスキルを自動選択して順次実行する
- 必要に応じて create-task で後続タスクをキューに投入する
- session_id が引き継がれ、文脈が保持される

### US-7: システム監視
**As a** 運用者
**I want to** ワーカーの死亡やタスク失敗を即座に知りたい
**So that** 障害時に迅速に対応できる

**受け入れ条件:**
- ワーカー死亡時に監視チャンネルに通知される
- タスク失敗時にエラー内容が通知される
- システム起動・停止時にも通知される
- エージェントの返信チャンネルとは分離されている

---

## 3. 機能要件

### F-1: タスクキュー（Maildir 形式）
- Maildir ディレクトリ構成: `new/`, `cur/{worker_id}/`, `done/`, `failed/`, `tmp/`
- タスクID命名規則: `{priority}.{YYYYMMDD-HHMMSS}.{random_hex}`
- アトミック操作: write-to-tmp + mv(2) rename パターン
- 排他制御: mv 成功 = 獲得、失敗 = 他 worker が先取り

### F-2: ワーカー（worker.sh）
- タスクの claim → 実行 → complete/fail のライフサイクル管理
- Claude Code CLI (`claude -p`) によるタスク実行
- `--resume` フォールバック: まず resume を試み、失敗時に `--session-id` で新規作成
- `--dangerously-skip-permissions` による自動実行
- `--system-prompt` と `--add-dir skills/` の注入
- クラッシュリカバリ: cur/ の孤児タスクを new/ に戻す

### F-3: 受信ブリッジ（inbox-recv）
- Telegram Bot API ロングポーリング
- chat_id から session_id を決定論的に計算（uuid5）
- メタデータ形式: `[from=User channel=telegram chat_id=12345 msg_id=200 session_id=xxx]`
- ステートレス: DB やファイルベースの状態管理なし

### F-4: プロセス管理（claude-inbox.sh）
- 複数ワーカーの起動・管理
- 死亡ワーカーの自動再起動
- シグナルハンドリング（INT, TERM → graceful shutdown）
- systemd 統合

### F-5: スキルシステム
- `--add-dir skills/` による progressive disclosure
- エージェントがスキルの frontmatter (name/description) を読んで自動選択
- 以下のスキルを提供:
  - `web-collect`: HN + GitHub Trending 収集
  - `notebooklm`: Podcast 生成
  - `notify-telegram`: Telegram 通知
  - `notify-slack`: Slack 通知（P2）
  - `create-task`: フォローアップタスク投入

### F-6: 通知（2チャンネル分離）
- エージェント返信: notify-telegram スキル（エージェントが判断して実行）
- システム監視: lib/observe.sh（bash が決定的に実行）
- 別の Bot / チャットを使用可能

---

## 4. 非機能要件

### NFR-1: 信頼性
- タスクのアトミック操作により、クラッシュ時もデータ整合性を保証
- ワーカー死亡時の自動再起動
- 失敗タスクは failed/ に保存され、再実行可能

### NFR-2: ステートレス性
- 受信ブリッジは完全ステートレス（DB 不要）
- session_id は純粋関数（uuid5）で計算

### NFR-3: シンプルさ
- 依存関係の最小化: bash, curl, jq, python3（uuid5計算のみ）
- Claude Code CLI 以外の特別なランタイム不要
- flock 不要（mv のアトミック性を利用）

### NFR-4: 拡張性
- チャンネル種別ごとの session_id 計算ロジック差し替え
  - Telegram: `uuid5("telegram:{chat_id}")`
  - Slack: `uuid5("slack:{channel_id}:{thread_ts}")`
- スキルの追加は skills/ にディレクトリを作るだけ

### NFR-5: 運用性
- systemd unit file による起動管理
- journalctl によるログ確認
- Maildir ディレクトリの直接参照による状態確認
- 環境変数ベースの設定

### NFR-6: セキュリティ
- `--dangerously-skip-permissions` はサーバー環境での自動実行専用
- 環境変数によるトークン管理
- systemd の `NoNewPrivileges`, `ProtectSystem=strict` による制限

---

## 5. 成功指標

| 指標 | 目標 |
|---|---|
| タスク成功率 | 90%以上のタスクが正常完了 |
| 応答時間 | メッセージ送信から結果通知まで5分以内（Podcast生成を除く） |
| セッション継続性 | 同一 chat_id の連続メッセージが正しく同一セッションに紐づく |
| ワーカー稼働率 | 99%以上（自動再起動により） |
| 障害検知時間 | ワーカー死亡から監視通知まで10秒以内 |

---

## 6. スコープ

### In Scope（v3.1）
- Telegram Bot 経由のタスク受信・結果通知
- CLI (`inbox-add`) によるタスク投入
- Maildir ベースのタスクキュー
- Claude Code セッション管理（resume/session-id）
- web-collect, notebooklm, notify-telegram, create-task スキル
- systemd 統合
- システム監視通知

### Out of Scope（将来）
- Slack 対応（P1）
- cron タスクの定期実行（P2）
- Web UI / ダッシュボード
- マルチユーザー認証
- タスクの優先度キューの動的変更
- セッション履歴のエクスポート

---

## 7. 技術的制約

- Claude Code CLI (`claude`) がインストール・認証済みであること
- `nlm` CLI が `notebooklm` スキル使用時にインストール・認証済みであること
- POSIX 準拠の `mv` が rename(2) で動作するファイルシステム（同一FS上）
- Telegram Bot Token が取得済みであること
- systemd が利用可能な Linux 環境

---

## 8. 現在の課題と優先度

### P0（即時対応）
- inbox-recv の書き直し: 1チャンネル=1セッション設計への移行
- worker.sh の --resume フォールバック実装
- notify-telegram SKILL.md の origin_msg_id 旧設計の更新

### P1（重要）
- セッションの寿命管理（肥大化対策）
- Slack 対応

### P2（将来）
- cron タスク対応
- 旧ファイルの整理・削除
- notify-slack の本格実装
