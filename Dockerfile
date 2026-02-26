FROM node:22-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash curl jq python3 python3-pip inotify-tools ca-certificates xauth unzip \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
        -o /tmp/google-chrome.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/google-chrome.deb \
    && rm /tmp/google-chrome.deb \
    && rm -rf /var/lib/apt/lists/*

# hadolint ignore=DL3016
RUN npm install -g @anthropic-ai/claude-code claude-mem @playwright/mcp \
    && npm cache clean --force

# Install Bun (required by claude-mem worker service)
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash

# Use system Google Chrome for Playwright (avoids downloading a second browser)
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/google-chrome-stable

# hadolint ignore=DL3013
RUN pip3 install --no-cache-dir --break-system-packages \
        notebooklm-mcp-cli

# Pre-create home dir and Chrome-required subdirs with open permissions
# so any UID (via docker-compose user:) can write to them
RUN mkdir -p /home/claude-inbox/.cache /home/claude-inbox/.config \
             /home/claude-inbox/.pki/nssdb \
    && chmod -R 777 /home/claude-inbox

WORKDIR /app
COPY bin/ bin/
COPY lib/ lib/
COPY skills/ skills/
COPY prompts/ prompts/

