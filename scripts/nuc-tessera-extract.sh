#!/usr/bin/env bash
#
# nuc-tessera-extract.sh — save the handful of things a later Tessera
# re-deploy cannot regenerate. No database, no Borg, no outputs/: the data
# is disposable and users re-onboard after the redeploy.
#
# Written for the one-way trip in August 2026, when nuc went from Ubuntu
# Server 24.04 (Tessera installed by hand per the runbook in the tessera
# repo's docs/deployment.md) to NixOS built from this flake. It is kept here
# rather than thrown away because the same problem recurs: every hand-built
# host has a few files that exist nowhere else, and the useful part of this
# script is the list of which ones, not the tar invocation.
#
# Run ON the nuc, as your normal sudo-capable login (NOT as `tessera`).
# Read-only: it copies, it never deletes or modifies.
#
#   chmod +x nuc-tessera-extract.sh && ./nuc-tessera-extract.sh
#
set -euo pipefail

TESSERA_HOME=${TESSERA_HOME:-/home/tessera/tessera}
TESSERA_USER=${TESSERA_USER:-tessera}
STAGE=$(mktemp -d /tmp/nuc-rescue.XXXXXX); chmod 700 "$STAGE"
OUT=${OUT:-$HOME/nuc-creds-$(date +%F).tar.gz.gpg}

# Build the staging tree here, as the calling user, before any grab() call
# creates one of these with `sudo mkdir -p` instead. Ownership is the whole
# point: the host-snapshot redirect further down runs as you rather than as
# root — `sudo` covers the commands inside the block, not the `>` — so a
# root-owned reference/ fails it with "Permission denied".
mkdir -p "$STAGE"/{env,ssh,cloudflared,units,reference}

MISSING=()
grab() { # grab <src> <dest-subdir>
  if sudo test -e "$1"; then
    sudo mkdir -p "$STAGE/$2" && sudo cp -a "$1" "$STAGE/$2/"
    printf '  ok      %s\n' "$1"
  else
    printf '  MISSING %s\n' "$1"; MISSING+=("$1")
  fi
}

echo "==> credentials"
# The one that matters. Entra / Linear / OneDrive *client secrets* are shown
# once at creation — if this file is their only copy, losing it means rotating
# each app registration by hand in three different vendor consoles.
grab "$TESSERA_HOME/.env"                      env
grab "/home/$TESSERA_USER/.ssh/id_ed25519"     ssh
grab "/home/$TESSERA_USER/.ssh/id_ed25519.pub" ssh

echo
echo "==> cloudflare tunnel"
# Keeping <uuid>.json keeps the existing tunnel and its DNS route. Without it
# the tunnel must be recreated with a new UUID and the record re-pointed.
grab /etc/cloudflared/cert.pem   cloudflared
grab /etc/cloudflared/config.yml cloudflared
if sudo test -d /etc/cloudflared; then
  while IFS= read -r j; do grab "$j" cloudflared; done \
    < <(sudo find /etc/cloudflared -maxdepth 1 -name '*.json')
fi

echo
echo "==> reference config (for the NixOS translation)"
grab /etc/caddy/Caddyfile reference
while IFS= read -r u; do grab "$u" units; done \
  < <(sudo find /etc/systemd/system -maxdepth 1 \( -name 'tessera*' -o -name 'langfuse*' \) 2>/dev/null)

{
  echo "# captured $(date -Is) on $(hostname)"
  echo; echo "## os";        . /etc/os-release && echo "$PRETTY_NAME"; uname -a
  echo; echo "## docker";    sudo docker ps -a; sudo docker volume ls
  echo; echo "## units";     systemctl list-units --all 'tessera*' 'langfuse*' 'caddy*' 'cloudflared*' --no-pager
  echo; echo "## listening"; sudo ss -lntp
  echo; echo "## tunnels";   cloudflared tunnel list 2>&1 || echo "(cloudflared not on PATH here)"
} > "$STAGE/reference/host-snapshot.txt" 2>&1
echo "  ok      host-snapshot.txt"

sudo find "$STAGE" -type f -exec sha256sum {} \; | sed "s|$STAGE/||" > "$STAGE/MANIFEST.sha256"
sudo chown -R "$USER" "$STAGE"

echo
echo "==> encrypting to $OUT (pick a strong passphrase)"
# Two things a fresh ~/.gnupg over ssh needs. GPG_TTY tells the agent which
# terminal to prompt on — without it this dies with "problem with the agent:
# Inappropriate ioctl for device". `|| true` because tty(1) exits non-zero
# when stdin is not a terminal, which set -e would otherwise treat as fatal.
export GPG_TTY=${GPG_TTY:-$(tty || true)}
# loopback keeps the prompt inside gpg instead of handing it to a pinentry
# binary, which a headless server may not have installed at all. stdin here is
# the tar stream, so gpg reads the passphrase from /dev/tty either way.
tar czf - -C "$STAGE" . \
  | gpg --pinentry-mode loopback --symmetric --cipher-algo AES256 --output "$OUT"
chmod 600 "$OUT"

echo
echo "=============================================================="
echo "archive: $OUT  ($(du -h "$OUT" | cut -f1))"
[ ${#MISSING[@]} -gt 0 ] && { echo; echo "NOT CAPTURED — check before wiping:"; printf '  - %s\n' "${MISSING[@]}"; }
echo
echo "from the laptop:"
echo "  scp nuc:$OUT ~/"
echo "  gpg -d ~/$(basename "$OUT") | tar tzf -    # verify it opens"
echo
echo "then on the nuc:  rm -rf $STAGE"
echo "=============================================================="
