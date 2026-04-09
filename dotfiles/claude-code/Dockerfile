FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y \
    git \
    curl \
    bash \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://claude.ai/install.sh | bash \
    && cp /root/.local/bin/claude /usr/local/bin/claude \
    && chmod +x /usr/local/bin/claude

RUN mkdir -p /home/node/.local/bin \
    && cp /usr/local/bin/claude /home/node/.local/bin/claude \
    && chown -R node:node /home/node/.local

USER node
ENV PATH="/home/node/.local/bin:$PATH"
ENV TERM=xterm-256color
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/claude"]
