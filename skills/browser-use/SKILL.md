---
name: browser-use
description: >
  This skill should be used when the user asks to "browse a website",
  "fill out a form", "click a button", "automate browser actions",
  "log into a site", "scrape a page", or needs web browser automation.
  Uses Playwright MCP connected to a remote Chrome instance via CDP.
---

# Browser Automation

Browser automation via Playwright MCP, connected to remote Chrome (kasmweb) via CDP.

## Setup

No setup required — Playwright MCP is pre-installed in the container.
Chrome runs as a sidecar container (`network_mode: "service:worker"`), sharing localhost with the worker. Connected via CDP (`CHROME_CDP_URL`).

## Tools

| Category | Tools |
|---|---|
| Navigation | `browser_navigate`, `browser_go_back`, `browser_go_forward`, `browser_wait` |
| Interaction | `browser_click`, `browser_type`, `browser_select_option`, `browser_hover`, `browser_drag`, `browser_press_key` |
| Data | `browser_snapshot`, `browser_take_screenshot`, `browser_network_requests`, `browser_console_messages` |
| Tabs | `browser_tab_new`, `browser_tab_select`, `browser_tab_close`, `browser_tab_list` |

## Usage

```
1. browser_navigate → "https://example.com"
2. browser_snapshot → read page content (accessibility tree)
3. browser_click → interact with elements
4. browser_type → fill in forms
```

## Notes

- Chrome runs as a worker sidecar (shared localhost), connected via `CHROME_CDP_URL` (default: `http://localhost:9222`)
- Logged-in sessions persist across tasks (shared Chrome profile volume)
- Chrome GUI is accessible at https://localhost:6901 for visual debugging (VNC)
- For long-running browser tasks, break into steps using `create-task`

## Error Handling

| Error | Action |
|---|---|
| No browser tools | Playwright MCP is pre-installed; check `@playwright/mcp` in node modules |
| CDP connection failed | Check that chrome service is running: `docker compose up -d chrome` |
| Navigation timeout | `browser_wait` before next action |
| Element not found | `browser_snapshot` to see available elements |
