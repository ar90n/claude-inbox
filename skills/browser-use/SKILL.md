---
name: browser-use
description: >
  This skill should be used when the user asks to "browse a website",
  "fill out a form", "click a button", "automate browser actions",
  "log into a site", "scrape a page", or needs web browser automation.
  Two backends: Claude in Chrome (preferred) and Playwright MCP (fallback).
---

# Browser Automation

Two browser backends are available. **Check your tool list to determine which to use.**

## Tool Detection

1. If you have a `computer` tool (type=computer_20250124) → use **Claude in Chrome**
2. If you have `browser_navigate`, `browser_click` etc. → use **Playwright MCP**
3. If both are available → prefer **Claude in Chrome**

## Claude in Chrome

Claude's native browser control. You see the screen and interact naturally.

- You have a `computer` tool — use it to take screenshots, click, type, scroll
- Works like computer_use: coordinate-based interaction with visual feedback
- Chrome profile and cookies are available (logged-in sessions persist)
- Requires: `CLAUDE_CHROME=1` + `DISPLAY` (X11)

## Playwright MCP

Headless browser automation via MCP tools. No display needed.

Setup: `bin/claude-inbox-setup playwright`

### Tools

| Category | Tools |
|---|---|
| Navigation | `browser_navigate`, `browser_go_back`, `browser_go_forward`, `browser_wait` |
| Interaction | `browser_click`, `browser_type`, `browser_select_option`, `browser_hover`, `browser_drag`, `browser_press_key` |
| Data | `browser_snapshot`, `browser_take_screenshot`, `browser_network_requests`, `browser_console_messages` |
| Tabs | `browser_tab_new`, `browser_tab_select`, `browser_tab_close`, `browser_tab_list` |

### Usage

```
1. browser_navigate → "https://example.com"
2. browser_snapshot → read page content (accessibility tree)
3. browser_click → interact with elements
4. browser_type → fill in forms
```

## Comparison

| | Claude in Chrome | Playwright MCP |
|---|---|---|
| Tool to check | `computer` | `browser_navigate` |
| Display | Required (X11) | Not needed (headless) |
| Interaction | Visual (screenshots + coordinates) | Accessibility tree |
| Cookies/login | Chrome profile persists | Fresh session each time |
| Best for | Visual tasks, complex JS sites | Structured scraping, automation |

## Notes

- For long-running browser tasks, break into steps using `create-task`
- Some sites detect headless browsers — Claude in Chrome avoids this

## Error Handling

| Error | Action |
|---|---|
| No browser tools | Run `bin/claude-inbox-setup playwright` or set `CLAUDE_CHROME=1` |
| Navigation timeout | `browser_wait` before next action |
| Element not found | `browser_snapshot` to see available elements |
