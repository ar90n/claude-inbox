---
name: notebooklm
description: >
  This skill should be used when the user asks to "create a podcast",
  "generate audio overview", "make a NotebookLM episode", or needs to
  convert text/articles into an AI-generated podcast via Google NotebookLM.
  Requires the nlm CLI (notebooklm-mcp-cli, MIT license).
---

# NotebookLM Podcast Generation

Generate audio podcasts using the `nlm` CLI.
Repository: https://github.com/jacob-bd/notebooklm-mcp-cli

## Prerequisites

- `nlm` installed: `pip install notebooklm-mcp-cli`
- Authenticated: run `nlm login` with X11 forwarding (Cookie-based, lasts 2-4 weeks)
  - Config stored in `~/.config/nlm/` — persists via bind-mount or host install

```bash
# From inside the worker container (X11 forwarding required):
docker exec -it -e DISPLAY=$DISPLAY \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  claude-inbox-worker-1 nlm login
```

## Workflow

### 1. Create notebook

```bash
notebook_id=$(nlm notebook create --title "Title" --json | jq -r '.id')
```

### 2. Add sources

```bash
# Text content
nlm source add "$notebook_id" --text "$(cat content.md)"
# URL
nlm source add "$notebook_id" --url "https://..."
```

Max 50 sources per notebook. Wait 10-30s after adding for processing.

### 3. Generate audio

```bash
nlm audio create "$notebook_id" --confirm --json
```

Takes 2-5 minutes. CLI polls until complete (timeout: 10 min).

### 4. Get audio URL

```bash
audio_url=$(nlm audio get "$notebook_id" --json | jq -r '.url')
```

URL is temporary (expires in hours).

## Error Handling

| Error | Action |
|---|---|
| 401 Unauthorized | Auth expired. Report that `nlm login` is needed. |
| Audio timeout | NotebookLM issue. Report failure. |
| Source too large | Truncate to ~5000 words and retry. |

## Output

Return the notebook ID, audio URL, and title.
