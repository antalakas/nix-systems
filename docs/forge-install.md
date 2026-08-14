# Installing `forge`

Headless development box: Minisforum MS-02 Ultra, Core Ultra 9 285HX, no GPU.
Reached over SSH (normally across the tailnet) from the laptop.

## Hardware and BIOS

**All four SODIMM slots are populated: 2×32GB Crucial + 2×16GB Hynix, 96GB
total.** The two kits do not match — the 5200 pair against unmatched 4800 1Rx8
modules — so the set trains down to 4800 at best, and four-DIMM DDR5 SODIMM
configurations on Arrow Lake-HX often settle lower than that. Check what it
actually landed on rather than assuming:

```bash
sudo dmidecode -t memory | grep -E "Size|Configured Memory Speed"
```

The trade is deliberate: 96GB carries several kind clusters, Docker and the
Claude sandbox at once, and memory bandwidth is not what limits this box.
Capacity is. If it ever turns out to be flaky rather than merely slow — memtest
errors, build failures that will not reproduce, a board that hesitates to POST —
pull the two 16s and go back to the matched 64GB pair at full clock before
suspecting anything else.

BIOS settings, all of which matter because there is no IPMI on this box:

- **Restore power state after AC loss: *on*.** Without it, a power cut means
  the machine stays down until someone is physically in front of it.
- **Wake on LAN / resume by PCIe device: *on*.** This is what keeps standby
  power on the NIC after a poweroff so it can still see a magic packet. See
  [§11](#11-wake-on-lan-from-the-jumpbox).
- **ERP / EuP: *off*.** It is the deep standby cut, and leaving it enabled
  overrides the setting above — the box will look configured for WoL and still
  ignore the packet.
- **Secure Boot: *off*** (no lanzaboote in this config).

## 1. Boot the installer

Write a current NixOS minimal ISO to a USB stick — the release does not much
matter, since the installed system comes from this flake's nixpkgs (26.11
unstable) rather than from the installer. Boot it and get networking up
(wired DHCP on whichever port you patched — the 2.5GbE or 10GbE RJ45; the SFP28
ports need transceivers and a switch to match).

```bash
sudo -i
passwd nixos           # so you can ssh/scp in from the laptop
```

Every step from here needs root. The commands below carry `sudo` explicitly so
they work in a fresh shell too — if you stayed in the root shell above, the
`sudo` is redundant and harmless. Note the `nixos` user ships with an empty
password and sshd refuses empty-password logins, so `passwd nixos` is what
makes remote access possible at all; `root` keeps its empty password and cannot
be used over SSH regardless.

## 2. Fill in the disk IDs

```bash
nix-shell -p git
git clone https://github.com/antalakas/nix-systems /tmp/nix-systems
cd /tmp/nix-systems

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

`/mnt/var/lib/docker` will show `compress=zstd:3` and no `nodatacow`, despite
what `disko.nix` asks for. That is btrfs rather than a mistake: mount options
apply per filesystem, not per subvolume, so the first mount wins and every
subvolume after it inherits what `/` was mounted with. The NOCOW inode
attribute is what actually works, and `systemd.tmpfiles.rules` in
`hosts/forge/default.nix` sets it on first boot. Setting it here as well costs
nothing and closes the window — the subvolume is empty exactly once, and the
attribute only governs files created after it:

```bash
sudo chattr +C /mnt/var/lib/docker
lsattr -d /mnt/var/lib/docker      # expect ---------------C------
```

## 4. Generate the hardware scan

```bash
sudo nixos-generate-config --no-filesystems --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix /tmp/nix-systems/hosts/forge/
```

`--no-filesystems` is required: `disko.nix` already declares every filesystem,
and a second set of definitions collides with it.

`sudo` is not optional on the first command. It shells out to `btrfs subvolume
show`, which needs root, and turns the failure into a fatal `Failed to retrieve
subvolume info for /` that says nothing about permissions. The `cp` needs no
sudo — it writes into `/tmp/nix-systems`, which you own.

## 5. Install

```bash
sudo cp -rT /tmp/nix-systems /mnt/etc/nixos
sudo nixos-install --flake /mnt/etc/nixos#forge
# set the root password when prompted
sudo nixos-enter --root /mnt -c 'passwd andreas'
reboot
```

`-T` matters. Step 4 already created `/mnt/etc/nixos`, so a plain `cp -r` copies
*into* it and leaves you with `/mnt/etc/nixos/nix-systems/` — after which
`nixos-install` fails, since there is no `flake.nix` at the path it was given.
`-T` treats the destination as the directory to become, not a directory to drop
things in.

The `configuration.nix` that step 4 also wrote is left behind and unused: this
host is built from the flake, which never reads it. Harmless, but do not edit it
expecting an effect.

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

## 11. Wake-on-LAN from the jumpbox

Same arrangement as the NUC: the Raspberry Pi already on this LAN idles at 5W
and is on the tailnet, so it is the thing that stays up. Everything else can be
off. Tailscale carries no layer-2 broadcast, which is exactly why the Pi is
needed — the magic packet has to originate on forge's own segment. (Substitute
your Pi's tailnet name for `jumpbox` below.)

Set the BIOS bits from the top of this doc first; without them the rest of this
section configures a NIC that has no standby power to listen with.

### Pick a port that can do it

```bash
ip -br link                          # name of the port you actually patched
#   eno2   UP   38:05:25:37:b8:40    <- the one with carrier on this machine
sudo ethtool eno2 | grep -i wake
#   Supports Wake-on: pumbg          <- 'g' is magic packet: this port can
#   Wake-on: d                       <- but it is off right now
```

The i226 2.5GbE ports are the ones to rely on. If the port you patched reports
`Supports Wake-on: d`, it cannot do this at all — move the cable to a 2.5GbE
port rather than trying to talk it round.

### Turn it on declaratively

```nix
# hosts/forge/default.nix — eno2 is the port patched on this machine
networking.interfaces.eno2.wakeOnLan.enable = true;
```

This is the one place the flake has to name an interface. It emits a systemd
`.link` file (`40-eno2.link`) carrying `WakeOnLan=magic`, applied by udev as
the device appears — so it takes effect even though this host runs
NetworkManager rather than networkd. Rebuild and check the runtime state rather
than trusting the config:

```bash
sudo ethtool eno2 | grep "Wake-on:"
#   Supports Wake-on: pumbg          <- confirmed on this machine
#   Wake-on: g                       <- armed; 'd' would mean it is not
```

If it still reads `d` once NetworkManager has brought the link up, NM is
resetting it; pin it on the connection profile as well:

```bash
nmcli connection modify "Wired connection 1" 802-3-ethernet.wake-on-lan magic
```

### Record the MAC

```bash
ip link show eno2 | awk '/link\/ether/ {print $2}'
#   38:05:25:37:b8:40        <- eno2, the patched port
```

Wake-on-LAN is addressed at layer 2, so this MAC — not forge's tailnet name,
not its IP — is what the Pi sends to. It is written down here and in
`hosts/forge/default.nix` because the machine cannot tell you its own MAC from
powered down, which is the only time you need it. Give it a DHCP reservation on
the router at the same time: WoL does not need one, but a stable LAN address is
what you will want on the day Tailscale is the thing that broke.

### Wake it

Confirmed working end to end on this machine — powered off, woken from the Pi,
back on the tailnet. From the laptop, in one hop:

```bash
ssh jumpbox wakeonlan 38:05:25:37:b8:40
ssh andreas@forge                          # ~40s later, once tailscaled is up
```

`wakeonlan` broadcasts to 255.255.255.255:9. If the Pi has more than one
interface, aim it at the LAN broadcast address explicitly:

```bash
ssh jumpbox wakeonlan -i 192.168.1.255 38:05:25:37:b8:40
```

`etherwake` works too and is what some Pi images ship instead, but it needs
root and an interface: `sudo etherwake -i eth0 38:05:25:37:b8:40`.

Going the other way, shutdown is remote and safe — the packet can always bring
it back:

```bash
ssh andreas@forge sudo systemctl poweroff
```

### Why poweroff and not suspend

S3 would resume faster, but Arrow Lake-HX generally only offers s2idle. Check:

```bash
cat /sys/power/mem_sleep       # if there is no 'deep', don't build on suspend
```

Without `deep`, suspend keeps far more of the machine powered than S5 does and
its network wake path is much less dependable here — which defeats the point of
turning the box off. Poweroff plus a magic packet is the predictable pair, and
a cold boot to a usable SSH session is under a minute anyway.

### The LAN fallback

The Pi is only a fallback for a broken tailnet if it can reach forge over the
LAN, which needs a key in `users.users.andreas.openssh.authorizedKeys.keys`
rather than the tailnet ACLs Tailscale SSH checks. The laptop's key is in
`hosts/forge/default.nix`; add the Pi's too if you want to hop rather than only
send packets from it.

## Day-to-day

```bash
# wake forge from the laptop, via the Pi that is always on
ssh jumpbox wakeonlan 38:05:25:37:b8:40

# from the laptop, build and deploy forge without logging in
nixos-rebuild switch --flake /etc/nixos#forge --target-host andreas@forge --use-remote-sudo

# on forge
nrs        # switch
nrb        # boot (safer for anything touching networking or the bootloader)
```

For changes that could take the network down, prefer `nrb` plus a reboot you
can watch, or `nixos-rebuild test` — a broken `switch` on a machine with no
IPMI means a trip to wherever it lives.

### Git in /etc/nixos needs sudo

The clone was made as root during the install, so git run as `andreas` refuses
it:

```
fatal: detected dubious ownership in repository at '/etc/nixos'
```

Use `sudo git -C /etc/nixos ...`. Do not take git's suggestion of adding a
`safe.directory` exception: that only silences the check, leaving the files
root-owned, so the next `git pull` fails on write permission instead. Chowning
the tree to `andreas` would work, but it gives every process running as you —
including the Claude Code sandbox and anything in Docker — write access to what
root builds into the system. `sudo` keeps that an explicit step.

Note that powerlevel10k's git status in the prompt reads the repo directly and
does not enforce `safe.directory`, so it will happily show a dirty `/etc/nixos`
that the git CLI then refuses to tell you anything about.

One consequence worth knowing when pulling: the install edits `disko.nix` and
`hardware-configuration.nix` in place, so those files can be locally modified
against a remote that has since gained the same values. Read
`sudo git -C /etc/nixos diff` before discarding anything.

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
