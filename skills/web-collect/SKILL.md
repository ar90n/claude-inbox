---
name: web-collect
description: >
  This skill should be used when the user asks to "collect tech news",
  "get today's HN top stories", "fetch GitHub trending", "gather daily
  digest", or needs source material for a tech podcast or briefing.
  Collects from Hacker News API and GitHub Search API.
---

# Web Collection

Collect today's notable tech information from public APIs.

## Sources

### Hacker News

Use the Firebase API (no auth required, no rate limit):

```bash
# Top story IDs
curl -sf 'https://hacker-news.firebaseio.com/v0/topstories.json' | jq '.[0:10][]'
# Per-item detail
curl -sf "https://hacker-news.firebaseio.com/v0/item/${id}.json"
```

Key fields: `title`, `url`, `score`, `descendants` (comment count).
Items with `url: null` are Ask/Show HN — link to `https://news.ycombinator.com/item?id={id}`.

### GitHub Trending

Use the Search API (10 req/min unauthenticated, 30 with `$GITHUB_TOKEN`):

```bash
date=$(date -d '1 day ago' +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)
curl -sf "https://api.github.com/search/repositories?q=created:>${date}&sort=stars&order=desc&per_page=10"
```

If `$GITHUB_TOKEN` is set, add `-H "Authorization: token $GITHUB_TOKEN"`.

## Output Format

Return Markdown:

```
# Tech Digest YYYY-MM-DD

## Hacker News Top 10
1. [Title](url) — Score: N, Comments: N
...

## GitHub Trending (24h)
1. [owner/repo](url) ★N — description (language)
...

## Summary
3-5 sentences: major themes, standout projects, notable trends.
```

## Error Handling

- Timeout: 10s per request, 1 retry.
- Partial failure: output what succeeded, note what failed.
- Total failure: report the error clearly.
