---
name: google-workspace
description: >
  This skill should be used when the user asks to "check my email",
  "read Gmail", "list calendar events", "check my schedule",
  "list Drive files", "upload to Drive", "read spreadsheet",
  "create a Google Doc", "send an email", or needs to interact
  with any Google Workspace service (Gmail, Calendar, Drive, Sheets, Docs, Chat).
---

# Google Workspace

Interact with Google Workspace services via the `gws` CLI.

Requires authentication: run `bin/claude-inbox-setup gws-login` first.

## Command Syntax

```bash
gws <service> <method> --params '{"key":"value"}'
```

Output is JSON. Parse with `jq`.

## Gmail

```bash
# List recent messages
gws gmail users.messages.list --params '{"userId":"me","maxResults":10}'

# Get a specific message (full body)
gws gmail users.messages.get --params '{"userId":"me","id":"MSG_ID","format":"full"}'

# Search messages
gws gmail users.messages.list --params '{"userId":"me","q":"from:someone@example.com","maxResults":5}'

# List labels
gws gmail users.labels.list --params '{"userId":"me"}'
```

### Sending Email

To send email, construct a base64url-encoded RFC 2822 message:

```bash
raw=$(printf 'To: recipient@example.com\r\nSubject: Hello\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nMessage body here' | base64 -w0 | tr '+/' '-_' | tr -d '=')
gws gmail users.messages.send --params "{\"userId\":\"me\",\"requestBody\":{\"raw\":\"$raw\"}}"
```

## Calendar

```bash
# List upcoming events
gws calendar events.list --params '{"calendarId":"primary","timeMin":"2026-03-05T00:00:00Z","maxResults":10,"singleEvents":true,"orderBy":"startTime"}'

# Get a specific event
gws calendar events.get --params '{"calendarId":"primary","eventId":"EVENT_ID"}'

# Create an event
gws calendar events.insert --params '{"calendarId":"primary","requestBody":{"summary":"Meeting","start":{"dateTime":"2026-03-06T10:00:00+09:00"},"end":{"dateTime":"2026-03-06T11:00:00+09:00"}}}'

# List calendars
gws calendar calendarList.list
```

## Drive

```bash
# List files
gws drive files.list --params '{"pageSize":10,"q":"trashed=false","fields":"files(id,name,mimeType,modifiedTime)"}'

# Search files by name
gws drive files.list --params '{"q":"name contains '\''report'\'' and trashed=false","pageSize":10}'

# Get file metadata
gws drive files.get --params '{"fileId":"FILE_ID","fields":"id,name,mimeType,size,modifiedTime,webViewLink"}'

# Download file content (text-based)
gws drive files.export --params '{"fileId":"FILE_ID","mimeType":"text/plain"}'
```

## Sheets

```bash
# Read cell range
gws sheets spreadsheets.values.get --params '{"spreadsheetId":"SHEET_ID","range":"Sheet1!A1:D10"}'

# Write to cells
gws sheets spreadsheets.values.update --params '{"spreadsheetId":"SHEET_ID","range":"Sheet1!A1","valueInputOption":"USER_ENTERED","requestBody":{"values":[["Header1","Header2"],["val1","val2"]]}}'

# Append rows
gws sheets spreadsheets.values.append --params '{"spreadsheetId":"SHEET_ID","range":"Sheet1!A1","valueInputOption":"USER_ENTERED","requestBody":{"values":[["new1","new2"]]}}'
```

## Docs

```bash
# Get document content
gws docs documents.get --params '{"documentId":"DOC_ID"}'

# Create a new document
gws docs documents.create --params '{"requestBody":{"title":"New Document"}}'
```

## Workflow

1. Run the appropriate `gws` command
2. Parse the JSON output with `jq`
3. Present results to the user in a readable format
4. For multi-step operations (e.g., "summarize my latest emails"), chain commands

## Error Handling

- **Not authenticated**: Report that Google Workspace is not configured and suggest running `bin/claude-inbox-setup gws-login`
- **API error**: Report the error message from the response
- **Permission denied**: The OAuth scope may not cover this API. Suggest re-running `gws auth login` with the needed scope
- **Rate limit**: Wait and retry once
