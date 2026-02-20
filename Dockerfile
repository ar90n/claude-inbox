FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash curl jq python3 inotify-tools ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code \
    && npm cache clean --force

WORKDIR /app
COPY bin/ bin/
COPY lib/ lib/
COPY skills/ skills/
COPY prompts/ prompts/

