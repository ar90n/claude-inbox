FROM node:22-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash curl jq python3 python3-pip inotify-tools ca-certificates unzip gosu socat \
    && rm -rf /var/lib/apt/lists/*

# hadolint ignore=DL3016
RUN npm install -g @anthropic-ai/claude-code claude-mem @playwright/mcp \
    && npm cache clean --force

# Install Bun baseline build (AVX not required — works on Celeron/older CPUs)
RUN curl -fsSL https://github.com/oven-sh/bun/releases/latest/download/bun-linux-x64-baseline.zip \
        -o /tmp/bun.zip \
    && unzip -o /tmp/bun.zip -d /tmp/bun \
    && mv /tmp/bun/bun-linux-x64-baseline/bun /usr/local/bin/bun \
    && chmod +x /usr/local/bin/bun \
    && rm -rf /tmp/bun /tmp/bun.zip

# hadolint ignore=DL3013
RUN pip3 install --no-cache-dir --break-system-packages \
        notebooklm-mcp-cli

# Create default user (entrypoint remaps UID/GID at runtime via gosu)
# node:22-slim ships with a 'node' user at UID 1000; remove it first.
RUN userdel -r node 2>/dev/null || true \
    && useradd -l -u 1000 -d /home/claude-inbox -s /bin/bash -m claude-inbox \
    && mkdir -p /home/claude-inbox/.cache /home/claude-inbox/.config \
               /home/claude-inbox/.notebooklm-mcp-cli \
               /home/claude-inbox/.claude/debug \
               /home/claude-inbox/.claude/projects \
               /home/claude-inbox/.claude-mem \
               /workdir \
    && chown -R claude-inbox:claude-inbox /home/claude-inbox /workdir

WORKDIR /app
COPY docker-entrypoint.sh /usr/local/bin/
COPY bin/ bin/
COPY lib/ lib/
COPY skills/ skills/
COPY prompts/ prompts/

ENTRYPOINT ["docker-entrypoint.sh"]

