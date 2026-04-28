FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y \
    git \
    curl \
    bash \
    python3 \
    python3-venv \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
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
