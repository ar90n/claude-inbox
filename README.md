[![CI](https://github.com/ar90n/claude-inbox/actions/workflows/ci.yml/badge.svg)](https://github.com/ar90n/claude-inbox/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
![Built with vibe coding](https://img.shields.io/badge/built%20with-vibe%20coding-ff69b4)

# claude-inbox

An async task queue that lets you use Claude Code from Telegram. Send a message from your phone, Claude works on it, and replies back.

## How it works

```
Telegram → bridge → inbox (task queue) → worker (claude -p) → reply on Telegram
```

- Each message becomes a task file, processed by workers in order
- Sessions are maintained per chat, so Claude remembers context across messages
- Runs with Docker Compose

## Setup

### 1. Get the release

```bash
gh release download latest -p 'docker-compose.yml' -p '.env.example'
```

Or clone:

```bash
git clone https://github.com/user/claude-inbox.git && cd claude-inbox
```

### 2. Configure

```bash
cp .env.example .env
echo "DOCKER_UID=$(id -u)" >> .env
echo "DOCKER_GID=$(id -g)" >> .env
```

Edit `.env`:

| Variable | Required | Description |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | Yes | From BotFather |
| `TELEGRAM_ALLOWED_CHAT_IDS` | Yes | Allowed chat IDs (comma-separated). Check with @userinfobot |
| `CLAUDE_MODEL` | No | Default model (`sonnet`, `opus`, `haiku`) |
| `WORKERS` | No | Parallel workers (default: 1) |
| `GITHUB_TOKEN` | No | Higher rate limit for web-collect |

### 3. Build and authenticate

```bash
docker compose build
docker compose run --rm worker bin/claude-inbox-setup login
docker compose run --rm worker bin/claude-inbox-setup status
```

### 4. Start

```bash
docker compose up -d
```

## Usage

Send a message to your bot on Telegram. It works like a normal conversation.

```
You:    Get today's HN top 10
Claude: (fetches via web-collect and replies)

You:    Turn that into a podcast
Claude: (remembers the previous result, generates via NotebookLM)
```

### Model selection

Prefix your message to switch models:

```
/haiku quick question
/opus think deeply about this problem
```

### CLI task submission

```bash
docker compose exec worker bin/claude-inbox-add "collect today's tech news"
```

## Skills

Workers automatically pick the right skill for each task:

| Skill | What it does |
|---|---|
| web-collect | Collect news from HN, GitHub Trending, Reddit, Lobsters, dev.to, etc. |
| browser-use | Browser automation (form filling, scraping, etc.) |
| notebooklm | Generate podcast audio from collected content |
| create-task | Queue follow-up tasks |
| schedule-task | Recurring tasks ("collect news every morning at 8am") |
| url-watch | Monitor URLs for changes and notify |

## Optional features

### claude-mem (persistent memory)

Retain context across sessions:

```bash
docker compose run --rm worker bin/claude-inbox-setup claude-mem
```

### NotebookLM (podcast generation)

```bash
docker compose run --rm worker bin/claude-inbox-setup nlm-login
```

Cookie-based auth. Re-authenticate every 2-4 weeks.

### System monitoring

Send worker health alerts to a separate Telegram bot/chat. Set `OBSERVE_TELEGRAM_BOT_TOKEN` and `OBSERVE_TELEGRAM_CHAT_ID` in `.env`.

## Operations

```bash
# Logs
docker compose logs -f worker
docker compose logs -f bridge-telegram

# Status
docker compose exec worker bin/claude-inbox-setup status

# Task state
ls ~/.claude-inbox/new/      # pending
ls ~/.claude-inbox/done/     # completed
ls ~/.claude-inbox/failed/   # failed

# Update
docker compose pull && docker compose up -d
```

## License

MIT
