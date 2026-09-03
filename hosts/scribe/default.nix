# scribe — Dell XPS 9310, the portable one.
#
# A graphical client rather than a builder: it runs the niri session, a
# terminal and a browser, and the actual work happens over the tailnet on
# forge. That is the whole reason it exists — a machine light enough to carry
# that is still a real x86 laptop, instead of a tablet that could only ever be
# a terminal.
#
# It is therefore the first host to import modules/desktop.nix and the first
# not to import modules/server.nix. Both of those are deliberate and neither is
# an oversight; see the sshd note below, which is the one place the two
# profiles genuinely disagree.

{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/common.nix
    ../../modules/desktop.nix
  ]
  # Same bootstrap order as forge and nuc: sops-nix cannot encrypt for this
  # host until it has an SSH host key, which only exists after the first
  # install. Until secrets/scribe.yaml is committed, Tailscale is brought up by
  # hand once and nothing here references a secret.
  ++ lib.optionals (builtins.pathExists ../../secrets/scribe.yaml) [
    ./secrets.nix
  ];

  networking.hostName = "scribe";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # ./disko.nix fixes the ESP at 1G, so this matches forge and nuc rather than
  # the laptop's 256M cap. Still bounded: a full /boot fails the rebuild
  # partway through installing the new entry.
  boot.loader.systemd-boot.configurationLimit = 20;

  # No boot.kernelPackages pin. forge runs linuxPackages_latest only because
  # Arrow Lake-HX is newer than the default kernel knows about; Tiger Lake
  # shipped in 2020 and is comprehensively supported by anything in this
  # flake's nixpkgs. Same reasoning as nuc's Comet Lake.

  # Not optional on this machine, and the failure mode is worse than usual:
  # the 9310 has no Ethernet port, so the Killer AX1650 (an Intel AX201 under
  # the badge, driven by iwlwifi) is the *only* network interface. Without its
  # firmware blob the box boots to a login prompt with no way to reach anything
  # — including the flake it would need to fix itself. The same option supplies
  # the SOF firmware Tiger Lake's audio DSP needs; without that there is no
  # sound card at all, not merely bad sound.
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # ─────────────────────────────────────────────────────────────
  # Laptop hardware
  # ─────────────────────────────────────────────────────────────

  # A 4-core 15W part in a 13" chassis with one small fan. thermald applies
  # Intel's own throttling policy rather than letting the firmware discover the
  # limits under load — same argument as forge, different reason for it.
  services.thermald.enable = true;

  # Battery. TLP rather than power-profiles-daemon: ppd expects a desktop
  # environment to drive it and niri ships no such UI, so it would sit at
  # "balanced" forever. The two conflict, and ppd is not enabled here, so
  # nothing needs disabling.
  services.tlp = {
    enable = true;
    settings = {
      # powersave on battery, performance on AC. The intel_pstate defaults are
      # already close to this; naming them keeps the behaviour from moving when
      # the driver's defaults do.
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      # Charge thresholds, set hopefully rather than confidently. TLP drives
      # these through the kernel's charge_control_*_threshold sysfs files, and
      # whether they exist at all depends on the vendor driver: they are a
      # ThinkPad feature that `dell_laptop` supports only on some models.
      # Verify with `tlp-stat -b` rather than assuming — if it reports the
      # feature as unavailable, these two lines are inert and the working
      # equivalent is the BIOS setting, "Primary Battery Charge Configuration"
      # → Custom. Either way, drop them before a day out if you want the last
      # 20%.
      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 80;
    };
  };

  # Battery percentage and time-remaining for waybar's `battery` module, which
  # reads them over UPower's D-Bus interface rather than from /sys.
  services.upower.enable = true;

  # Dell ships BIOS and Thunderbolt firmware for this model through LVFS, so
  # `fwupdmgr refresh && fwupdmgr update` is the supported update path — there
  # is no Windows partition left to run Dell Update from. See §9 of
  # docs/scribe-install.md.
  services.fwupd.enable = true;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = false; # radio off until asked for, on battery
  services.blueman.enable = true;

  # Lid close suspends, always. The laptop's hosts/nixos/default.nix takes full
  # control of this through acpid to keep a clamshell-with-external-monitor
  # case working; this machine is carried rather than docked, so the default
  # logind behaviour is both correct and one fewer moving part. Revisit if it
  # ever acquires a dock.

  # No fingerprint reader configuration, and this is a decision rather than an
  # omission: the 9310's reader is a Goodix 27c6:5395 in the power button, and
  # it has no working Linux driver. Nothing to enable, and `fprintd` would just
  # add a PAM prompt that can never succeed.

  # NetworkManager for Wi-Fi. On a machine with no Ethernet this is the whole
  # network stack, and `nmtui` is what you use at the console before the
  # desktop is up.
  networking.networkmanager.enable = true;

  # zram rather than a swap partition. Note the consequence, since a laptop is
  # where you would want the opposite: with no swap device there is no
  # hibernation, so a closed lid is a suspend that drains. Hibernating onto the
  # LUKS volume would mean a real swap partition sized to RAM inside it — worth
  # doing if suspend drain turns out to matter, and a reinstall to add.
  zramSwap.enable = true;

  # ─────────────────────────────────────────────────────────────
  # Reaching it
  # ─────────────────────────────────────────────────────────────

  # modules/server.nix is deliberately not imported, and sshd is set up here by
  # hand instead, because the two differ on exactly one thing that matters for
  # a machine that leaves the house. That module opens port 22 on *every*
  # interface — sound for a box behind the house NAT, wrong for a laptop that
  # joins café and airport Wi-Fi, where "every interface" includes a network
  # full of strangers.
  #
  # So: key-only sshd, reachable over the tailnet and nowhere else. The rest of
  # server.nix — kind's inotify limits, the journald cap, fstrim — is either
  # irrelevant here or already a default.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 22 ];

  # Tailscale itself is enabled in modules/common.nix; this adds SSH over the
  # tailnet, authenticated against tailnet ACLs. `useRoutingFeatures =
  # "client"` is also what makes the tailscale module relax the kernel's
  # reverse-path check to "loose" on its own, which is why nothing here sets
  # networking.firewall.checkReversePath.
  services.tailscale = {
    useRoutingFeatures = "client";
    extraUpFlags = [ "--ssh" ];
  };

  users.users.andreas.openssh.authorizedKeys.keys = [
    # the main laptop
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAlPc0tM6OBS5qjtF4OOieQAXa7ki0AD78YK+7i4thkc antalakas@gmail.com"
  ];

  # ─────────────────────────────────────────────────────────────
  # Docker
  # ─────────────────────────────────────────────────────────────
  # Enabled by modules/common.nix, but socket-activated here rather than
  # started at boot: Claude Code runs on forge, so there is normally no
  # container on this machine and a daemon idling through a battery day buys
  # nothing. `docker ps` still works — docker.socket starts it on first use,
  # costing a second the first time. modules/common.nix marks `enableOnBoot`
  # mkDefault so that this is an override rather than a conflict.
  virtualisation.docker.enableOnBoot = false;

  # /var/lib/docker is its own btrfs subvolume (./disko.nix) even though this
  # host is not expected to run containers much, because the attribute below
  # only governs files created after it and so cannot be applied retroactively
  # — the cost of declaring it now is nothing, and the cost of wanting it later
  # is moving data. Same pair of settings as forge and nuc, same reasoning,
  # spelled out at length in hosts/forge/default.nix.
  virtualisation.docker.daemon.settings = {
    storage-driver = "overlay2";
  };
  systemd.tmpfiles.rules = [ "h /var/lib/docker - - - - +C" ];

  # ./secrets.nix is imported conditionally above. What is still missing after
  # the first install is the encrypted file it points at: derive this host's
  # age key with `ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub`, add it to
  # .sops.yaml, and create secrets/scribe.yaml. See docs/scribe-install.md §7.

  # The release this host was first installed from. Set once, at install, and
  # left alone: it pins compatibility defaults for stateful services, so moving
  # it later silently changes them under existing data. 26.11 is what forge and
  # nuc were installed from — confirm it against the installer before the first
  # switch.
  system.stateVersion = "26.11";
}
