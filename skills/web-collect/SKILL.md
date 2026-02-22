---
name: web-collect
description: >
  This skill should be used when the user asks to "collect tech news",
  "get today's HN top stories", "fetch GitHub trending", "gather daily
  digest", or needs source material for a tech podcast or briefing.
  Collects from Hacker News, GitHub Trending, Hackaday, Reddit, Lobsters, dev.to, and Zenn.
---

# Web Collection

Collect today's notable tech information from public APIs.
All sources are unauthenticated (except GitHub with optional token).

## Sources

### Hacker News

Firebase API (no auth, no rate limit):

```bash
# Top story IDs
curl -sf 'https://hacker-news.firebaseio.com/v0/topstories.json' | jq '.[0:10][]'
# Per-item detail
curl -sf "https://hacker-news.firebaseio.com/v0/item/${id}.json"
```

Key fields: `title`, `url`, `score`, `descendants` (comment count).
Items with `url: null` are Ask/Show HN — link to `https://news.ycombinator.com/item?id={id}`.

### GitHub Trending

Search API (10 req/min unauthenticated, 30 with `$GITHUB_TOKEN`):

```bash
date=$(date -d '1 day ago' +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)
curl -sf "https://api.github.com/search/repositories?q=created:>${date}&sort=stars&order=desc&per_page=10"
```

If `$GITHUB_TOKEN` is set, add `-H "Authorization: token $GITHUB_TOKEN"`.

### Hackaday

RSS feed (no auth):

```bash
curl -sf 'https://hackaday.com/feed/' | head -c 100000
```

RSS (XML) format. Extract `<item>` elements: `<title>`, `<link>`, `<description>`, `<dc:creator>`.
Parse with simple grep/sed or ask Claude to extract from the XML.

### Reddit

JSON API (no auth for read, append `.json` to any Reddit URL):

```bash
# Top posts from a subreddit (past 24h)
curl -sf -H 'User-Agent: claude-inbox/1.0' \
  'https://www.reddit.com/r/programming/top.json?t=day&limit=10'
```

Recommended subreddits:

| Subreddit | Topic |
|---|---|
| r/programming | General programming |
| r/technology | Tech industry news |
| r/netsec | Security / infosec |
| r/machinelearning | ML/AI research |
| r/selfhosted | Self-hosting / homelab |
| r/linux | Linux |
| r/devops | DevOps / infrastructure |
| r/ExperiencedDevs | Senior dev discussions |

Key fields in response: `data.children[].data.{title, url, score, num_comments, subreddit, permalink}`.
Link to comments: `https://www.reddit.com{permalink}`.

**Important:** Always set `User-Agent` header. Reddit blocks default curl UA.

### Lobsters

JSON API (no auth):

```bash
curl -sf 'https://lobste.rs/hottest.json' | jq '.[0:10]'
```

Key fields: `title`, `url`, `score`, `comment_count`, `tags`, `comments_url`.
Tags are useful for categorization (e.g., `ai`, `security`, `networking`, `programming`).

### dev.to

JSON API (no auth):

```bash
# Trending articles (past 24h, by reactions)
curl -sf 'https://dev.to/api/articles?top=1&per_page=10'
# Or latest
curl -sf 'https://dev.to/api/articles?per_page=10'
```

Key fields: `title`, `url`, `user.username`, `positive_reactions_count`, `comments_count`, `tag_list`, `description`.

### Zenn

RSS feed (no auth):

```bash
# Trending articles
curl -sf 'https://zenn.dev/feed'
# Trending tech articles
curl -sf 'https://zenn.dev/api/articles?order=daily&count=10'
```

The API (`/api/articles`) returns JSON. Key fields: `title`, `path`, `emoji`, `liked_count`, `user.username`.
Full URL: `https://zenn.dev{path}`.

Note: Zenn is a Japanese tech blog platform. Content is primarily in Japanese.
Include Zenn when the user communicates in Japanese or explicitly requests it.

## Output Format

Return Markdown with raw collected data. This output is consumed by downstream
steps (summarize, podcast, notify) — not sent directly to users.

```
# Tech Digest YYYY-MM-DD

## Hacker News Top 10
1. [Title](url) — Score: N, Comments: N
...

## GitHub Trending (24h)
1. [owner/repo](url) ★N — description (language)
...

## Hackaday
1. [Title](url) — summary
...

## Reddit Highlights
### r/programming
1. [Title](url) — ▲N, Comments: N
...

## Lobsters Top 10
1. [Title](url) [tags] — Score: N, Comments: N
...

## dev.to Trending
1. [Title](url) by @username — ❤N, Comments: N [tags]
...

## Zenn トレンド
1. [Title](url) by @username — ♡N
...
```

Include only the sections requested. "tech news" → all sources. "HN top" → HN only.

## Error Handling

- Timeout: 10s per request, 1 retry.
- Partial failure: output what succeeded, note what failed.
- Total failure: report the error clearly.
- Reddit 429 (rate limit): wait 2s and retry once. If still failing, skip and note.
