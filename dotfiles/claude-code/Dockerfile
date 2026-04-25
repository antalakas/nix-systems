FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y \
    git \
    curl \
    bash \
    python3 \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

RUN python3 -m venv /opt/mempalace \
    && /opt/mempalace/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/mempalace/bin/pip install --no-cache-dir mempalace \
    && ln -s /opt/mempalace/bin/mempalace /usr/local/bin/mempalace \
    && mkdir -p /home/node/.mempalace /home/node/.cache \
    && chown -R node:node /home/node/.mempalace /home/node/.cache

USER node
ENV TERM=xterm-256color COLORTERM=truecolor PATH="/opt/mempalace/bin:${PATH}"
WORKDIR /workspace

ENTRYPOINT ["claude"]
