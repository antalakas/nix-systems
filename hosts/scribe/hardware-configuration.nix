# Placeholder. Replaced during the install by a real hardware scan:
#
#   sudo nixos-generate-config --no-filesystems --show-hardware-config \
#     > hosts/scribe/hardware-configuration.nix
#
# `--no-filesystems` is required, because ./disko.nix already declares every
# filesystem and a second set of definitions collides with it.
#
# This file `throw`s rather than being empty or absent so the failure is legible
# and early. An empty file would evaluate fine and then fail much later, during
# the first rebuild, with a missing `fileSystems."/"` — and a file that is
# absent would not be tracked by git, which a flake needs it to be.
#
# The throw is also why the install runs the hardware scan *before* `disko`,
# reversing forge's order: `disko --flake .#scribe` has to evaluate
# nixosConfigurations.scribe to reach disko.devices, and evaluating it imports
# this file. Writing the scan first breaks the cycle. See
# docs/scribe-install.md §3, and the same note in docs/nuc-install.md §3.

throw ''
  hosts/scribe/hardware-configuration.nix is still the placeholder.

  Generate the real one on the machine, from the installer:

    sudo nixos-generate-config --no-filesystems --show-hardware-config \
      > /tmp/nix-systems/hosts/scribe/hardware-configuration.nix

  See docs/scribe-install.md §3.
''
