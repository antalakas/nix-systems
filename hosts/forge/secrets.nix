# sops-nix wiring for forge. Imported only once secrets/forge.yaml exists —
# see the conditional import in ./default.nix and the bootstrap order in
# docs/forge-install.md.

{ config, lib, ... }:

{
  sops = {
    defaultSopsFile = ../../secrets/forge.yaml;
    # Decrypt with a key derived from the host's SSH host key, so the machine
    # can unlock its own secrets on boot with nothing else provisioned.
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # Both default to 0400 root:root under /run/secrets, which is what wants
    # them: tailscaled and the restic units all run as root.
    #
    # Adding a name here before the key exists in secrets/forge.yaml fails
    # activation — sops-install-secrets will not shrug off a secret it cannot
    # find. Edit the file first, then rebuild.
    secrets.tailscale_authkey = { };
    secrets.restic_password = { };
  };

  # With this in place a reinstall rejoins the tailnet unattended; without it,
  # someone has to run `tailscale up` at the console.
  services.tailscale.authKeyFile = config.sops.secrets.tailscale_authkey.path;
}
