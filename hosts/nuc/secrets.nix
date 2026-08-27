# sops-nix wiring for nuc. Imported only once secrets/nuc.yaml exists — adding
# a secret name here before the key is in that file fails activation, because
# sops-install-secrets will not shrug off a secret it cannot find. Edit the
# file first, then rebuild. See the bootstrap order in docs/forge-install.md §7.

{ config, lib, ... }:

{
  sops = {
    defaultSopsFile = ../../secrets/nuc.yaml;
    # Decrypt with a key derived from the host's SSH host key, so the machine
    # can unlock its own secrets on boot with nothing else provisioned.
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # Defaults to 0400 root:root under /run/secrets, which is what tailscaled
    # wants.
    #
    # Deliberately shorter than forge's list, which also carries
    # restic_password. This host does have a /srv to back up to (./disko.nix
    # puts the 850 PRO there), but no restic units are configured — so naming
    # the secret would only fail activation for a service that does not exist.
    # Add it alongside a backup.nix if that changes. A Tessera .env is the
    # other obvious candidate, once docs/deployment.md is translated to NixOS.
    secrets.tailscale_authkey = { };
  };

  # With this in place a reinstall rejoins the tailnet unattended; without it,
  # someone has to run `tailscale up` at the console — which on a headless box
  # means finding a keyboard and a monitor.
  services.tailscale.authKeyFile = config.sops.secrets.tailscale_authkey.path;
}
