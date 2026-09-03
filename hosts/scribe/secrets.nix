# sops-nix wiring for scribe. Imported only once secrets/scribe.yaml exists —
# adding a secret name here before the key is in that file fails activation,
# because sops-install-secrets will not shrug off a secret it cannot find. Edit
# the file first, then rebuild. See the bootstrap order in
# docs/forge-install.md §7.

{ config, lib, ... }:

{
  sops = {
    defaultSopsFile = ../../secrets/scribe.yaml;
    # Decrypt with a key derived from the host's SSH host key, so the machine
    # can unlock its own secrets on boot with nothing else provisioned.
    #
    # Worth being clear about what this does and does not buy on an encrypted
    # host: the host key lives on the LUKS volume, so nothing here is readable
    # until the passphrase has been typed. sops is not adding secrecy at rest
    # that the disk encryption does not already provide — it is what keeps the
    # secret out of the *git repository*, which is public.
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # Defaults to 0400 root:root under /run/secrets, which is what tailscaled
    # wants.
    #
    # One secret, as on nuc. No restic_password: there is no second disk here
    # and no backup units, and naming a secret for a service that does not
    # exist buys a failed activation. Whatever this laptop holds that matters
    # should be pushed to a git remote rather than backed up from here.
    secrets.tailscale_authkey = { };
  };

  # With this in place a reinstall rejoins the tailnet unattended. Less
  # dramatic here than on a headless box — this machine has a screen and a
  # browser, so `tailscale up` at the console is merely tedious rather than
  # impossible — but it is one fewer manual step on a redo, and the same file
  # is where anything else this host needs will go.
  services.tailscale.authKeyFile = config.sops.secrets.tailscale_authkey.path;
}
