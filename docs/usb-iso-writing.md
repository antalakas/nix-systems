# Writing an ISO to a USB stick

Everything below assumes this flake's hosts — NixOS, no full desktop
environment. That last part is the detail that trips up most guides you'll find
online: they all reach for `udisksctl`, and **this config does not have it**.

## Writing the image

`dd` from coreutils is already on every NixOS system and handles any hybrid ISO
(NixOS, Ubuntu, Fedora, Arch — they're all hybrid these days). There is nothing
to install.

```bash
lsblk -o NAME,SIZE,MODEL,TRAN          # find the stick
sudo umount /dev/sdX*                  # unmount anything auto-mounted
sudo dd if=image.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

Two things to get right:

- **Write to the whole device** (`/dev/sdb`), never a partition (`/dev/sdb1`).
  A hybrid ISO carries its own partition table; writing into a partition
  produces a stick that will not boot.
- **Check `SIZE` and `MODEL` twice.** `dd` will overwrite an internal NVMe drive
  just as happily as a USB stick, without asking. The `TRAN` column says `usb`
  for the stick and `nvme` for the things you do not want to destroy.

`conv=fsync` makes `dd` flush before it exits, so the progress bar finishing
actually means something. Without it, `dd` returns while gigabytes are still
sitting in the page cache.

## Safely removing it

There is no `udisksctl` here. `services.udisks2.enable` is off, and nothing
pulls it in implicitly — GNOME/Plasma/XFCE are what normally enable it, and
this host runs `programs.niri` with `greetd` instead. Use `util-linux` and
`coreutils`, both of which NixOS always installs:

```bash
sync                                   # flush write buffers
sudo umount /dev/sdX*                  # only if partitions got mounted
sudo blockdev --flushbufs /dev/sdX
```

Once `--flushbufs` returns, unplugging is safe. `sudo eject /dev/sdX` is
optional and only ejects — it does not cut power to the port.

For a genuine power-down, the equivalent of what `udisksctl power-off` does:

```bash
echo 1 | sudo tee /sys/block/sdX/device/delete
```

That detaches the device from the kernel. It will not come back until you
replug it.

## If you want `udisksctl` anyway

One line in `hosts/nixos/default.nix`:

```nix
services.udisks2.enable = true;
```

That buys `udisksctl power-off -b /dev/sdX` and non-root mounting of removable
media. Worth adding if external drives become a routine thing rather than an
occasional one; pair it with `udiskie` in the niri session for automount. Left
off for now deliberately — it is a D-Bus daemon that exists to serve a desktop
environment this host does not run.

## GUI and multi-ISO alternatives

Nothing needs installing — `nix run` fetches, runs, and leaves nothing behind.

| Tool | Command | Notes |
|---|---|---|
| Impression | `nix run nixpkgs#impression` | Simple GNOME-style writer, nicest for a one-off |
| USBImager | `nix run nixpkgs#usbimager` | Tiny, no-nonsense GTK writer |
| Ventoy | `nix run nixpkgs#ventoy-full` | Format the stick once, then *copy* ISOs onto it |
| balenaEtcher | `nix run nixpkgs#etcher` | Electron, heavy; only if you already like it |

Ventoy is the one worth the setup if you burn ISOs more than occasionally:
after the initial format the stick holds several bootable ISOs and you add new
ones by copying files, with no re-burning and no `dd` at all. Note that a
Ventoy stick *is* mounted as a normal filesystem, so it genuinely needs the
`umount` step above before you pull it — unlike a `dd`-ed stick, which was
never mounted in the first place.
