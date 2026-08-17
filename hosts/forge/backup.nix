# Local restic backups into /srv — the 1TB NVMe salvaged from the Latitude,
# kept off the main filesystem on purpose (see disko.nix).
#
# What this is, stated plainly so nobody mistakes it for more: a second-disk
# backup. It survives the 4TB failing, a bad `rm`, and a rebuild that eats
# /home. It does not survive theft, fire, or a power supply that takes both
# NVMe drives with it, because /srv is in the same chassis. It is the first
# tier. Add a remote repository — restic speaks S3, B2 and rclone — once
# something here would genuinely hurt to lose.
#
# Imported only alongside secrets.nix: the repository password comes from sops,
# and restic has nothing to do without it. See the conditional in ./default.nix.

{ config, pkgs, lib, ... }:

{
  # `initialize` creates the repository but not the directory above it, and on
  # a fresh install disko mounts /srv with nothing underneath.
  systemd.tmpfiles.rules = [ "d /srv/restic 0700 root root -" ];

  services.restic.backups.local = {
    initialize = true;
    repository = "/srv/restic/forge";
    passwordFile = config.sops.secrets.restic_password.path;

    # /home is the only thing on this box that is not reproducible. The store
    # rebuilds from the flake, /var/lib/docker is images and kind clusters that
    # come back with a pull, and /srv is the repository itself. /etc/nixos is
    # this repo and therefore already on GitHub — but it is also where the
    # install's in-place edits to disko.nix and hardware-configuration.nix live
    # before anyone pushes them, and it costs kilobytes to carry.
    paths = [
      "/home/andreas"
      "/etc/nixos"
    ];

    # Patterns without a slash match at any depth, which is what you want for
    # the reproducible-from-a-lockfile ones.
    exclude = [
      "/home/andreas/.cache"
      "/home/andreas/.local/share/Trash"
      # A symlink farm into /nix/store, rebuilt by home-manager on activation.
      "/home/andreas/.zed_server"
      "node_modules"
      "__pycache__"
      ".venv"
      ".direnv"
      ".pixi"
    ];

    # Honours CACHEDIR.TAG, which cargo and friends drop into their build
    # directories — so this covers churn nobody thought to name above.
    extraBackupArgs = [ "--exclude-caches" ];

    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
    ];

    # A backup nobody has read is a hypothesis. Reading a rotating slice each
    # run gets the whole repository verified over a couple of months, without
    # paying for a full re-read every night.
    checkOpts = [ "--read-data-subset=2%" ];

    timerConfig = {
      OnCalendar = "daily";
      # Load-bearing on this host rather than a default worth leaving alone:
      # forge is powered off between sessions (see §11), so most daily runs
      # fall while it is down. Without this they are skipped outright and the
      # repository quietly stops gaining snapshots — a backup that has silently
      # stopped being taken is the failure mode worth spending a line on.
      Persistent = true;
      # So a missed run does not start the moment you wake the box to use it.
      RandomizedDelaySec = "45min";
    };
  };
}
