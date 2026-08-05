# Installing `forge`

Headless development box: Minisforum MS-02 Ultra, Core Ultra 9 285HX, no GPU.
Reached over SSH (normally across the tailnet) from the laptop.

## Hardware notes before you assemble

**Populate only the two 32GB Crucial sticks.** The board has four SODIMM slots,
so all four modules fit — but mixing the matched 5200 kit with the unmatched
Hynix 4800 1Rx8 modules trains everything down to 4800 at best, and four-DIMM
DDR5 SODIMM configurations on Arrow Lake-HX frequently train lower or turn
flaky. 64GB dual-channel runs two kind clusters, Docker and the Claude sandbox
without strain. Keep the 16s as spares and only add them if you actually hit a
memory ceiling — at which point expect the clock drop as the price.

**In the BIOS, set "restore power state after AC loss" to *on*.** There is no
IPMI on this box. Without that setting, a power cut means it stays down until
someone is physically in front of it.

Secure Boot must be off (no lanzaboote in this config).

## 1. Boot the installer

Write a current NixOS minimal ISO to a USB stick — the release does not much
matter, since the installed system comes from this flake's nixpkgs (26.11
unstable) rather than from the installer. Boot it and get networking up
(wired DHCP on whichever port you patched — the 2.5GbE or 10GbE RJ45; the SFP28
ports need transceivers and a switch to match).

```bash
sudo -i
passwd nixos           # so you can scp things in if needed
```

## 2. Fill in the disk IDs

```bash
nix-shell -p git
git clone https://github.com/antalakas/nix-systems /tmp/nix-systems
cd /tmp/nix-systems
git checkout headless-forge

lsblk -o NAME,SIZE,MODEL,SERIAL   # which disk is which
ls -l /dev/disk/by-id/            # the stable names for them
$EDITOR hosts/forge/disko.nix     # replace both REPLACE_ME device paths
```

Use `by-id` paths, never `/dev/nvme0n1`. Enumeration order is not stable across
boots, and the next step formats whatever these point at.

Before running it, confirm each symlink lands where you think:

```bash
readlink -f /dev/disk/by-id/nvme-WD_BLACK_SN850X_...   # expect the 4TB device
```

## 3. Partition and mount

This destroys both disks.

```bash
sudo nix --experimental-features "nix-command flakes" \
  run github:nix-community/disko/latest -- \
  --mode destroy,format,mount \
  --flake /tmp/nix-systems#forge
```

Verify before continuing — `/mnt`, `/mnt/home`, `/mnt/nix`, `/mnt/var/lib/docker`,
`/mnt/.snapshots`, `/mnt/srv` and `/mnt/boot` should all be mounted:

```bash
findmnt -R /mnt
```

## 4. Generate the hardware scan

```bash
nixos-generate-config --no-filesystems --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix /tmp/nix-systems/hosts/forge/
```

`--no-filesystems` is required: `disko.nix` already declares every filesystem,
and a second set of definitions collides with it.

## 5. Install

```bash
cp -r /tmp/nix-systems /mnt/etc/nixos
nixos-install --flake /mnt/etc/nixos#forge
# set the root password when prompted
nixos-enter --root /mnt -c 'passwd andreas'
reboot
```

## 6. Join the tailnet

At the console, on first boot:

```bash
sudo tailscale up --ssh
```

From here on you can work from the laptop:

```bash
ssh andreas@forge
```

If `tailscale up` is what you have to reach, you need the console — this is why
step 0 is "keep physical access convenient for the first week".

## 7. Move secrets under sops

Now that the host has an SSH host key, it can decrypt its own secrets.

```bash
# on forge
nix run nixpkgs#ssh-to-age -- -i /etc/ssh/ssh_host_ed25519_key.pub

# on the laptop, if you don't already have a personal age key
age-keygen -o ~/.config/sops/age/keys.txt
```

Put both public keys into `.sops.yaml`, then create the encrypted file:

```bash
sops secrets/forge.yaml
```

```yaml
tailscale_authkey: tskey-auth-...   # from the Tailscale admin console
```

Commit it (it is encrypted), rebuild, and `hosts/forge/secrets.nix` starts
being imported automatically. A reinstall now rejoins the tailnet unattended.

## 8. Claude Code sandbox

The sandbox is already installed by home-manager — `~/.local/bin/claude-sandbox`
and `~/.config/claude-code/Dockerfile`. What it needs that nix does not provide:

```bash
# GitHub PATs, one per resource owner. The script refuses to read this file
# unless it is mode 0600.
install -m 600 /dev/null ~/.config/claude-code/github-tokens
$EDITOR ~/.config/claude-code/github-tokens
#   antalakas=github_pat_...
#   TileDB-Inc=github_pat_...

# Reference mounts — machine-specific, gitignored. Point at forge's paths.
$EDITOR ~/.config/claude-code/refs.conf
#   /home/andreas/workspace/tiledb/repos/TileDB-Server:/ref/TileDB-Server

# Profiles, then log in inside each
mkdir -p ~/.claude-profiles/work/.claude ~/.claude-profiles/personal/.claude
claude-sandbox                      # work profile;  run /login
claude-sandbox --profile personal   # personal;      run /login
```

Two things differ from the laptop:

- The image runs `--network=host`, so the sandbox reaches kind clusters and the
  local registry on `localhost` with no extra plumbing.
- `MEMPALACE_MINE_CPUS` defaults to 6 (see `dotfiles/claude-code/Dockerfile`).
  That cap exists because the miner pegged 15 of the laptop's 22 cores; with 24
  here you can raise it.

## 9. Kubernetes

```bash
kind-up                 # single-node cluster named "dev"
kind-up big 3           # 3 workers
kubectl get nodes

docker tag myapp localhost:5000/myapp
docker push localhost:5000/myapp    # same reference works inside the cluster

kind delete cluster --name dev      # the registry survives
```

The registry is a systemd-managed container: `systemctl status docker-kind-registry`.

To bring up k3s alongside, set `services.k3s.enable = true` in
`modules/k8s-dev.nix` and rebuild.

## 10. Zed remote

Add forge as a remote in Zed on the laptop; it connects over SSH. The nix-built
remote server is already at `~/.zed_server`, which is what makes this work at
all on NixOS.

**Client and server versions must match.** Both come from this flake's nixpkgs,
so after `nix flake update` rebuild *both* hosts. If they drift anyway, set
`"upload_binary_over_ssh": true` in the laptop's Zed settings.

## Day-to-day

```bash
# from the laptop, build and deploy forge without logging in
nixos-rebuild switch --flake /etc/nixos#forge --target-host andreas@forge --use-remote-sudo

# on forge
nrs        # switch
nrb        # boot (safer for anything touching networking or the bootloader)
```

For changes that could take the network down, prefer `nrb` plus a reboot you
can watch, or `nixos-rebuild test` — a broken `switch` on a machine with no
IPMI means a trip to wherever it lives.

## Not set up yet

- **WireGuard.** The laptop's `tiledb-wg` profile is not carried over. If
  company resources turn out to need it, add it as a NetworkManager profile
  with secrets from sops — and keep it split-tunnel. A full-tunnel WireGuard
  brought up over an SSH session that arrived via Tailscale will cut that
  session.
- **Backups.** `/srv` on the 1TB drive is the intended restic target; nothing
  writes to it yet.
- **Ollama.** No GPU here, so the laptop stays the place for local models. Its
  API is already reachable across the tailnet on port 11434.
