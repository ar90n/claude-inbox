---
name: browser-use
description: >
  This skill should be used when the user asks to "browse a website",
  "fill out a form", "click a button", "automate browser actions",
  "log into a site", or needs AI-driven web browser automation.
  Uses the browser-use Python library with Playwright and Claude.
  Requires ANTHROPIC_API_KEY in the environment.
---

# Browser Automation

Automate browser interactions using the `browser-use` Python library.
Repository: https://github.com/browser-use/browser-use

## Prerequisites

- Google Chrome installed at `/usr/bin/google-chrome-stable`
- `ANTHROPIC_API_KEY` set (used by the nested Claude agent that drives the browser)
- For visible browser: `DISPLAY` set + X11 forwarding

## Usage

Write and run a Python script using `browser-use`:

```python
import asyncio
from browser_use import Agent, Browser, BrowserConfig
from langchain_anthropic import ChatAnthropic

async def main():
    browser = Browser(config=BrowserConfig(
        chrome_instance_path='/usr/bin/google-chrome-stable',
        extra_chromium_args=['--no-sandbox', '--disable-dev-shm-usage'],
        headless=True,   # False if DISPLAY is set and you want visible browser
    ))
    agent = Agent(
        task="YOUR TASK HERE",
        llm=ChatAnthropic(model="claude-haiku-4-5-20251001"),
        browser=browser,
    )
    result = await agent.run()
    await browser.close()
    return result

print(asyncio.run(main()))
```

Run it:
```bash
python3 /tmp/browser_task.py
```

## Using an Existing Chrome Account (Logged-in Profile)

If `CHROME_PROFILE_DIR` is mounted (see docker-compose.yml), browser-use can access
existing Google logins, saved passwords, and cookies from the host Chrome profile.

```python
import asyncio, os
from browser_use import Agent, Browser, BrowserConfig
from langchain_anthropic import ChatAnthropic

async def main():
    browser = Browser(config=BrowserConfig(
        chrome_instance_path='/usr/bin/google-chrome-stable',
        extra_chromium_args=['--no-sandbox', '--disable-dev-shm-usage'],
        headless=True,
        # Use mounted Chrome profile for existing logins
        user_data_dir='/home/claude-inbox/.config/google-chrome',
    ))
    agent = Agent(
        task="YOUR TASK HERE",
        llm=ChatAnthropic(model="claude-haiku-4-5-20251001"),
        browser=browser,
    )
    result = await agent.run()
    await browser.close()
    return result

print(asyncio.run(main()))
```

**Setup**: uncomment the `CHROME_PROFILE_DIR` volume line in `docker-compose.yml` and
set `CHROME_PROFILE_DIR=~/.config/google-chrome` in `.env`.

## Notes

- Use `headless=True` for background tasks (no display needed)
- Use `headless=False` with X11 forwarding for tasks that require visible interaction (e.g., OAuth)
- `--no-sandbox` is required inside Docker containers
- `langchain_anthropic` uses `ANTHROPIC_API_KEY` — separate from Claude Code's own auth
- Use `claude-haiku-4-5-20251001` for the browser agent (fast and cheap for navigation)
- Chrome profile is mounted read-only (`:ro`) — the container cannot corrupt your host profile

## Error Handling

| Error | Action |
|---|---|
| `ANTHROPIC_API_KEY not set` | Set `ANTHROPIC_API_KEY` in `.env` and restart worker |
| Chrome crash / sandbox error | Ensure `--no-sandbox` flag is passed |
| Profile locked / in use | Close Chrome on the host first, then restart the container |
| Task failed / wrong page | Retry with more detailed task description |
