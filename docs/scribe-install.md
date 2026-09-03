# Installing `scribe`

Dell XPS 9310, the fourth host in this flake and the portable one. A graphical
client rather than a builder: it runs the niri session and a browser, and the
work happens over the tailnet on forge.

This document is the *deltas* from `docs/forge-install.md` and
`docs/nuc-install.md`, not a replacement for either. Where this host does the
same thing for the same reason, the reasoning is there and only the command is
here. The sops bootstrap, the host-key backup, the two Tailscale expiry clocks
and the `/etc/nixos` ownership question are all forge's and nuc's verbatim.

Five things genuinely differ, and four of them are consequences of this being a
laptop rather than a box in a cupboard:

- **[Hardware and BIOS](#hardware-and-bios)** — no USB-A port and no Ethernet
  port. Both bite before the installer even boots, and the BIOS has a setting
  that hides the disk entirely.
- **[§1](#1-boot-the-installer-and-get-on-the-network)** — there is no wired DHCP to
  bring up, and only two USB-C ports to share between the installer stick, a
  network adapter and the charger. forge's and nuc's §1 both start by patching
  a cable in; this one starts with a trade-off.
- **[§2](#2-clone-and-fill-in-the-disk-id)** — the disk ID. It was `REPLACE_ME`
  when this was written; it is now the device read off this laptop during the
  install, so reinstalling *this* machine checks it rather than fills it in.
  Any other machine still has to edit it, and §4 formats whatever it says.
- **[§4](#4-partition-and-mount)** — LUKS. `disko` prompts for a passphrase,
  twice, and getting the second one wrong wastes the format.
- **[§8](#8-verify-the-desktop)** — there is a desktop to verify, which neither
  headless host has.

The step *order* is nuc's, not forge's: the hardware scan comes before `disko`
in [§3](#3-generate-the-hardware-scan--before-disko), for the same reason and
with the same consequences downstream. That one is not a preference; the other
order cannot work here either.

## Status: installed, and every step below has been run

`scribe` was installed from this document on the night of 3–4 September 2026
and is running. Read the rest as a record of a procedure that worked rather
than as a plan, which is what it was when it was written: at that point nothing
in `hosts/scribe/` had been evaluated, built or booted, and the only thing
verified was that the Nix and KDL files parsed as balanced text.

What the install settled:

- **The configuration evaluates, builds and boots.** The `nix eval` at the end
  of [§3](#3-generate-the-hardware-scan--before-disko) was the first time any
  of it had been evaluated at all, and it passed unchanged, as did
  `nixos-install`. No option name in `hosts/scribe/`, `modules/desktop.nix` or
  `home/niri-desktop.nix` needed correcting.
- **All three values guessed off-machine turned out right**, so
  [§8](#8-verify-the-desktop) records what they came back as rather than what
  to do if they were wrong. The panel is the FHD+ one and wants the committed
  `scale 1.25`; PipeWire came up with a speaker sink and a microphone source on
  the first boot; and `dell_laptop` does expose charge thresholds through
  `natacpi`, so the 75/80 pair is live rather than inert.
- **The keyboard works at the LUKS prompt** — the one failure here that costs a
  reinstall. It is worth knowing *why* it works, because the scan does not say
  so; see [§3](#3-generate-the-hardware-scan--before-disko).

None of that is a reason to skip the checks. They are cheap, they run before
anything destructive, and the flake has moved on since. In particular do not
treat a clean `disko` run as evidence that the system config is sound —
`disko` evaluates only `disko.devices`, so a broken option elsewhere in
`hosts/scribe/` will not surface until `nixos-install` in [§5](#5-install), an
hour later and with the disk already destroyed. §3 has the one-line check that
closes that gap.

## What this adds to the flake

New files:

| Path | What it is |
|---|---|
| `hosts/scribe/default.nix` | the host: hardware, power, sshd, docker |
| `hosts/scribe/disko.nix` | LUKS + btrfs on the single NVMe, and the device ID read off the machine |
| `hosts/scribe/secrets.nix` | sops wiring, imported only once `secrets/scribe.yaml` exists |
| `hosts/scribe/home.nix` | home-manager: tint, alacritty, Zed, the niri profile |
| `hosts/scribe/hardware-configuration.nix` | placeholder that `throw`s until [§3](#3-generate-the-hardware-scan--before-disko) replaces it |
| `modules/desktop.nix` | the niri session, portals, fonts, PipeWire, swaylock PAM. The mirror of `modules/server.nix` |
| `home/niri-desktop.nix` | fuzzel, waybar, mako, btop, GTK theme, wallpaper, fonts |
| `dotfiles/niri/config-mobile.kdl` | single-panel niri profile |
| `docs/scribe-install.md` | this file |

Changed files:

| Path | Change |
|---|---|
| `flake.nix` | adds `nixosConfigurations.scribe` |
| `modules/common.nix` | `virtualisation.docker.enableOnBoot` is now `mkDefault`, so this host can override it without `mkForce` |
| `home/ssh-tint.nix` | new `clientReset` option — see [Design notes](#design-notes) |
| `dotfiles/niri/config-home.kdl`, `config-office.kdl` | the `scribe: ` focus-ring rule, on the main laptop's profiles |
| `dotfiles/niri/PROFILES.md` | documents the `mobile` profile and why profiles must be whole files |

Rebuilding the main laptop (`nrs` there) is what makes the last two take
effect. Nothing else in this list touches forge or nuc.

## Hardware and BIOS

A Dell XPS 13 9310 — Tiger Lake, a 4-core 15W part, 13.4" panel, single M.2
2280 NVMe slot, Killer AX1650 Wi-Fi (an Intel AX201 under the badge). Nothing
of forge's hardware tuning is copied across and nothing needs to be: Tiger Lake
shipped in 2020 and the default kernel knows it well.

Three physical facts to settle before you start, because each one stops the
install dead:

- **There is no USB-A port.** Two Thunderbolt 4 (USB-C) ports, a microSD
  reader, a headphone jack. If the installer is on an ordinary USB-A stick you
  need the USB-C adapter that came in the box, or a USB-C stick. Worth checking
  now rather than at a boot menu.

  Two ports total is also the whole budget for the install: the stick takes
  one, the machine charges over the other, and any wired network adapter wants
  the same one the charger does. [§1](#ports-and-power) works through it.
- **There is no Ethernet port.** Wi-Fi is the only built-in network interface,
  which is why [§1](#1-boot-the-installer-and-get-on-the-network) looks nothing like
  the other two. Both of the easy ways out are wired-shaped: a USB-C Ethernet
  dongle, or USB tethering from a phone, either of which makes that whole
  section collapse into "plug it in".
- **`hardware.enableRedistributableFirmware` is load-bearing here**, not merely
  advisable. It supplies the iwlwifi blob for the only network interface, and
  the SOF firmware Tiger Lake's audio DSP needs. `hosts/scribe/default.nix`
  sets it; the note there spells out why the failure mode is worse than usual.

BIOS (F2 at the Dell logo; F12 for the one-time boot menu):

- **`SATA Operation`: RAID/Intel RST → *AHCI*.** This is the one that matters.
  Under RAID the Linux NVMe driver cannot see the drive at all, so the
  installer boots to a shell with no disk in `lsblk` and nothing obviously
  wrong. Change it *before* [§2](#2-clone-and-fill-in-the-disk-id), where you
  need `/dev/disk/by-id` to have something in it.

  If there is still a Windows install you care about, note that flipping this
  breaks its boot until it is repaired. Since this host is a full wipe, that is
  moot — but it is the reason the switch is usually described as dangerous.
- **Secure Boot: *off***. No lanzaboote in this config.
- **Wake-on-LAN / power-on settings: leave them.** Neither applies to a machine
  with no Ethernet that is carried around and closed.

## 1. Boot the installer and get on the network

Write a current NixOS **minimal** ISO to a USB stick — the release does not
much matter, since the installed system comes from this flake's nixpkgs rather
than from the installer. `docs/usb-iso-writing.md` covers the writing.

```bash
sudo -i
passwd nixos           # so you can ssh/scp in from the laptop later
ip -br a               # what interfaces exist, and what has an address
```

**The card itself will work.** The installation ISO enables all firmware —
`profiles/all-hardware.nix`, which the installer media import — so the iwlwifi
blob for the AX201 is present here even though no host config has been applied
yet. The `hardware.enableRedistributableFirmware` in `hosts/scribe/default.nix`
is for the *installed* system, not for this step. If `ip -br a` shows no
wireless interface at all, that is a real problem; it should not happen.

There are several ways to get an address. Which is best is not simply "the
fastest link", because of a port-count problem this machine has and the other
two hosts do not — read [the ports and power note](#ports-and-power) before
choosing.

### USB-C Ethernet adapter — best link

An Anker (or any) USB-C gigabit adapter works with nothing configured. They are
almost all either Realtek RTL8153 (`r8152`) or ASIX AX88179 (`ax88179_178a`);
both drivers are in mainline and present on the installer ISO, so the adapter
enumerates as an ordinary wired interface and the ISO's DHCP client picks it up
unprompted:

```bash
ip -br a               # a new enp0s20f0u*-style interface, with an address
```

Nothing to install, no passphrase to type, and a link that will not be the
reason [§5](#5-install) takes an hour. This is the one to use if the power
question below allows it.

### USB tethering from a phone

Same shape, no adapter needed. Plug the phone into a USB-C port and enable USB
tethering; it enumerates as `cdc_ether` or `rndis` and DHCP does the rest.
Watch the data if you are not on an unlimited plan — [§5](#5-install) pulls
several gigabytes. Occupies a port exactly as the Ethernet adapter does.

### Ports and power

The 9310 has **two USB-C ports and nothing else**, and it charges over those
same ports. The installer stick has to stay plugged in for the whole session —
the ISO's store is a squashfs read from it, so it cannot be pulled once you
have booted. That leaves exactly one free port, and both wired options above
take it:

| Route | Ports used | Can charge during the install |
|---|---|---|
| Ethernet adapter or phone tethering | stick + adapter | **no** |
| Wi-Fi | stick only | yes |
| USB-C hub with PD passthrough | stick + hub | yes |

So the choice is a real trade rather than a preference. In order of what to
reach for:

1. **A USB-C hub with power delivery passthrough**, if you have one — Anker
   make several, and it removes the trade entirely: Ethernet and charging on
   the one port.
2. **The Ethernet adapter on a full battery.** The install is perhaps half an
   hour of downloading and building; a healthy 9310 at 100% will finish it
   comfortably. Check the charge before you start, not after `disko` has run.
3. **Wi-Fi**, if the battery is low and there is no hub. It is the fiddliest
   route to configure and the only one that leaves a port free for the charger,
   which on a machine that has been sitting in a drawer is the deciding factor.

Nothing here is destructive to get wrong — a flat battery mid-install leaves an
unbootable disk, which is recoverable by charging it and starting again from
[§4](#4-partition-and-mount). It is an hour lost, not a machine.

### NetworkManager, if this ISO has it

Which tools the minimal ISO carries has moved around between releases. Check
before assuming:

```bash
command -v nmtui nmcli
```

If either is there, use it and skip the next section:

```bash
systemctl start NetworkManager
nmtui                              # or: nmcli device wifi connect "YourSSID" --ask
```

### The `wpa_cli` route

The fallback, and the one the NixOS manual documents for the minimal ISO. Note
the interface name from `ip -br a` — usually `wlan0` or `wlp0s20f3`:

```bash
systemctl start wpa_supplicant
wpa_cli
```

```
> add_network
0
> set_network 0 ssid "YourSSID"
> set_network 0 psk "YourPassword"
> enable_network 0
> quit
```

The quotes around the SSID and passphrase are part of `wpa_cli`'s syntax rather
than shell quoting; without them it reports `FAIL` on a line that looks
correct. `add_network` prints the id it allocated — it is `0` on a fresh
installer, which is what the subsequent lines assume.

`key_mgmt` is deliberately not set: it defaults to `WPA-PSK`, which is right
for WPA2 and for the WPA2/WPA3 mixed mode most home routers run. On a
**WPA3-only** network that default fails to associate, and the network needs
`set_network 0 key_mgmt SAE` plus `set_network 0 ieee80211w 2` instead.

### Confirm it before moving on

Whichever route you took:

```bash
ip -br a               # the interface should have an inet address
ip route               # and a default route through it
ping -c3 cache.nixos.org
```

All three, not just the first. Associating with an access point, getting a DHCP
lease and having working DNS are separate things that fail separately — and the
install fetches several gigabytes from the binary cache over this link, so a
marginal connection here means a `nixos-install` that stalls in
[§5](#5-install) rather than one that fails cleanly.

Staying in that root shell is the simplest thing to do, and it sidesteps a trap
in [§3](#3-generate-the-hardware-scan--before-disko): `sudo` covers the command
it prefixes, never the `>` redirect after it.

## 2. Clone and fill in the disk ID

`hosts/scribe/disko.nix` carries this machine's actual device now —
`nvme-PC_SN730_NVMe_WDC_1024GB_2041C7801763`, read off it during the install —
so for a reinstall of this laptop the section below is a check and not an edit.
For a different machine, or after a disk swap, it is an edit, and §4 formats
whatever you put there.

```bash
nix-shell -p git
git clone https://github.com/antalakas/nix-systems /tmp/nix-systems
cd /tmp/nix-systems

lsblk -o NAME,SIZE,MODEL,SERIAL
ls -l /dev/disk/by-id/ | grep -v part
```

Take the `nvme-<model>_<serial>` form — readable, and stable across the
`nvme-eui.*` and `..._1` duplicate aliases the kernel also exposes. Then prove
that what the file says resolves to a device that exists, which is the check
that matters and the one you can run either way:

```bash
grep -n mainDisk hosts/scribe/disko.nix
test -e "$(sed -n 's/.*mainDisk = "\(.*\)";/\1/p' hosts/scribe/disko.nix)" \
  && echo "OK: disko points at a device that exists" \
  || echo "BAD: path does not resolve — do not run disko"
```

If it does need replacing, edit the **assignment** rather than every occurrence
of the old string. The word being replaced appears in the comment above it too,
and a blanket `sed -i "s|OLD|NEW|"` rewrites that prose into a sentence saying
the opposite of what it means — which is exactly what happened during this
install, and it went unnoticed until the file was read back on the laptop.

**If `lsblk` shows no NVMe device at all, the disk is not broken and the cable
is not loose** — there is no cable. Go back to the BIOS and set `SATA
Operation` to AHCI. This is by far the most common way this install stalls, and
it presents as missing hardware rather than as a setting.

The other device in that listing is the installer stick. There is only one
internal drive on this machine, so unlike nuc there is no pair to tell apart —
but there is also no second chance if you name the stick.

Note the clone is over **HTTPS**, and not only because the installer has no
key. This tree becomes `/etc/nixos` in [§5](#5-install), where git runs as root
and root never consults `~andreas/.ssh` — forge's "…and an HTTPS remote, for
the same reason" covers it at length.

## 3. Generate the hardware scan — before `disko`

Same reversal as nuc's §3, same reason: `disko --flake .#scribe` has to
evaluate `nixosConfigurations.scribe` to reach `disko.devices`; evaluating it
imports `hosts/scribe/hardware-configuration.nix`; and that file `throw`s,
because it is a placeholder whose whole job is to fail legibly rather than let
a rebuild die later with a missing `fileSystems."/"`.

```bash
sudo nixos-generate-config --no-filesystems --show-hardware-config \
  > /tmp/nix-systems/hosts/scribe/hardware-configuration.nix
```

`--no-filesystems` is required: `disko.nix` already declares every filesystem,
and a second set of definitions collides with it.

Read the output before trusting it:

```bash
grep -nE "availableKernelModules|fileSystems|swapDevices|hostPlatform" \
  hosts/scribe/hardware-configuration.nix
```

- `nvme` in `boot.initrd.availableKernelModules`. This is the one that decides
  whether the machine boots at all.
- **`xhci_pci` in the list — and `usbhid` absent from it, which is correct.**
  This host cares about the initrd keyboard in a way forge and nuc do not: the
  root filesystem is behind LUKS, so the initrd takes a passphrase from the
  keyboard *before* the real system starts, and a keyboard that is not driven
  yet cannot type one. The scan does not list the HID modules — NixOS adds them
  separately through `boot.initrd.includeDefaultModules`, which defaults to
  true and which nothing in `hosts/scribe/` turns off. So check the *merged*
  option rather than the scan:

  ```bash
  nix --experimental-features "nix-command flakes" eval --json \
    /tmp/nix-systems#nixosConfigurations.scribe.config.boot.initrd.availableKernelModules \
    | tr ',' '\n' | grep -Ei 'hid|kbd'
  ```

  Want `usbhid`, `hid_generic` and `atkbd` among the results — internal and USB
  keyboards are driven by different modules and it costs nothing to carry all
  three. Check it here rather than at the prompt in [§6](#6-first-boot), where
  the only way out is another installer boot and a hand-mounted LUKS volume.
- **No `fileSystems` and no `swapDevices` lines at all.** `--no-filesystems`
  suppresses the entire storage section rather than emitting empty lists, so
  absent is the expected answer for both. If either *does* appear, the flag was
  missed and the definitions will collide with `disko.nix`.
- `nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";`

Then check the throw is gone. This is cheap and it fails now rather than four
minutes into `disko`:

```bash
nix --experimental-features "nix-command flakes" \
  eval /tmp/nix-systems#nixosConfigurations.scribe.config.networking.hostName
#   warning: Git tree '/tmp/nix-systems' is dirty
#   "scribe"
```

The warning is the mechanism working rather than something to fix. You are
overwriting two *tracked* files — the scan and `disko.nix` — which is why a
dirty working tree is enough: a flake evaluates against a copy of the tree
containing only tracked files, so modifications to one are picked up and a
brand-new file would be invisible. That asymmetry bites for real in
[§7](#7-move-secrets-under-sops), where the new file is `secrets/scribe.yaml`.

### Force the whole config, not just one option

`networking.hostName` touches almost nothing. This forces every option in
`hosts/scribe/`, `modules/desktop.nix` and `home/niri-desktop.nix`, and still
builds nothing:

```bash
nix --experimental-features "nix-command flakes" eval --raw \
  /tmp/nix-systems#nixosConfigurations.scribe.config.system.build.toplevel.drvPath
#   /nix/store/…-nixos-system-scribe-26.11.….drv
```

A store path back means the configuration is sound. This is what closes the gap
the status section warns about, and it costs a minute of CPU against an hour of
`nixos-install` and a destroyed disk.

Worth confirming the LUKS wiring reached the system config too, rather than
only `disko.devices`:

```bash
nix --experimental-features "nix-command flakes" \
  eval /tmp/nix-systems#nixosConfigurations.scribe.config.boot.initrd.luks.devices \
  --apply builtins.attrNames
#   [ "cryptroot" ]
```

## 4. Partition and mount

This destroys the disk.

**Choose the passphrase before you run this.** You will be asked for it twice
in quick succession — once by `cryptsetup luksFormat`, once by `luksOpen` — and
they are separate prompts rather than the usual type-it-twice confirmation. A
typo in the first is silently carried into the volume; the second then fails,
and you have to start the whole step again. It also cannot be recovered: there
is no key escrow, and forgetting it means the disk is gone. Put it in
1Password now, not afterwards.

```bash
sudo nix --experimental-features "nix-command flakes" \
  run github:nix-community/disko/latest -- \
  --mode destroy,format,mount \
  --flake /tmp/nix-systems#scribe

findmnt -R /mnt
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
```

`/mnt`, `/mnt/home`, `/mnt/nix`, `/mnt/var/lib/docker`, `/mnt/.snapshots` and
`/mnt/boot` should all be mounted. `lsblk` should show a `crypt` device named
`cryptroot` sitting on the second partition, with the btrfs subvolumes above
it — that nesting is the thing to actually look at, because it is the
difference between an encrypted install and an unencrypted one that otherwise
behaves identically.

`hosts/scribe/disko.nix` names no `passwordFile`, which is what makes those
prompts interactive. If you ever need to run this non-interactively — scripting
a reinstall, say — write the passphrase to a file on the *installer's* tmpfs
and point `passwordFile` at it for that run only. Do not commit it: this repo
is public, and a passphrase in git history is not a passphrase.

`/mnt/var/lib/docker` will show `compress=zstd:3` and no `nodatacow`, despite
what `disko.nix` asks for. That is btrfs, not a mistake — mount options apply
per filesystem, not per subvolume, so the first mount wins. What actually
disables COW is the NOCOW inode attribute, which the `systemd.tmpfiles` rule in
`hosts/scribe/default.nix` sets on first boot. Setting it here as well costs
nothing and closes the window, because the subvolume is empty exactly once and
the attribute only governs files created after it:

```bash
sudo chattr +C /mnt/var/lib/docker
lsattr -d /mnt/var/lib/docker      # expect ---------------C------
```

Unlike nuc, nothing on this host pulls a container image on first boot —
`modules/k8s-dev.nix` is not imported — so this one is genuinely belt-and-braces
rather than a race you are trying to win.

## 5. Install

Two things to settle before starting, both cheap now and expensive later:

- **Run it inside `tmux`.** §1's Wi-Fi route makes it likely you are driving
  this over ssh from another machine, and a dropped connection takes
  `nixos-install` with it — an hour of downloading, restarted. `nix-shell -p
  tmux`, then `tmux new -s install`; reconnect with `tmux attach -t install`.
- **Stay in one root shell from §2 through §5.** Cloning as root at the console
  and then ssh'ing back in as `nixos` leaves a tree you cannot write, and the
  `sed` in §2 fails with `couldn't open temporary file … Permission denied`,
  which reads like a full disk rather than a permission problem.

```bash
sudo mkdir -p /mnt/etc
sudo cp -rT /tmp/nix-systems /mnt/etc/nixos
ls /mnt/etc/nixos                       # flake.nix at the top level
sudo nixos-install --flake /mnt/etc/nixos#scribe   # set the root password when prompted
sudo nixos-enter --root /mnt -c 'passwd andreas'
```

The `mkdir` and the `-T` are both nuc's, for nuc's reasons — the reordering in
[§3](#3-generate-the-hardware-scan--before-disko) means nothing has written
under `/mnt/etc` before now, and `cp -T` creates the destination but not its
parent. Keep `-T`: it is the difference between `/mnt/etc/nixos/flake.nix` and
`/mnt/etc/nixos/nix-systems/flake.nix`, and `nixos-install` fails on the second.

If the root password prompt at the very end fails — mistyping the confirmation
is the easy way — nothing is lost and there is no need to start over.
`nixos-install` sets it last, after the system and bootloader are written, and
prints the recovery itself:

```bash
nixos-enter --root '/mnt'
passwd
exit
```

Set the `andreas` password with care and do not skip it. greetd is the only way
into this machine at the console, there is no root login over SSH
(`PermitRootLogin = "no"`), and unlike forge and nuc there is no LAN sshd
listening on every interface to fall back to — `hosts/scribe/default.nix`
scopes port 22 to `tailscale0`, which does not exist yet.

This is a bigger download than the other two hosts: a full Wayland session,
Firefox, Brave and Zed, over Wi-Fi. Expect it to take a while, and see
[§1](#1-boot-the-installer-and-get-on-the-network) about signal.

There is no host key to restore — this machine has never run NixOS, so it gets
a fresh one, which is what [§7](#7-move-secrets-under-sops) then encrypts to
and what [§9](#9-aftercare) tells you to back up.

Pull the USB stick, then `reboot`.

## 6. First boot

The passphrase prompt comes first, before anything else on screen. **This is
the moment the `usbhid` check in [§3](#3-generate-the-hardware-scan--before-disko)
pays off or does not.** If the keyboard is dead here, nothing you type reaches
cryptsetup and the machine cannot boot; the way out is to boot the installer
again, `cryptsetup luksOpen` by hand, mount, and add the missing modules to
`boot.initrd.availableKernelModules` before rebuilding. It is far more likely
to just work.

After that, greetd's text greeter, then the niri session. What to expect, and
what each thing tells you:

```bash
systemctl --failed
findmnt -R /
nixos-version
```

`nixos-version` is worth a moment. `system.stateVersion` in
`hosts/scribe/default.nix` and `home.stateVersion` in `hosts/scribe/home.nix`
both say `26.11`, copied from forge and nuc. They pin compatibility defaults
for stateful services, so they are set once at install and left alone — moving
one later silently changes those defaults under existing data. If
`nixos-version` reports something else, decide now, before the first `nrs` and
before anything stateful accumulates. Older-than-actual is conservative rather
than broken; the point is to have looked.

### Wi-Fi, this time with NetworkManager

The installed system has NetworkManager, so the `wpa_cli` dance is over.
`nm-applet` is in the tray (the niri profile spawns it), or from a terminal:

```bash
nmcli device wifi list
nmcli device wifi connect "YourSSID" --ask
```

### Joining the tailnet

```bash
sudo tailscale up --ssh
```

This is markedly easier than it was on nuc, and for a reason worth noting: this
host has a browser. nuc's §6 goes to some length about copying a login URL off
a headless console; here the URL opens where it is printed.

`secrets/scribe.yaml` does not exist yet, so `hosts/scribe/default.nix` has not
imported `secrets.nix` and nothing in the config references a secret. This one
manual `tailscale up` is what the bootstrap ordering costs, and
[§7](#7-move-secrets-under-sops) is what stops it recurring on the next install.

Unlike nuc, there is no stale tailnet device holding this name — the machine is
new to the tailnet. Confirm it got the plain name anyway, because the same
collision waits on every *reinstall* from here on:

```bash
tailscale status | head -3          # must say `scribe`, not `scribe-1`
```

### Reaching it from the main laptop

```bash
# main laptop
ssh andreas@scribe.taile6c0b.ts.net
```

The tailnet FQDN rather than the short name, for nuc's §6 reason: the router
answers short names out of its own DHCP records before MagicDNS is consulted.
An alias sidesteps it:

```
# ~/.ssh/config on the main laptop
Host scribe
  HostName scribe.taile6c0b.ts.net
  User andreas
```

Note what is *not* available on this host: there is no LAN fallback. forge and
nuc keep port 22 open on every interface precisely for the day Tailscale is the
thing that broke; `hosts/scribe/default.nix` deliberately does not, because a
laptop's "every interface" includes café Wi-Fi. The fallback here is the
keyboard, which — this being a laptop — is always attached.

## 7. Move secrets under sops

Now that the host has an SSH host key it can decrypt its own secrets. This is
forge's §7 and nuc's §7 with the names changed.

```bash
# on scribe
ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
```

Add that to `.sops.yaml` as `&scribe`, alongside `&forge`, `&nuc` and
`&andreas`, and give `secrets/scribe\.yaml$` a `creation_rules` entry encrypted
to `*scribe` and `*andreas`. Both keys, always: the host key dies with the host,
and the personal key on the laptop is the only recovery path.

Create the file **from your laptop clone**, not `/etc/nixos`. That one is
root-owned so you cannot write it, and reaching for `sudo` makes it worse —
`sudo` resets `HOME` to `/root`, where there is no
`~/.config/sops/age/keys.txt`, so sops reports it cannot decrypt with any key.

```bash
cd ~/dev/nix-systems
sops secrets/scribe.yaml
```

```yaml
tailscale_authkey: tskey-auth-...   # reusable, from the Tailscale admin console
```

Then the step nothing complains about when you skip it:

```bash
git add secrets/scribe.yaml
```

`hosts/scribe/default.nix` imports `secrets.nix` behind
`builtins.pathExists ../../secrets/scribe.yaml`, and a flake sees only tracked
files. An untracked `secrets/scribe.yaml` is invisible to that check, so the
import stays off and the rebuild succeeds having changed nothing at all. Commit
it; it is encrypted, which is the point of committing it.

### Land the hardware scan and the disk ID at the same time

The install left two in-place edits in `/etc/nixos`: the hardware scan from
[§3](#3-generate-the-hardware-scan--before-disko) and the disk ID from
[§2](#2-clone-and-fill-in-the-disk-id). Get both into git from the laptop
rather than committing on the box, so `/etc/nixos` stays a deploy target that
only ever reads:

```bash
# main laptop
scp andreas@scribe:/etc/nixos/hosts/scribe/hardware-configuration.nix hosts/scribe/
scp andreas@scribe:/etc/nixos/hosts/scribe/disko.nix hosts/scribe/
git add hosts/scribe/hardware-configuration.nix hosts/scribe/disko.nix \
        secrets/scribe.yaml .sops.yaml
git commit && git push
```

```bash
# scribe — discard the local copies in favour of the ones you just pushed
sudo git -C /etc/nixos checkout hosts/scribe/
sudo git -C /etc/nixos pull
sudo git -C /etc/nixos status      # clean
nrt && nrs
```

`sudo git` is not optional in `/etc/nixos` — the clone was made as root, so git
run as `andreas` refuses it with "dubious ownership". See
[§9](#9-aftercare) for the ownership question, which nuc answers differently
from forge.

Check the secret landed rather than trusting the build:

```bash
sudo ls -l /run/secrets/tailscale_authkey   # root:root, 0400
systemctl status tailscaled-autoconnect
```

## 8. Verify the desktop

The section neither headless host has. Most of this is one command each, and
two of them are settings that were guessed off-machine — both of which this
machine has since confirmed, so what follows records the answer as well as the
check.

**Panel scale — a guess when this was written, and right.** The 9310 shipped
with two very different panels; this machine has the FHD+ one, which is what
`dotfiles/niri/config-mobile.kdl` assumes:

```bash
niri msg outputs
#   Output "Sharp Corporation 0x14F9 Unknown" (eDP-1)
#     Current mode: 1920x1200 @ 59.950 Hz (preferred)
#     Logical size: 1536x960    Scale: 1.25
```

- `1920x1200` → `scale 1.25` as committed, giving 1536x960 logical. Leave it.
- `3840x2400` → change it. `scale 2` gives 1920x1200 logical, which is small on
  a 13.4" panel; `scale 2.5` gives 1536x960, matching the above.

Edit `dotfiles/niri/config-mobile.kdl`, `nrs`, then `niri msg action
load-config-file` — or just log out and back in.

**Audio — the most likely thing to have been wrong, and it worked on the first
boot.** Nothing configured sound in this repo before this host, so
`modules/desktop.nix` is the first place PipeWire appears.

```bash
wpctl status                 # a sink and a source, not "no devices"
systemctl --user status pipewire wireplumber
```

Here that gave a Speaker sink and a Digital Microphone source on the 500 Series
on-package HD Audio device, with pipewire, wireplumber and pipewire-pulse all
active — so the SOF firmware loaded.

An empty device list here almost always means firmware rather than
configuration — Tiger Lake's audio DSP needs the SOF blobs that
`hardware.enableRedistributableFirmware` supplies. `dmesg | grep -i sof` says
so directly.

**The lock screen, and check it *unlocks*.**

```bash
swaylock
```

Then type your password and get back in. This is worth doing deliberately once,
in a place where you can reboot if it goes wrong, because the failure mode is
specific: swaylock authenticates against a PAM service of its own name, and
without one it locks perfectly well and then rejects every correct password.
`modules/desktop.nix` declares `security.pam.services.swaylock`; this confirms
it took.

**Battery.**

```bash
sudo tlp-stat -b       # read this one properly, see below
upower -i $(upower -e | grep BAT)
```

`hosts/scribe/default.nix` asks TLP to stop charging at 80%, which is right for
a machine that spends weeks on a desk and wrong for the morning before a day
out. **Whether it takes effect is not a given** — charge thresholds are a
ThinkPad feature that TLP drives through the kernel's
`charge_control_*_threshold` sysfs files, and `dell_laptop` exposes them only
on some models. On this one it does:

```
Plugin: dell
Supported features: charge thresholds
Driver usage:
* natacpi (dell_laptop) = active (charge thresholds)
/sys/class/power_supply/BAT0/charge_control_start_threshold =     75 [%]
/sys/class/power_supply/BAT0/charge_control_end_threshold   =     80 [%]
```

So the setting is live rather than inert. If `tlp-stat -b` instead reports the
feature unavailable, the two settings do nothing and the working equivalent is
in the BIOS, under *Primary Battery Charge Configuration* → Custom.

Read `charge_full` against `charge_full_design` in the same output while you
are there. This machine came back at 4018 of 6707 mAh — about 60% of its
original capacity, ordinary for a 2020 laptop that has sat unused, but it makes
the 80% stop 80% of a battery that is already three-fifths of what it was.

**The rest of the session**, quickly: `Mod+D` opens fuzzel, `Mod+Return` a
terminal, `Mod+A` a region screenshot, the brightness and volume keys move
their respective things. Every one of those is a bind that pointed at a package
no host installed before `modules/desktop.nix` existed, so this is a real check
rather than a formality.

**The ssh tint.** From this machine, `ssh andreas@forge` — the terminal should
repaint blue and the focus ring turn amber. From the main laptop, `ssh
andreas@scribe` should repaint amber-brown with a green ring. The second half
needs the main laptop rebuilt too, since the rule was added to its niri
profiles.

## 9. Aftercare

The things nothing reminds you about. The first two are specific to this being
the only encrypted host in the flake, and they are the two that cannot be
recovered from later.

- **Back up the LUKS header.** A corrupted header makes the disk unreadable
  *permanently* — every correct passphrase in the world will not open a volume
  whose key material is gone. It is 16MB and it is the whole game.

  ```bash
  DEV=/dev/disk/by-id/nvme-<model>_<serial>-part2
  sudo cryptsetup isLuks "$DEV" && echo "yes, LUKS"
  sudo cryptsetup luksHeaderBackup "$DEV" \
    --header-backup-file /tmp/scribe-luks-header.img
  ```

  **`-part2`, not the bare disk.** The LUKS container is the second GPT
  partition; the whole-disk path is the container holding it, and `cryptsetup`
  rejects it with `is not a valid LUKS device` — which reads like the
  encryption is missing rather than like a wrong path. `lsblk -f` shows which
  partition says `crypto_LUKS`.

  Move it off the machine — a header backup stored on the disk it protects is
  not a backup. Treat it as equivalent to the passphrase, because with the
  passphrase it *is* the disk: anyone holding both can open the volume even
  after you change the passphrase, since a header backup preserves the old key
  slots. Encrypted, off-site, alongside the age key.

- **Add a second LUKS passphrase**, and put it somewhere you cannot lose. One
  keyslot is a single point of failure that is entirely inside your head.

  ```bash
  sudo cryptsetup luksAddKey "$DEV"
  sudo cryptsetup luksDump "$DEV" | grep -A3 Keyslots
  ```

  Generate a long random one, store it in 1Password, and never type it. The
  daily passphrase stays memorable; this is the one that survives forgetting it.

The rest are forge's and nuc's, plus two Dell-specific ones:

- **Disable the node key expiry.** Tailscale admin console → Machines → scribe
  → Disable key expiry. Two clocks are easily conflated: the auth key's 90 days
  only governs whether it can still enrol a machine, while the *node* key
  expires on the tailnet default of 180 days and drops the box off the tailnet
  when it does. There is no CLI equivalent, and a reinstall re-enrols as a new
  device with a fresh clock, so this belongs on the redo list.
- **Back up the SSH host key**, off the machine, following forge's §7. Without
  it a reinstall generates a new host key, the derived age key no longer matches
  `.sops.yaml`, and the box cannot decrypt its own secrets.
- **Update the firmware.** Dell publishes BIOS and Thunderbolt firmware for this
  model through LVFS, and there is no Windows partition left to run Dell Update
  from, so `services.fwupd` is the supported path:

  ```bash
  fwupdmgr refresh
  fwupdmgr get-updates
  fwupdmgr update
  ```

  Do it on mains power. A BIOS update interrupted by a flat battery is the one
  failure here that a reinstall does not fix.
- **Decide the `/etc/nixos` ownership.** nuc chowns the tree to `andreas` so git
  there needs no `sudo`; forge keeps it root-owned. nuc's own §9 argues the
  trade both ways, and its conclusion leans on that host running nothing but
  your shells. This one is a laptop that leaves the house, which pushes the
  other way — every process running as you could otherwise write what root then
  builds into the system. Left root-owned here on purpose; `sudo git -C
  /etc/nixos` is the cost.
- **No hibernation, and that is a choice.** `zramSwap` with no swap device
  means a closed lid is a suspend, which drains. If that turns out to matter,
  hibernation needs a real swap partition sized to RAM *inside* the LUKS
  volume — which is a reinstall, not a rebuild.

## Design notes

Why this host is shaped the way it is. None of this is needed to follow the
install; it is here so the decisions are recoverable a year from now, when the
only remaining evidence is the config itself.

### It is a client, not a builder

`scribe` runs the niri session, a terminal, a browser and Zed. Claude Code runs
on **forge**, over the tailnet, and this laptop is the thing in front of it.
That is the whole premise: a machine light enough to carry that is still a real
x86 laptop, instead of a tablet that could only ever have been a terminal.

Two consequences that look like omissions and are not:

- **`modules/k8s-dev.nix` is not imported.** No kind, no registry container.
- **Docker is socket-activated** rather than started at boot
  (`virtualisation.docker.enableOnBoot = false`). It is still enabled by
  `modules/common.nix` and `docker ps` still works — the daemon starts on first
  use, costing a second. Idling it through a battery day buys nothing when the
  containers are all on another machine. This is what the `mkDefault` change in
  `modules/common.nix` exists for; without it the override would be a conflict
  rather than an override.

The Claude Code sandbox from `home/common.nix` is still installed here, because
it needs nothing but Docker and is identical on every host. It will work. It is
a fallback, not the path.

### It imports `modules/desktop.nix` and *not* `modules/server.nix`

The two are mirrors — a host takes one or the other. But `scribe` also needs
sshd, which lives in `server.nix`, so it declares its own instead of importing
that module. The reason is one line:

```nix
# modules/server.nix
networking.firewall.allowedTCPPorts = [ 22 ];   # every interface
```

Sound for a box behind the house NAT, where "every interface" means the LAN and
the tailnet. Wrong for a laptop that joins café and airport Wi-Fi, where it
means a network full of strangers. `hosts/scribe/default.nix` scopes port 22 to
`tailscale0` instead.

**The cost is that this host has no LAN fallback.** forge and nuc keep port 22
open everywhere precisely for the day Tailscale is the thing that broke; that
option is deliberately given up here. The fallback on this machine is the
keyboard, which — it being a laptop — is always attached. That trade only works
because it is a laptop, and it should be revisited if `scribe` ever spends its
life on a desk.

The rest of `server.nix` was not lost in the process: the kind inotify limits
are irrelevant without kind, and the journald cap and `fstrim` are either
defaults or unimportant at this scale.

### It is the only encrypted host

forge and nuc sit in one building and are never carried. `scribe` is the only
machine in the flake where "someone else is holding the disk" is a realistic
state, which is why it is the only one with LUKS.

What is actually being protected is not really the documents — it is the SSH
host key, the age key derived from it, and the tailnet node key, which together
constitute a working identity on the tailnet rather than merely a laptop.

Encryption cannot be retrofitted without a reinstall, which is why it is here
on day one rather than deferred. The two irreversible consequences — the header
backup and the second keyslot — are in [§9](#9-aftercare) and are the two items
on that list that cannot be done later.

### It is the first host that is both ends of the ssh tint

`home/ssh-tint.nix` had one job: repaint the *client's* terminal when you ssh
into a headless box. `scribe` is a machine you sit at **and** one that is
reachable over the tailnet, so it needs both halves, and the module grew a
second option to say so:

- `enable` — the remote half. Paints the terminal of whoever ssh's *in* here.
  Amber-brown `#33210f`, chosen by hue against forge's blue and nuc's green, at
  the same brightness.
- `clientReset` — the local half. Clears a tint left behind when *this*
  machine's session to forge or nuc drops without running its own exit hook.

The main laptop wants only `clientReset` and still carries its own inline copy
of it, predating the option. That is duplication to collapse whenever
`hosts/nixos` is next touched.

The matching focus-ring rule — green `#9ece6a`, against forge's amber and nuc's
violet — had to be added by hand to `config-home.kdl` and `config-office.kdl`.
Nothing generates those, and the module's own docstring is the only thing that
says so.

### The desktop modules are new, and the laptop does not use them yet

`modules/desktop.nix` and `home/niri-desktop.nix` were extracted from
`hosts/nixos` so that `scribe` would not be a copy-paste of it — but
`hosts/nixos` still carries its own inline copies and imports neither. See
[Not set up yet](#not-set-up-yet); it is the largest loose end here.

Two things in those modules are genuinely new rather than lifted, and both are
fixes to bugs that were live on every host:

- **PipeWire.** Nothing in this repo configured audio at all. The niri binds
  have been driving volume through `wpctl` — which is WirePlumber — on hosts
  where nothing installed it.
- **swaylock, and its PAM service.** `Super+Alt+L` has been bound in every niri
  profile since the beginning, and no host installed swaylock. The PAM entry is
  the half that is easy to miss and impossible to diagnose *from* the lock
  screen: without a PAM service of its own name, swaylock locks correctly and
  then rejects every correct password.

## Not set up yet

- **Migrating the main laptop onto the shared modules.** `modules/desktop.nix`
  and `home/niri-desktop.nix` were extracted from `hosts/nixos` when this host
  was added, but `hosts/nixos` still carries its own inline copies of
  everything in them and does not import either. The two will drift, and until
  the migration happens **a change to the desktop has to be made twice**.

  It was left alone deliberately: that config needs `--impure` and imports
  `langfuse.nix` from outside the repo, so it cannot be evaluated from anywhere
  but the machine itself, and a refactor that cannot be tested against the
  daily driver is not one to do blind. The pieces that would move are listed at
  the top of `modules/desktop.nix`.

  Two things in the shared modules are genuinely new rather than lifted, and
  the laptop would gain them: PipeWire (nothing in this repo configured audio
  at all) and the swaylock PAM service (the `Super+Alt+L` bind has been a no-op
  on every host, since no host installed swaylock).

- **The niri profile duplication.** `config-mobile.kdl` is a third near-copy of
  a 700-line file. niri's KDL has no include directive, so profiles must be
  whole files and this cannot be factored out in the config itself — but
  *generating* the three from a shared nix expression would work, and is the
  obvious fix if a fourth profile ever appears. See the note at the top of
  `dotfiles/niri/PROFILES.md`.

- **Backups.** There are none, deliberately: this host has one disk and holds
  nothing that should exist only here. That is an assumption worth re-checking
  rather than a guarantee — the moment something on this laptop is not also in
  a git remote, it needs either a habit or a `backup.nix`. `hosts/forge/backup.nix`
  is the template, and note its ordering trap: the restic password goes into
  sops *before* the rebuild that declares it.

- **Fingerprint reader.** The 9310's is a Goodix 27c6:5395 in the power button,
  with no working Linux driver. Nothing to do, recorded so nobody spends an
  evening on it.
