# Repository Structure: claude-inbox

## 1. Directory Layout

```
claude-inbox/
├── bin/                             # Executables
│   ├── claude-inbox                 # Entry point (launched by systemd)
│   ├── worker                       # Worker (claim task -> run claude)
│   ├── inbox-recv                   # Chat app receive bridge
│   └── inbox-add                    # CLI task submission
│
├── lib/                             # Infrastructure layer (sourced by bin/)
│   ├── task.sh                      # Atomic task operations
│   └── observe.sh                   # System monitoring notifications
│
├── skills/                          # Knowledge layer (Claude Code skills)
│   ├── create-task/
│   │   └── SKILL.md                 # Follow-up task submission
│   ├── web-collect/
│   │   └── SKILL.md                 # HN + GitHub Trending collection
│   ├── notebooklm/
│   │   └── SKILL.md                 # Podcast generation via nlm CLI
│   ├── notify-telegram/
│   │   └── SKILL.md                 # Telegram Bot API notifications
│   └── notify-slack/
│       └── SKILL.md                 # Slack Webhook notifications (P2)
│
├── prompts/                         # Production-time prompts
│   ├── CLAUDE.md                    # Production CLAUDE.md (agent instructions)
│   └── system.md                    # Agent system prompt (--system-prompt)
│
├── docs/                            # Project documentation
│   ├── product-requirements.md
│   ├── functional-design.md
│   ├── architecture.md
│   ├── repository-structure.md      # This file
│   ├── development-guidelines.md
│   └── glossary.md
│
├── claude-inbox.service             # systemd unit file
├── CLAUDE.md                        # Development design doc (for developers)
│
├── .claude/                         # Claude Code settings
│   ├── settings.local.json
│   ├── commands/
│   ├── skills/
│   └── agents/
│
├── .devcontainer/                   # VS Code Dev Container
│   └── devcontainer.json
│
└── .gitignore
```

---

## 2. File Classification

### 2.1 Executables (bin/)

| File | Role | Description |
|---|---|---|
| `bin/claude-inbox` | Entry point | Process manager, worker supervision |
| `bin/worker` | Worker | Claim task -> run claude -> save result |
| `bin/inbox-recv` | Bridge | Telegram -> task queue conversion |
| `bin/inbox-add` | CLI | Local task submission |

### 2.2 Prompts (prompts/)

| File | Role | Description |
|---|---|---|
| `prompts/system.md` | System prompt | Defines agent behavior (`--system-prompt`) |
| `prompts/CLAUDE.md` | Production CLAUDE.md | Agent-facing project instructions |

### 2.3 Configuration (root)

| File | Role | Description |
|---|---|---|
| `claude-inbox.service` | systemd unit | Daemon configuration |
| `CLAUDE.md` | Dev design doc | Architecture & design reference for developers |
| `.gitignore` | Git config | Exclusion patterns |

### 2.4 lib/ (Infrastructure Layer)

| File | Responsibility |
|---|---|
| `task.sh` | task_claim, task_complete, task_fail, task_submit, task_recover |
| `observe.sh` | observe() function (Telegram monitoring notifications) |

**Important:** lib/ is sourced by bin/ scripts. Not agent-facing — agents never invoke these directly.

### 2.5 skills/ (Knowledge Layer)

| Directory | Skill | Trigger Examples |
|---|---|---|
| `create-task/` | Follow-up task submission | Multi-step chaining |
| `web-collect/` | Tech news collection | "collect news", "HN top" |
| `notebooklm/` | Podcast generation | "make a podcast" |
| `notify-telegram/` | Telegram notifications | Task completion (auto) |
| `notify-slack/` | Slack notifications | Slack requests (P2) |

**Adding a skill:** Create `skills/{skill-name}/SKILL.md`.

### 2.6 docs/ (Documentation)

| File | Content |
|---|---|
| `product-requirements.md` | PRD (user stories, requirements) |
| `functional-design.md` | Functional design (component details, flows) |
| `architecture.md` | Architecture (diagrams, data flows) |
| `repository-structure.md` | Repository structure (this file) |
| `development-guidelines.md` | Development guidelines |
| `glossary.md` | Glossary |

---

## 3. Runtime Directory ($CLAUDE_INBOX)

Not included in the repository. Defaults to `~/.claude-inbox`.

```
$CLAUDE_INBOX/
├── tmp/                    # Temporary write area
├── new/                    # Pending tasks
├── cur/                    # In-progress tasks
│   └── {worker_id}/
├── done/                   # Completed tasks (log)
├── failed/                 # Failed tasks
├── state/                  # Worker state
├── log/                    # Logs
└── .recv-offset-{channel}  # Bridge polling offset
```

---

## 4. Naming Conventions

### 4.1 File Names

| Pattern | Example | Usage |
|---|---|---|
| `kebab-case` | `claude-inbox`, `inbox-recv` | Executables |
| `kebab-case.sh` | `task.sh`, `observe.sh` | Library scripts |
| `UPPER_CASE.md` | `CLAUDE.md`, `SKILL.md` | Special documents |
| `kebab-case.md` | `product-requirements.md` | General documents |

### 4.2 Task ID

```
{priority}.{YYYYMMDD-HHMMSS}.{random_hex}.task
```

Example: `5.20260215-143022.a1b2c3d4.task`

### 4.3 Worker ID

```
w.{PID}
```

Example: `w.12345`
