# Installing `nuc`

Headless always-on box, the third host in this flake. Reached over SSH, normally
across the tailnet, same as `forge`.

Unlike forge, this machine has a past. It ran Ubuntu Server 24.04 with Tessera
installed by hand from the runbook in that repo's `docs/deployment.md`, plus
Caddy and a cloudflared tunnel — so the install is a one-way trip over a disk
that is not empty, and §0 exists because of it.

This document is the *deltas* from `docs/forge-install.md`, not a replacement
for it. Where the two hosts do the same thing for the same reason, the reasoning
is there and only the command is here. Three things genuinely differ:

- **[§0](#0-before-anything-destructive)** — there is data on the main drive
  that exists nowhere else, and `disko` destroys it.
- **[§2](#2-clone-and-verify--the-disk-ids-are-already-in-the-file)** — the disk
  IDs are already committed, so this is a verification step rather than an
  editing one.
- **[§3](#3-generate-the-hardware-scan--before-disko)** — the hardware scan
  comes *before* `disko`, which reverses forge's §3/§4. That one is not a
  preference; the other order cannot work here.

Everything else — the sops bootstrap, the host-key backup, the two Tailscale
expiry clocks, the `/etc/nixos` ownership and HTTPS-remote notes — is forge's
verbatim and is not repeated.

## Hardware and BIOS

An Intel NUC — Core i7-10710U, Comet Lake-U, six cores — with two 512G Samsung
drives: a 970 PRO (NVMe) carrying the system and an 850 PRO (SATA) at `/srv`.

`hosts/nuc/default.nix` does not copy any of forge's hardware tuning — no kernel
pin, no DDP firmware, no Wake-on-LAN — on purpose, and this CPU is why the first
of those is right to omit. forge runs `linuxPackages_latest` only because Arrow
Lake-HX is newer than the default kernel knows about; Comet Lake is four years
older than anything in this flake's nixpkgs. Add tuning back only when the
machine turns out to need it.

It also confirms the one guess in that file that was made off-host:
`hardware.cpu.intel.updateMicrocode` is correct, since some NUC models are AMD.
[§2](#2-clone-and-verify--the-disk-ids-are-already-in-the-file) checks it anyway,
because the next machine may not be this one.

BIOS, for a box with no IPMI that is meant to stay up:

- **After power failure: *Power On*.** This is the setting that matters most
  here. forge is powered off between sessions and woken deliberately; this host
  is not, so a power cut with the wrong value means it stays down until someone
  is standing in front of it.
- **Wake on LAN / resume by PCIe device: *on*, ERP/EuP: *off*.** Not needed yet
  — nothing in the flake arms WoL on this host — but they are BIOS settings, and
  the moment you want them is the moment you cannot get to the BIOS. See
  [§9](#9-aftercare).
- **Secure Boot: *off*** (no lanzaboote in this config).

## 0. Before anything destructive

The 970 PRO holds the hand-built Tessera deployment. Most of it is reproducible
and the rest is disposable — the database, the Borg repo and `outputs/` are all
deliberately *not* rescued, because users re-onboard after the redeploy. What
cannot be regenerated is a short list, and `scripts/nuc-tessera-extract.sh`
knows it: the Tessera `.env` (the Entra, Linear and OneDrive *client secrets* in
it are shown once at creation, so losing them means rotating three app
registrations by hand in three vendor consoles), the cloudflared tunnel
credentials, the deploy key, and the systemd units and Caddyfile kept as a
reference for translating the deployment into this flake.

That script has already been run on this host. Before going further, confirm the
archive is on the **laptop** rather than in a home directory on the drive you
are about to format — and confirm it *opens*. `ls` proves a file exists; it does
not prove you still know the passphrase, and the day you find that out is the
day after the wipe.

```bash
ls -l ~/nuc-creds-*.tar.gz.gpg
export GPG_TTY=$(tty)
nix shell nixpkgs#gnupg -c \
  gpg --pinentry-mode loopback -d ~/nuc-creds-*.tar.gz.gpg | tar tzf -
```

Both gpg options are load-bearing, and are the decrypt-side twins of the ones
the script uses to *write* the archive. `--pinentry-mode loopback` keeps the
prompt inside gpg rather than handing it to a pinentry binary, which an ad-hoc
`nix shell nixpkgs#gnupg` does not bring with it — without it this fails with
"problem with the agent: No pinentry" and, confusingly, "decryption failed: Bad
session key", as though the passphrase were wrong. `GPG_TTY` tells gpg which
terminal to prompt on, which it cannot infer here because stdout is a pipe.

Read the listing rather than just its exit status. `env/.env` is the entry that
matters; the script prints `MISSING` for anything it could not find and still
produces an archive, so a clean extract does not by itself mean the client
secrets are in there. For the full check — this is what the manifest is for:

```bash
mkdir -p /tmp/creds-check
nix shell nixpkgs#gnupg -c \
  gpg --pinentry-mode loopback -d ~/nuc-creds-*.tar.gz.gpg | tar xzf - -C /tmp/creds-check
( cd /tmp/creds-check && sha256sum -c MANIFEST.sha256 )
rm -rf /tmp/creds-check      # plaintext secrets on disk until this runs
```

If the archive is missing, or it does not open, stop here. Nothing is destroyed
until [§4](#4-partition-and-mount), so the old root is still readable from the
installer — Ubuntu kept it in LVM, so recovering it is `vgchange -ay` and a
read-only mount, not a plain `mount /dev/sda1`.

Note what the `nix shell` above implies: gpg is in no host's closure in this
flake, so the one tool that opens the archive has to be fetched at the moment
you need it. That is fine today and less fine during an actual emergency, which
is the argument `.sops.yaml` makes for installing `ssh-to-age` rather than
`nix run`-ing it. Add `gnupg` to `home/common.nix` if this archive is ever
promoted from one-off to fallback.

The second drive needs no rescue. Under Ubuntu it was one full-disk ext4 mounted
at `/home/andreas/ssd` and empty — 444.5G of 476.9G free, which is a fresh
filesystem once ext4's reserved blocks and journal are accounted for. Checked
before the wipe.

## 1. Boot the installer

Write a current NixOS minimal ISO to a USB stick — the release does not much
matter, since the installed system comes from this flake's nixpkgs rather than
from the installer. Boot it, and get wired DHCP up.

```bash
sudo -i
passwd nixos           # so you can ssh/scp in from the laptop
ip -br a               # confirm the port you patched has an address
```

The `nixos` user ships with an empty password and sshd refuses empty-password
logins, so `passwd nixos` is what makes remote access possible at all. `root`
keeps its empty password and cannot be used over SSH regardless.

Staying in that root shell is the simplest thing to do, and it sidesteps a trap
in [§3](#3-generate-the-hardware-scan--before-disko): `sudo` covers the command
it prefixes, never the `>` redirect after it.

## 2. Clone and verify — the disk IDs are already in the file

forge's §2 has you fill in two `REPLACE_ME` device paths. `hosts/nuc/disko.nix`
already carries both: they were read off this machine while it still ran Ubuntu.
So this is a verification step, and it is worth doing properly, because the next
one formats whatever these resolve to.

```bash
nix-shell -p git
git clone https://github.com/antalakas/nix-systems /tmp/nix-systems
cd /tmp/nix-systems

lsblk -o NAME,SIZE,MODEL,SERIAL
readlink -f /dev/disk/by-id/nvme-Samsung_SSD_970_PRO_512GB_S463NF0M915208E
readlink -f /dev/disk/by-id/ata-Samsung_SSD_850_PRO_512GB_S250NXAGB30165T
```

Both must resolve, and to the devices you expect — on this machine `/dev/nvme0n1`
and `/dev/sda`, both reported by `lsblk` as 476.9G Samsung. If either fails,
re-read `ls -l /dev/disk/by-id/` and fix `disko.nix` before continuing. The
kernel also exposes the NVMe as `nvme-eui.0025385991b3924d` and as a duplicate
`..._1` alias; the model+serial form in the file is the stable, readable one.

`lsblk` is also the last chance to recognise the old layout before it goes: the
NVMe should show a 1G ESP, a 2G `/boot` and a 473.9G LVM PV carrying a 100G
`ubuntu--vg-ubuntu--lv`, and `sda` a single full-disk partition. A third,
smaller device is the installer USB — do not confuse it with anything.

Settle the microcode guess while you are here:

```bash
lscpu | grep -iE "vendor|model name"
```

If this is an AMD model, swap `hardware.cpu.intel.updateMicrocode` in
`hosts/nuc/default.nix` for `hardware.cpu.amd.updateMicrocode`.

Note the clone is over **HTTPS**, and not only because the installer has no key.
This tree becomes `/etc/nixos` in [§5](#5-install), where git runs as root and
root never consults `~andreas/.ssh` — forge's "…and an HTTPS remote, for the
same reason" covers it at length.

## 3. Generate the hardware scan — before `disko`

**This is the step order that differs.** forge partitions in §3 and scans in §4.
That cannot work for a host whose scan is still the placeholder:
`disko --mode ... --flake .#nuc` has to evaluate `nixosConfigurations.nuc` to
reach `disko.devices`; evaluating it imports `hosts/nuc/hardware-configuration.nix`;
and importing that file `throw`s, because it is a placeholder whose whole job is
to fail legibly rather than let a rebuild die later with a missing
`fileSystems."/"`.

Writing the scan first breaks the cycle, and `--show-hardware-config` needs
nothing mounted to run.

```bash
sudo nixos-generate-config --no-filesystems --show-hardware-config \
  > /tmp/nix-systems/hosts/nuc/hardware-configuration.nix
```

`--no-filesystems` is required: `disko.nix` already declares every filesystem,
and a second set of definitions collides with it.

Only `nixos-generate-config` runs under `sudo`; the redirect runs as whoever you
are. From the root shell in [§1](#1-boot-the-installer) that is moot, but as the
`nixos` user it means the file has to land somewhere you own — `/tmp/nix-systems`
is, if you cloned it yourself.

Read the output before trusting it:

```bash
grep -nE "availableKernelModules|fileSystems|swapDevices|hostPlatform" \
  hosts/nuc/hardware-configuration.nix
```

- `nvme` in `boot.initrd.availableKernelModules`. This is the one that decides
  whether the machine boots; `ahci` and `sd_mod` alongside it are the SATA
  drive. `usb_storage` and `usbhid` will be in there too, because the scan was
  taken from a running USB installer — harmless, it is an "available" list
  rather than a required one.
- **No `fileSystems` and no `swapDevices` lines at all.** `--no-filesystems`
  suppresses the entire storage section rather than emitting empty lists, so
  absent is the expected answer for both and there is nothing to compare against
  `zramSwap`. If either *does* appear, the flag was missed and the definitions
  will collide with `disko.nix`.
- `nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";`

Then check the throw is gone. This is cheap and it fails now rather than four
minutes into `disko`:

```bash
nix --experimental-features "nix-command flakes" \
  eval /tmp/nix-systems#nixosConfigurations.nuc.config.networking.hostName
#   warning: Git tree '/tmp/nix-systems' is dirty
#   "nuc"
```

The warning is the mechanism working rather than something to fix, and the next
paragraph is why.

You are overwriting a *tracked* file, which is why the dirty working tree is
enough. A flake evaluates against a copy of the tree containing only tracked
files, so modifications to one are picked up and a brand-new file would be
invisible. That asymmetry bites for real in [§7](#7-move-secrets-under-sops),
where the new file is `secrets/nuc.yaml`.

## 4. Partition and mount

This destroys both disks.

```bash
sudo nix --experimental-features "nix-command flakes" \
  run github:nix-community/disko/latest -- \
  --mode destroy,format,mount \
  --flake /tmp/nix-systems#nuc

findmnt -R /mnt
```

`/mnt`, `/mnt/home`, `/mnt/nix`, `/mnt/var/lib/docker`, `/mnt/.snapshots`,
`/mnt/srv` and `/mnt/boot` should all be mounted. Ubuntu's 1G ESP, 2G `/boot`
and LVM PV are gone; the layout in `disko.nix` replaced them wholesale.

`/mnt/var/lib/docker` will show `compress=zstd:3` and no `nodatacow`, despite
what `disko.nix` asks for. That is btrfs, not a mistake — mount options apply
per filesystem, not per subvolume, so the first mount wins. What actually
disables COW is the NOCOW inode attribute, which
`systemd.tmpfiles.rules` in `hosts/nuc/default.nix` sets on first boot. Setting
it here as well costs nothing and closes the window, because the subvolume is
empty exactly once and the attribute only governs files created after it:

```bash
sudo chattr +C /mnt/var/lib/docker
lsattr -d /mnt/var/lib/docker      # expect ---------------C------
```

Optional, and cheap: now that the target is mounted, re-run the scan against it
and confirm nothing moved.

```bash
sudo nixos-generate-config --root /mnt --no-filesystems --show-hardware-config \
  | diff - hosts/nuc/hardware-configuration.nix
```

## 5. Install

```bash
sudo mkdir -p /mnt/etc
sudo cp -rT /tmp/nix-systems /mnt/etc/nixos
ls /mnt/etc/nixos                       # flake.nix at the top level
sudo nixos-install --flake /mnt/etc/nixos#nuc     # set the root password when prompted
sudo nixos-enter --root /mnt -c 'passwd andreas'
```

The `mkdir` is not in forge's §5, and its absence here is the last consequence
of the reordering in [§3](#3-generate-the-hardware-scan--before-disko). forge
runs `nixos-generate-config --root /mnt`, which creates `/mnt/etc/nixos` as a
side effect, so its `cp` lands in an existing tree. This sequence never writes
under `/mnt` before now, and `cp -T` creates the *destination* but not the
destination's parent — so without it the copy dies with `cannot create directory
'/mnt/etc/nixos': No such file or directory`.

Keep `-T` regardless. It treats the destination as the directory to *become*
rather than a directory to drop things in — the difference between
`/mnt/etc/nixos/flake.nix` and `/mnt/etc/nixos/nix-systems/flake.nix`, and
`nixos-install` fails on the second.

The other half of that trade is a step forge needs and this host does not: with
no `nixos-generate-config --root /mnt` in the sequence, nothing wrote a stray
`configuration.nix` or top-level `hardware-configuration.nix` into
`/mnt/etc/nixos`, so there is nothing to delete afterwards. Confirm with the
`ls` rather than assuming — an untracked file in `/etc/nixos` makes the tree
read dirty from the first boot onwards, and a repo that is always dirty is one
whose *real* local edits you stop noticing.

There is also no host key to restore. forge's §7 covers putting one back before
`nixos-install` on a *re*install; this machine has never run NixOS, so it gets a
fresh one — which is what [§7](#7-move-secrets-under-sops) then encrypts to, and
what [§9](#9-aftercare) tells you to back up.

Pull the USB stick, then `reboot`.

## 6. First boot

Log in at the console as `andreas` — `modules/server.nix` sets
`PermitRootLogin = "no"`, so root is console-only from here on — and find the
LAN address:

```bash
ip -br a
```

That is all the console is for. `services.openssh` is up on first boot with the
laptop's key already in `users.users.andreas.openssh.authorizedKeys.keys`
(`hosts/nuc/default.nix`), and port 22 is open on every interface, so the LAN
way in works *before* the tailnet exists rather than only after it breaks. That
is the point of the two-paths arrangement `modules/server.nix` describes, and it
is easy to forget that one of the two is available this early.

```bash
# laptop
ssh andreas@192.168.1.x
sudo tailscale up --ssh
```

### The host key changed, and this time it should have

The first connection will almost certainly fail with `REMOTE HOST IDENTIFICATION
HAS CHANGED!`, naming an offending line in `~/.ssh/known_hosts`. That is
correct: the laptop still holds the *Ubuntu* host key for this address, and the
install generated a new one. Do not reach past it — verify, because this is the
one moment the connection is unauthenticated, and because the key being
confirmed is exactly the one [§7](#7-move-secrets-under-sops) derives this
host's age key from. Getting it wrong is not a `known_hosts` annoyance; it is
the root of trust for every secret this machine will ever decrypt.

```bash
# nuc, at the console — the authoritative copy
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Compare that fingerprint against the one ssh printed. If they match:

```bash
# laptop
ssh-keygen -R 192.168.1.x      # drops every key type for that address, keeps a .old backup
ssh andreas@192.168.1.x        # accept the fingerprint you just verified
```

Connecting later by *tailnet* name hits this a second time, and harder — the
Ubuntu box answered to that name too, so it is a hard failure rather than a
prompt. That is covered below, once there is a tailnet to connect over.

### Delete the old tailnet device before enrolling

This host has been on the tailnet before, under Ubuntu, and that device is still
registered — offline, and still holding the name. Tailscale will not hand the
same MagicDNS name to two machines, so enrolling on top of it yields `nuc-1` and
leaves `nuc` pointing at something that no longer exists. Nothing fails at the
time. You find out later, when `ssh andreas@nuc` hangs against a dead address,
and every instruction from [§7](#7-move-secrets-under-sops) onwards assumes the
plain name.

Check from the laptop, then remove it in the admin console — Machines → the
offline `nuc` → Remove:

```bash
# laptop
tailscale status | grep -i nuc      # an offline `nuc` here is the Ubuntu one
getent hosts nuc                    # still resolves, to the OLD tailnet address
```

There is no CLI for deleting a device, so the console is unavoidable. Then, once
`tailscale up` has run, confirm the name it actually got — which is the whole
point of having removed the old one first:

```bash
# nuc
tailscale status | head -3          # must say `nuc`, not `nuc-1`
```

This is not only a migration problem. Every reinstall enrols as a *new* device
and leaves the previous entry behind, so the same collision waits on the next
one — which puts it on the same redo list as disabling key expiry in
[§9](#9-aftercare).

Doing it over SSH rather than at the console matters for a practical reason: on
a headless box there is no browser for the login URL `tailscale up` prints, and
run this way the URL arrives in a terminal you can copy from. Typing it out from
the console screen also works — it is `https://login.tailscale.com/a/` plus
about a dozen hex characters — but there is no reason to. Using `--auth-key`
would skip the URL entirely and is the wrong trade here: a `tskey-auth-...`
string is several times longer to key in by hand.

No auth key is involved either way at this stage: `secrets/nuc.yaml` does not
exist, so `hosts/nuc/default.nix` has not imported `secrets.nix` and nothing in
the config references a secret. This one manual `tailscale up` is what the
bootstrap ordering costs, and [§7](#7-move-secrets-under-sops) is what stops it
recurring on the next install.

### Reaching it by name afterwards

Two things get between you and `ssh andreas@nuc` from the laptop, and neither is
a prompt you can click past.

The first is `known_hosts`, again. It is keyed on the name rather than the
machine, and the Ubuntu box answered to this same tailnet name — so the first
connection does not ask, it fails outright with `REMOTE HOST IDENTIFICATION HAS
CHANGED!` and an offending line number. Same cause as the LAN address earlier,
same fix, and the fingerprint it reports should be the one you verified at the
console:

```bash
# laptop
ssh-keygen -R nuc.taile6c0b.ts.net
ssh-keygen -R 100.91.219.77        # the old node's tailnet address, while you are here
ssh andreas@nuc.taile6c0b.ts.net   # accept the fingerprint you verified
```

The second is that the *short* name may never reach the tailnet at all. The
router answers `nuc` out of its own DHCP records before MagicDNS is consulted,
and those records outlive the machine that created them — here it returned a
stale LAN address, and ssh died with `No route to host` against nothing at all.
Ask which resolver answered:

```bash
resolvectl query nuc
```

An alias settles both, and sidesteps the router's view entirely:

```
# ~/.ssh/config on the laptop
Host nuc
  HostName nuc.taile6c0b.ts.net
  User andreas
```

The DHCP reservation in [§9](#9-aftercare) is still worth having, but it repairs
the LAN path rather than this one.

While you are there:

```bash
systemctl --failed
findmnt -R /
nixos-version
```

That last one is worth a moment. `system.stateVersion` in
`hosts/nuc/default.nix` and `home.stateVersion` in `hosts/nuc/home.nix` both say
`26.11`, copied from forge. They pin compatibility defaults for stateful
services, so they are set once at install and left alone — moving one later
silently changes those defaults under existing data. If `nixos-version` reports
something else, decide now, before the first `nrs` and before anything stateful
accumulates. Older-than-actual is conservative rather than broken; the point is
to have looked.

From here on, work from the laptop:

```bash
ssh andreas@nuc
```

## 7. Move secrets under sops

Now that the host has an SSH host key it can decrypt its own secrets. This is
forge's §7 with the names changed, so only the specifics are here.

```bash
# on nuc
ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
```

Add that to `.sops.yaml` as `&nuc`, alongside `&forge` and `&andreas`, and give
`secrets/nuc\.yaml$` a `creation_rules` entry encrypted to `*nuc` and
`*andreas`. Both keys, always: the host key dies with the host, and the personal
key on the laptop is the only recovery path.

Create the file **from your laptop clone**, not `/etc/nixos`. That one is
root-owned so you cannot write it, and reaching for `sudo` makes it worse —
`sudo` resets `HOME` to `/root`, where there is no
`~/.config/sops/age/keys.txt`, so sops reports it cannot decrypt with any key.

```bash
cd ~/dev/nix-systems
sops secrets/nuc.yaml
```

```yaml
tailscale_authkey: tskey-auth-...   # reusable, from the Tailscale admin console
```

Then the step nothing complains about when you skip it:

```bash
git add secrets/nuc.yaml
```

`hosts/nuc/default.nix` imports `secrets.nix` behind
`builtins.pathExists ../../secrets/nuc.yaml`, and — as in
[§3](#3-generate-the-hardware-scan--before-disko) — a flake sees only tracked
files. An untracked `secrets/nuc.yaml` is invisible to that check, so the import
stays off and the rebuild succeeds having changed nothing at all. Commit it; it
is encrypted, which is the point of committing it.

`hosts/nuc/secrets.nix` names exactly one secret. Do not add `restic_password`
to match forge: there is a `/srv` here to back up to, but no restic units, and
sops-install-secrets fails activation for a secret the file does not contain —
so naming one for a service that does not exist buys a broken activation on a
headless box. Add it alongside a `backup.nix` if that changes.

### Land the hardware scan at the same time

The install left one in-place edit in `/etc/nixos`:
`hosts/nuc/hardware-configuration.nix`, still the working-tree modification from
[§3](#3-generate-the-hardware-scan--before-disko). Get it into git from the
laptop rather than committing on the box, so `/etc/nixos` stays a deploy target
that only ever reads:

```bash
# laptop
scp andreas@nuc:/etc/nixos/hosts/nuc/hardware-configuration.nix hosts/nuc/
git add hosts/nuc/hardware-configuration.nix secrets/nuc.yaml .sops.yaml
git commit && git push
```

```bash
# nuc — discard the local copy in favour of the one you just pushed
sudo git -C /etc/nixos checkout hosts/nuc/hardware-configuration.nix
sudo git -C /etc/nixos pull
sudo git -C /etc/nixos status      # clean
nrt && nrs
```

`sudo git` is not optional in `/etc/nixos` — the clone was made as root, so git
run as `andreas` refuses it with "dubious ownership". forge's Day-to-day section
explains why the `safe.directory` exception git suggests is the wrong fix.

Check the secret landed rather than trusting the build:

```bash
sudo ls -l /run/secrets/tailscale_authkey   # root:root, 0400
systemctl status tailscaled-autoconnect
```

With that in place a reinstall rejoins the tailnet unattended. Without it,
someone has to run `tailscale up` at the console — which on a headless box means
finding a keyboard and a monitor.

## 8. Verify the btrfs and docker arrangement

Worth ten seconds once, because two of these settings are inert-looking and one
of them genuinely is.

```bash
findmnt -t btrfs -o TARGET,SOURCE,OPTIONS
docker info | grep -i "storage driver"     # overlay2, not btrfs
nix shell nixpkgs#e2fsprogs -c lsattr -d /var/lib/docker   # ---------------C------
sudo btrfs subvolume list /
```

`lsattr` has to be fetched because `e2fsprogs` is in no host's closure in this
flake — nothing here is ext4, so nothing pulls it in. It is on `PATH` in
[§4](#4-partition-and-mount) only because the installer ISO carries it, which is
why that section can call it bare and this one cannot. Same shape as the
`nix shell nixpkgs#gnupg` in [§0](#0-before-anything-destructive), and the same
argument applies: add `e2fsprogs` to `home/common.nix` if you ever want `chattr`
on a running host rather than once during an install.

That reports `Permission denied While reading flags on /var/lib/docker`, because
the directory is mode 0710 and you are `andreas`. It needs root, and getting
root and a fetched binary into the same command takes some care:

```bash
nix shell nixpkgs#e2fsprogs -c sh -c \
  'sudo "$(command -v lsattr)" -d /var/lib/docker'
```

Resolving `lsattr` inside the shell and handing `sudo` the absolute result is
what makes this reliable. Two things it sidesteps: plain `sudo lsattr` depends
on how sudo treats `PATH`, and the binary is not in the system profile anyway;
and `sudo $(nix build --print-out-paths nixpkgs#e2fsprogs)/bin/lsattr` — the
obvious move — is broken, because `e2fsprogs` is a multi-output derivation. That
prints five store paths, word splitting turns them into five arguments, and sudo
tries to execute the first one, a directory, reporting `command not found`.

`overlay2` is named explicitly in `hosts/nuc/default.nix` because docker would
otherwise pick its btrfs driver on a btrfs filesystem, which is the
less-travelled path. The `+C` comes from the tmpfiles rule, which runs well
before `docker.service`, and only governs files created after it.

That last clause is why the `chattr +C` in [§4](#4-partition-and-mount) is not
redundant with the tmpfiles rule, and why this check does not keep until later:
`modules/k8s-dev.nix` declares `kind-registry` under
`virtualisation.oci-containers`, so docker pulls `registry:2` unprompted on the
first boot. The subvolume already has data by the time you read this. If `+C` is
clear here, repairing it means moving that data rather than setting an
attribute.

## 9. Aftercare

The things nothing reminds you about. All of these are forge's, and all of them
are per-host.

- **Disable the node key expiry.** Tailscale admin console → Machines → nuc →
  Disable key expiry. Two clocks are easily conflated: the auth key's 90 days
  only governs whether it can still enrol a machine, while the *node* key
  expires on the tailnet default of 180 days and drops the box off the tailnet
  when it does. There is no CLI equivalent, and a reinstall re-enrols as a new
  device with a fresh clock, so this belongs on the redo list. Do not reach for
  tags instead — `modules/server.nix` runs Tailscale SSH against tailnet ACLs,
  and tagging can quietly remove your own access.
- **Back up the SSH host key**, off the machine, following forge's §7. Without
  it a reinstall generates a new host key, the derived age key no longer matches
  `.sops.yaml`, and the box cannot decrypt its own secrets — one console visit
  plus a `sops updatekeys secrets/nuc.yaml` to recover.
- **Give it a DHCP reservation** on the router. Not needed for anything here; it
  is what you will want on the day Tailscale is the thing that broke, together
  with the laptop key already in
  `users.users.andreas.openssh.authorizedKeys.keys`.
- **Wake-on-LAN**, if this box ever stops being always-on. `hosts/nuc/default.nix`
  deliberately has none: it is the one setting that must name an interface and a
  MAC, and neither is knowable off the machine. Now it can tell you —
  `ip -br link`, then `sudo ethtool <if> | grep -i wake` to check the port
  supports `g` at all. forge's §11 has the full procedure, including the
  NetworkManager override and the Pi on this same LAN that sends the packet.

## Not set up yet

- **Tessera.** The reason this host exists, and still to be translated into this
  flake from what [§0](#0-before-anything-destructive) rescued: three units
  (`tessera-api`, `tessera-web`, `tessera-mcp`), a `tessera-api.service.d/override.conf`
  drop-in, and the Caddyfile. Read the drop-in — it is the easiest file in that
  archive to overlook, and drop-ins are where hand-edits to env paths, restart
  policy and resource limits accumulate. The `.env` is the obvious next sops
  secret, per the note in `hosts/nuc/secrets.nix`. The cloudflared credentials
  keep the existing tunnel UUID and its DNS route; without them the tunnel must
  be recreated and the record re-pointed.

  Langfuse was captured by the same glob and produced no units, so it ran as
  something other than systemd — `reference/host-snapshot.txt` carries the
  `docker ps -a` and `docker volume ls` that say what.
- **Backups.** `disko.nix` puts the 850 PRO at `/srv`, which is where a restic
  repository would go, but there is no `hosts/nuc/backup.nix` counterpart to
  forge's. `hosts/forge/backup.nix` is the template — note its ordering trap:
  the password goes into sops *before* the rebuild that declares it.
- **Wake-on-LAN**, as above.
