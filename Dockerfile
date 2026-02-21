FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash curl jq python3 python3-pip inotify-tools ca-certificates xauth unzip \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
        -o /tmp/google-chrome.deb \
    && apt-get update \
    && apt-get install -y /tmp/google-chrome.deb \
    && rm /tmp/google-chrome.deb \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code claude-mem \
    && npm cache clean --force

# Install Bun (required by claude-mem worker service)
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash

# Use system Google Chrome for Playwright (avoids downloading a second browser)
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/google-chrome-stable

RUN pip3 install --break-system-packages \
        notebooklm-mcp-cli \
        browser-use playwright langchain-anthropic

# Pre-create home dir so any UID (via docker-compose user:) can write to it
RUN mkdir -p /home/claude-inbox && chmod 777 /home/claude-inbox

WORKDIR /app
COPY bin/ bin/
COPY lib/ lib/
COPY skills/ skills/
COPY prompts/ prompts/

