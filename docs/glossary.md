# 用語集: claude-inbox

## A

### Atomic Rename / アトミックリネーム
POSIX の `mv` コマンドが同一ファイルシステム上で `rename(2)` システムコールを使用することで実現されるアトミックなファイル操作。claude-inbox の全ファイル操作の基盤。flock やロックファイルを不要にする。

## B

### Bridge / ブリッジ
外部チャットアプリのメッセージをタスクキューに変換するコンポーネント。`inbox-recv` がこの役割を担う。完全ステートレスで、DB やファイルベースの状態を持たない。

## C

### chat_id
Telegram のチャット識別子。private chat では各ユーザーに固有の数値 ID。claude-inbox では session_id の計算に使用される。

### claim / クレーム
ワーカーがタスクを排他的に取得する操作。`new/` から `cur/{worker_id}/` への `mv` で実現。mv が成功したワーカーがタスクを獲得し、失敗した場合は他のワーカーが先に取得したことを意味する。

### Claude Code CLI
Anthropic が提供する Claude のコマンドラインインターフェース。`claude -p` でプロンプトを実行し、`--resume` でセッションを継続できる。claude-inbox のタスク実行エンジン。

### cur/ ディレクトリ
処理中のタスクが置かれるディレクトリ。各ワーカーが `cur/{worker_id}/` サブディレクトリを持つ。ワーカー異常終了時は `task_recover()` でタスクを `new/` に戻す。

## D

### done/ ディレクトリ
完了したタスクのログ保存先。`.task` ファイル（元のプロンプト）と `.result` ファイル（実行結果）が保存される。コンテキスト復元には使用しない（Claude セッションが保持する）。

## F

### failed/ ディレクトリ
失敗したタスクの保存先。done/ と同じく `.task` + `.result` のペアが保存される。再実行のために参照可能。

### Frontmatter
SKILL.md の先頭にある YAML メタデータ。`name` と `description` を含む。Claude エージェントがスキルの自動選択に使用する。

## G

### getUpdates
Telegram Bot API のロングポーリングメソッド。指定した offset 以降の新しいメッセージを取得する。`inbox-recv` が使用。

## I

### inbox-add
コマンドラインからタスクを投入する CLI ツール。cron ジョブやスクリプトからの使用を想定。`--priority` オプションで優先度を指定可能。

### inbox-recv
チャットアプリからのメッセージを受信するブリッジ。Telegram Bot API のロングポーリングでメッセージを取得し、タスクファイルを生成して `new/` に投入する。

## L

### lib/
インフラ層のシェルスクリプトライブラリ。`worker.sh` が `source` して使用する。スキルではなく、エージェントが直接触るものではない。

## M

### Maildir
メール保存形式の一つで、メッセージを個別のファイルとして管理する。claude-inbox ではタスクキューとして応用している。`new/`, `cur/`, `done/`, `failed/`, `tmp/` のディレクトリ構成を使用。

### メタデータ
タスクファイルの1行目に `[key=value ...]` 形式で格納される情報。`from`, `channel`, `chat_id`, `msg_id`, `session_id` 等を含む。

### msg_id
Telegram メッセージの ID。v3.1 ではオプションで、`notify-telegram` スキルが `reply_to_message_id` として使用する（UX 改善用）。

## N

### new/ ディレクトリ
待機中のタスクが置かれるディレクトリ。ワーカーはここからタスクを claim する。タスクはタスクIDのソート順（優先度→タイムスタンプ）で処理される。

### nlm CLI
NotebookLM のコマンドラインツール（`notebooklm-mcp-cli`）。Podcast 生成に使用。Cookie ベースの認証で2-4週間持続。

## O

### observe()
`lib/observe.sh` で定義されるシステム監視通知関数。`OBSERVE_TELEGRAM_BOT_TOKEN` と `OBSERVE_TELEGRAM_CHAT_ID` が設定されていれば Telegram に通知し、未設定なら stderr に出力する。エージェント非経由で bash が決定的に実行する。

### origin_msg_id（廃止）
v2 で使用していた元メッセージ ID。reply-to チェーンの起点を指していたが、Telegram の制約（1段の参照のみ）により正しく追跡できないため、v3.1 で廃止された。

## P

### Progressive Disclosure
スキルの自動選択メカニズム。`--add-dir skills/` で全スキルをエージェントに渡し、エージェントが frontmatter の description を読んでタスク内容に合うスキルを自動ロードする。Claude Code の標準的なスキル選択方式。

### Priority / 優先度
タスク ID の先頭桁。0=最高、9=最低、デフォルト=5。ソート順により優先度の高いタスクが先に処理される。

## R

### resume / リジューム
Claude Code CLI の `--resume` フラグ。既存のセッションを継続する。worker.sh は常に `--resume` を試み、セッションが存在しない場合は `--session-id` にフォールバックする。

### rename(2)
POSIX のシステムコール。同一ファイルシステム上でアトミックにファイル名を変更する。`mv` コマンドが内部で使用する。

## S

### session_id / セッション ID
Claude Code のセッションを識別する UUID。`uuid5(NAMESPACE_URL, "telegram:{chat_id}")` で決定論的に計算される。同じ chat_id からは常に同じ session_id が生成される。

### SKILL.md
スキルの定義ファイル。YAML frontmatter（name, description）と手順書（Markdown）で構成される。`skills/{skill-name}/SKILL.md` に配置。

### skills/
知識層のディレクトリ。Claude Code の `--add-dir` で渡されるスキル群。各サブディレクトリに SKILL.md を置く。エージェントが自動選択する。

### prompts/
本番用プロンプトのディレクトリ。`system.md`（`--system-prompt` で渡される system prompt）と `CLAUDE.md`（エージェント向けプロジェクト指示）を格納する。

### system.md
→ `prompts/system.md` を参照。Claude エージェントの system prompt。セッション継続性、自律実行、スキル自動選択のルールを定義する。

## T

### task_claim()
`lib/task.sh` の関数。`new/` から最古のタスクを1件取得し、`cur/{worker_id}/` にアトミック移動する。mv 成功 = 獲得。

### task_complete()
`lib/task.sh` の関数。結果を `tmp/` に書き込み、`done/` にアトミック移動する。タスクファイルも `done/` に移動。

### task_fail()
`lib/task.sh` の関数。エラー情報を `tmp/` に書き込み、`failed/` にアトミック移動する。

### task_recover()
`lib/task.sh` の関数。ワーカー異常終了時に `cur/{worker_id}/` の孤児タスクを `new/` に戻す。trap EXIT で呼び出される。

### task_submit()
`lib/task.sh` の関数。新規タスクを `tmp/` に書き込み、`new/` にアトミック移動する。タスク ID を自動生成。

### Task ID / タスク ID
タスクファイルの識別子。`{priority}.{YYYYMMDD-HHMMSS}.{random_hex}` 形式。ソート順が処理順序を決定する。

### tmp/ ディレクトリ
write-to-tmp パターンの一時書き込み先。ここに書き込んでから目的ディレクトリに mv する。クラッシュ時にゴミが残る可能性があるが無害。

## U

### uuid5
UUID バージョン5。名前空間 UUID と名前文字列から決定論的に UUID を生成する。純粋関数であり、同じ入力から常に同じ出力が得られる。Python の `uuid.uuid5()` で計算。

## W

### Worker / ワーカー
`worker.sh` のプロセスインスタンス。タスクの claim → 実行 → complete/fail のライフサイクルをループで処理する。`w.{PID}` の形式で識別される。

### Worker ID
ワーカーの識別子。`w.{PID}` 形式（例: `w.12345`）。`cur/` ディレクトリのサブディレクトリ名として使用される。

### write-to-tmp パターン
claude-inbox の全ファイル操作の基本パターン。`tmp/` にファイルを書き込んでから、目的ディレクトリに `mv`（rename(2)）で移動する。書き込み途中のファイルが他プロセスから見えることを防ぐ。
