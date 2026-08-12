FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y \
    git \
    curl \
    bash \
    python3 \
    python3-venv \
    unzip \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2 (needed for EKS auth via `aws eks get-token`)
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) AWS_ARCH=x86_64 ;; \
        arm64) AWS_ARCH=aarch64 ;; \
        *) echo "unsupported arch" && exit 1 ;; \
    esac; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli; \
    rm -rf /tmp/awscliv2.zip /tmp/aws

# kubectl + helm (latest stable, static binaries from upstream)
ARG KUBECTL_VERSION=stable
ARG HELM_VERSION=latest
RUN set -eux; \
    ARCH="$(dpkg --print-architecture)"; \
    if [ "$KUBECTL_VERSION" = "stable" ]; then \
        KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"; \
    fi; \
    curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"; \
    chmod +x /usr/local/bin/kubectl; \
    if [ "$HELM_VERSION" = "latest" ]; then \
        HELM_VERSION="$(curl -fsSL https://api.github.com/repos/helm/helm/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')"; \
    fi; \
    curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" -o /tmp/helm.tgz; \
    tar -xzf /tmp/helm.tgz -C /tmp; \
    mv "/tmp/linux-${ARCH}/helm" /usr/local/bin/helm; \
    chmod +x /usr/local/bin/helm; \
    rm -rf /tmp/helm.tgz "/tmp/linux-${ARCH}"

# PostgreSQL + pgvector, for projects whose control plane is a Postgres app.
# From PGDG rather than Debian: bookworm carries only postgresql-15, and no
# pgvector at any version. apt reads an ASCII-armored key directly when the
# filename ends in .asc, which avoids pulling in gnupg purely to dearmor it.
#
# Binaries only — no service is started and none is needed. This container runs
# unprivileged, and postgres refuses to run as root regardless, so a cluster
# lives in userspace wherever you initdb it:
#   initdb -D /workspace/.pgdata -U <user> --auth=trust
#   pg_ctl -D /workspace/.pgdata -o "-p 5433 -k /tmp" -l /tmp/pg.log start
# The cluster the package creates for itself under /var/lib/postgresql is
# dropped: nothing here can start it, and it only wastes layer space.
ARG PG_MAJOR=16
RUN set -eux; \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        -o /usr/share/keyrings/postgresql-archive-keyring.asc; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/postgresql-archive-keyring.asc] https://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo "$VERSION_CODENAME")-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        "postgresql-${PG_MAJOR}" "postgresql-${PG_MAJOR}-pgvector"; \
    pg_dropcluster --stop "${PG_MAJOR}" main || true; \
    rm -rf /var/lib/apt/lists/*

ARG CLAUDE_CODE_VERSION=2.1.220

RUN python3 -m venv /opt/mempalace \
    && /opt/mempalace/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/mempalace/bin/pip install --no-cache-dir mempalace \
    && ln -s /opt/mempalace/bin/mempalace /usr/local/bin/mempalace \
    && mkdir -p /home/node/.mempalace /home/node/.cache \
    && chown -R node:node /home/node/.mempalace /home/node/.cache

# Cap MemPalace's background miner so its ONNX embedding pass can't saturate
# every core (it otherwise defaults its intra-op thread pool to all CPUs and
# pegged ~15/22 cores). MemPalace spawns the miner via $MEMPALACE_PYTHON, so we
# point that at a wrapper that pins CPU affinity + lowers priority. The
# long-running MCP server (interactive search) does not use this path, so it
# stays unthrottled. Tune the cap at runtime with MEMPALACE_MINE_CPUS.
RUN install -m 0755 /dev/stdin /usr/local/bin/mempalace-python-capped <<'EOF'
#!/usr/bin/env bash
# Run MemPalace's Python under a CPU cap (affinity + niceness).
PY=/opt/mempalace/bin/python3
CPUS="${MEMPALACE_MINE_CPUS:-6}"
total="$(nproc)"
[ "$CPUS" -lt 1 ] && CPUS=1
[ "$CPUS" -gt "$total" ] && CPUS="$total"
last="$((CPUS - 1))"
export OMP_NUM_THREADS="$CPUS" OPENBLAS_NUM_THREADS="$CPUS" \
       MKL_NUM_THREADS="$CPUS" NUMEXPR_NUM_THREADS="$CPUS" \
       TOKENIZERS_PARALLELISM=false
exec taskset -c "0-${last}" nice -n 15 "$PY" "$@"
EOF

USER node
ENV TERM=xterm-256color COLORTERM=truecolor \
    PATH="/home/node/.local/bin:/opt/mempalace/bin:/usr/lib/postgresql/${PG_MAJOR}/bin:${PATH}" \
    DISABLE_AUTOUPDATER=1 \
    MEMPALACE_PYTHON=/usr/local/bin/mempalace-python-capped

# Native installer (matches the host's installMethod=native shared via .claude.json)
# and installs into the user-owned /home/node/.local so /doctor is happy.
# Version is pinned here; bump CLAUDE_CODE_VERSION and `claude-sandbox --rebuild`.
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION}"

WORKDIR /workspace

ENTRYPOINT ["claude"]
