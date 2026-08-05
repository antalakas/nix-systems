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

    secrets.tailscale_authkey = { };
  };

  # With this in place a reinstall rejoins the tailnet unattended; without it,
  # someone has to run `tailscale up` at the console.
  services.tailscale.authKeyFile = config.sops.secrets.tailscale_authkey.path;
}
