FROM node:22-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash curl jq python3 python3-pip inotify-tools ca-certificates xauth unzip \
    && rm -rf /var/lib/apt/lists/*

# hadolint ignore=DL3008
RUN curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
        -o /tmp/google-chrome.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/google-chrome.deb \
    && rm /tmp/google-chrome.deb \
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

# Use system Google Chrome for Playwright (avoids downloading a second browser)
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/google-chrome-stable

# hadolint ignore=DL3013
RUN pip3 install --no-cache-dir --break-system-packages \
        notebooklm-mcp-cli

# Create user with host UID/GID (build with: docker compose build --build-arg UID=$(id -u) GID=$(id -g))
ARG UID
ARG GID
# hadolint ignore=DL3046
RUN groupadd -g "$GID" claude-inbox 2>/dev/null || true \
    && useradd -l -u "$UID" -g "$GID" -d /home/claude-inbox -s /bin/bash -m claude-inbox 2>/dev/null || true \
    && mkdir -p /home/claude-inbox/.cache /home/claude-inbox/.config \
               /home/claude-inbox/.pki/nssdb \
               /home/claude-inbox/.claude/debug \
               /home/claude-inbox/.claude/projects \
               /home/claude-inbox/.claude-mem \
               /workdir \
    && chown -R "$UID:$GID" /home/claude-inbox /workdir

WORKDIR /app
COPY bin/ bin/
COPY lib/ lib/
COPY skills/ skills/
COPY prompts/ prompts/

USER claude-inbox

