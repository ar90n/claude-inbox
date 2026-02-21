FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash curl jq python3 python3-pip inotify-tools ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code \
    && npm cache clean --force

RUN pip3 install --break-system-packages notebooklm-mcp-cli

# Pre-create home dir so any UID (via docker-compose user:) can write to it
RUN mkdir -p /home/claude-inbox && chmod 777 /home/claude-inbox

WORKDIR /app
COPY bin/ bin/
COPY lib/ lib/
COPY skills/ skills/
COPY prompts/ prompts/

