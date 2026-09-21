FROM node:22-bookworm-slim

# ca-certificates is named rather than inherited: the base image marks it auto
# and can drop it, and every curl below — and the Nix client's own fetches —
# need a CA bundle. jq because `gh --jq` does not reach into shell pipelines.
RUN apt-get update && apt-get install -y \
    git \
    curl \
    ca-certificates \
    bash \
    python3 \
    python3-venv \
    unzip \
    jq \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI, compose and buildx, for the HOST's daemon: claude-sandbox mounts
# its socket (see there), and nothing runs a daemon in here. From Docker's own
# repository, because bookworm's docker.io is 20.10 against a 29.x host and the
# compose plugin is not packaged at all. Unpinned, like kubectl and helm below:
# client and daemon negotiate an API version per connection, so a minor either
# side is fine, and --rebuild refreshes it.
#
# terraform, from HashiCorp's repository since Debian does not package it, so a
# deploy-tileai change can be validated before CI sees it. Both repositories
# ship ASCII-armored keys, which apt reads directly under a .asc name — the
# same trick as the PostgreSQL block below.
#
# A Java runtime, because the console regenerates its API client with
# openapi-generator, which is a jar. Headless: nothing here has a display.
RUN set -eux; \
    curl -fsSL https://download.docker.com/linux/debian/gpg \
        -o /usr/share/keyrings/docker-archive-keyring.asc; \
    curl -fsSL https://apt.releases.hashicorp.com/gpg \
        -o /usr/share/keyrings/hashicorp-archive-keyring.asc; \
    codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"; \
    arch="$(dpkg --print-architecture)"; \
    echo "deb [arch=${arch} signed-by=/usr/share/keyrings/docker-archive-keyring.asc] https://download.docker.com/linux/debian ${codename} stable" \
        > /etc/apt/sources.list.d/docker.list; \
    echo "deb [arch=${arch} signed-by=/usr/share/keyrings/hashicorp-archive-keyring.asc] https://apt.releases.hashicorp.com ${codename} main" \
        > /etc/apt/sources.list.d/hashicorp.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        docker-ce-cli \
        docker-compose-plugin \
        docker-buildx-plugin \
        terraform \
        default-jre-headless; \
    rm -rf /var/lib/apt/lists/*

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

# kubectl + helm + kind (latest stable, static binaries from upstream)
#
# kind drives the host's Docker over the mounted socket, so its nodes are
# ordinary containers on the host — `docker ps` there shows them, and the
# kubeconfig it writes lands in the host's ~/.kube through that mount.
ARG KUBECTL_VERSION=stable
ARG HELM_VERSION=latest
ARG KIND_VERSION=latest
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
    rm -rf /tmp/helm.tgz "/tmp/linux-${ARCH}"; \
    if [ "$KIND_VERSION" = "latest" ]; then \
        KIND_VERSION="$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')"; \
    fi; \
    curl -fsSLo /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${ARCH}"; \
    chmod +x /usr/local/bin/kind

# uv, for the Python SDK's generator and tests. Astral's installer, into
# /usr/local/bin so it is on PATH for every user; left alone it would install
# under ~/.local/bin and edit shell rc files, neither of which this image
# wants. Its cache is $XDG_CACHE_HOME/uv, i.e. the cache volume, so downloads
# outlive the container.
RUN curl -LsSf https://astral.sh/uv/install.sh \
    | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh

# npm 11. The console's .npmrc sets engine-strict and its package.json wants
# npm >=11.10, so anything older refuses to install (EBADENGINE) — on purpose,
# because the release-age cooldown it relies on does not exist in older npm.
# Node 22 ships 10.9; this replaces the global npm in place. A flake workspace
# puts its own node ahead of this on PATH anyway (tile-ai's is 24.x with npm
# 11.17); this is for workspaces without one.
RUN npm install -g npm@11

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

# Nix client configuration. There is no Nix INSTALLED here: claude-sandbox
# bind-mounts the host's /nix/store read-only, the host daemon's socket, and
# the directory holding the host's own `nix` binary at /opt/nix/bin (see the
# launcher). That binary is a store path linked against store paths, so it runs
# unchanged on Debian once the store is mounted — and being the host's own, it
# always speaks the host daemon's protocol, which a Nix installed in the image
# could not promise. Evaluation runs in here; building, downloading and garbage
# collection happen on the host with the host's settings, and what lands in the
# store is shared with the host's own `nix develop` in the same repository.
#
# What the client needs from this side: flakes switched on (the host's
# nix.conf is not visible here), the daemon named rather than guessed from a
# /nix/var/nix/db that does not exist, and a CA bundle for the fetches it does
# itself — flake inputs come through the client, not the daemon. The
# entrypoint below is what turns this into a loaded development shell.
RUN mkdir -p /etc/nix \
    && echo 'experimental-features = nix-command flakes' > /etc/nix/nix.conf

ARG CLAUDE_CODE_VERSION=2.1.276

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

# The entrypoint: load the workspace's Nix development shell, if it has one,
# then hand over to Claude Code.
#
# HOW: the way nix-direnv does it. `nix print-dev-env` emits a bash script that
# recreates the environment `nix develop` would give — PATH, the cgo flags, the
# pkg-config path, the stdenv's variables — and evaluating it in this process
# means claude, and every command claude runs, inherit that environment. No
# `nix develop -c` in front of every command, no shell to remember to enter,
# which is the property the repositories using flakes are built around.
#
# It steps aside, with a line saying so, when /workspace has no flake.nix, when
# claude-sandbox found no Nix on the host to lend, or when
# CLAUDE_SANDBOX_DEVSHELL=off (the launcher's --no-devshell). If loading fails —
# no network, a flake with no devShell, a shell that does not build — that is
# reported and the plain image is used: a broken shell must not mean no sandbox.
RUN install -m 0755 /dev/stdin /usr/local/bin/sandbox-entrypoint <<'EOF'
#!/usr/bin/env bash
# Load /workspace's flake devShell into this environment, then exec claude.
set -u

# Produces the shell's environment as a bash script in $devshell_script, or
# leaves it empty with a line on stderr saying why.
devshell_script=""
find_devshell() {
    [ "${CLAUDE_SANDBOX_DEVSHELL:-auto}" != "off" ] || return 0
    [ -f /workspace/flake.nix ] || return 0
    if ! command -v nix >/dev/null 2>&1; then
        echo "   dev shell: /workspace has a flake.nix but the host lent no Nix — not loaded" >&2
        return 0
    fi
    echo "   dev shell: loading from /workspace/flake.nix (the first time on a repository downloads it)" >&2
    # stderr stays on the terminal so a long first download shows its progress.
    if ! devshell_script="$(cd /workspace && nix print-dev-env)"; then
        devshell_script=""
        echo "   dev shell: NOT loaded — nix print-dev-env failed, see above (CLAUDE_SANDBOX_DEVSHELL=off skips this)" >&2
    fi
}
find_devshell

# The eval happens HERE, at top level, and not in the function above: the
# script is a series of `declare -x`, and declare inside a function makes the
# variable local to it — the shell would load and then vanish before claude.
if [ -n "$devshell_script" ]; then
    # The script sets PATH to the shell's and appends the one it found, points
    # TMPDIR and friends at a fresh mktemp directory, and can carry the build
    # sandbox's certificate path. Keep this container's own values for those:
    # tools should keep finding /tmp, and the Nix client its CA bundle.
    saved_path="$PATH"
    declare -A before=()
    for v in TMPDIR TMP TEMP TEMPDIR NIX_SSL_CERT_FILE SSL_CERT_FILE NIX_REMOTE; do
        if declare -p "$v" >/dev/null 2>&1; then before[$v]="${!v}"; fi
    done

    set +u
    eval "$devshell_script"
    set -u

    for v in TMPDIR TMP TEMP TEMPDIR NIX_SSL_CERT_FILE SSL_CERT_FILE NIX_REMOTE; do
        if [ -n "${before[$v]+set}" ]; then export "$v=${before[$v]}"; else unset "$v"; fi
    done
    if [ -n "${NIX_BUILD_TOP:-}" ]; then rmdir "$NIX_BUILD_TOP" 2>/dev/null || true; fi
    unset NIX_BUILD_TOP
    # Belt and braces: the image's own tools (claude, docker, helm, psql...)
    # must stay reachable behind the shell's, whatever this nix version did.
    case ":$PATH:" in
        *":$saved_path:"*) ;;
        *) PATH="$PATH:$saved_path" ;;
    esac
    export PATH
    echo "   dev shell: loaded${name:+ ($name)}" >&2
fi

exec claude "$@"
EOF

USER node
ENV TERM=xterm-256color COLORTERM=truecolor \
    PATH="/home/node/.local/bin:/opt/nix/bin:/opt/mempalace/bin:/usr/lib/postgresql/${PG_MAJOR}/bin:${PATH}" \
    DISABLE_AUTOUPDATER=1 \
    MEMPALACE_PYTHON=/usr/local/bin/mempalace-python-capped \
    NIX_REMOTE=daemon \
    NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    GOMODCACHE=/home/node/.cache/go/pkg/mod

# GOMODCACHE above: Go's build cache already lands in $XDG_CACHE_HOME/go-build,
# the cache volume, but the module cache defaults to ~/go/pkg/mod, which is not
# a volume — so `go mod tidy` and `go work vendor` re-downloaded everything each
# session. Same volume, same persistence.

# helm-unittest, for the charts' tests. A helm plugin, so it is installed as
# the user helm will run as, into ~/.local/share/helm/plugins — a plain copy
# holding the binary its install hook downloads, so nothing points back into
# the clone helm makes while installing. That clone would land in
# ~/.cache/helm, which the cache volume hides at runtime; pointed at /tmp and
# dropped instead, so it does not sit in the layer for nothing. --verify=false:
# this helm verifies plugin signatures by default and the plugin's releases
# carry none. Unpinned, like helm itself.
RUN HELM_CACHE_HOME=/tmp/helm-cache \
    helm plugin install https://github.com/helm-unittest/helm-unittest.git --verify=false \
    && rm -rf /tmp/helm-cache

# Native installer (matches the host's installMethod=native shared via .claude.json)
# and installs into the user-owned /home/node/.local so /doctor is happy.
# Version is pinned here; bump CLAUDE_CODE_VERSION and `claude-sandbox --rebuild`.
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_CODE_VERSION}"

WORKDIR /workspace

ENTRYPOINT ["sandbox-entrypoint"]
