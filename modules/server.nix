# Headless server profile: no display stack, reached over SSH, tuned for
# running containers and throwaway Kubernetes clusters.

{ config, pkgs, lib, ... }:

{
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Two ways in, on purpose, because a box with no display and no IPMI has no
  # third one:
  #
  #   1. Tailscale SSH (--ssh below). Authenticates against tailnet ACLs, so it
  #      keeps working even with an empty authorized_keys.
  #   2. Plain sshd on the LAN, key-only.
  #
  # Port 22 is opened on every interface; the box is behind NAT, so that is the
  # LAN plus the tailnet, not the public internet. To narrow it to the tailnet
  # only, drop the line below and use:
  #   networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 22 ];
  networking.firewall.allowedTCPPorts = [ 22 ];

  services.tailscale = {
    useRoutingFeatures = "client";
    extraUpFlags = [ "--ssh" ];
  };

  # Kubernetes-on-Docker is inotify-hungry: every kubelet, controller and
  # file-watching operator takes instances from a per-user pool sized for a
  # desktop. Exhausting it is the usual cause of pods wedged in CrashLoopBackOff
  # on a multi-node kind cluster, and the error it produces ("too many open
  # files") points nowhere near inotify.
  boot.kernel.sysctl = {
    "fs.inotify.max_user_instances" = 8192;
    "fs.inotify.max_user_watches" = 1048576;
    "fs.file-max" = 2097152;
    # containerd puts each container's secrets in a kernel keyring; the default
    # ceiling is low enough that a few hundred pods hit it.
    "kernel.keys.maxkeys" = 5000;
    # Elasticsearch/OpenSearch and anything else that mmaps aggressively.
    "vm.max_map_count" = 262144;
  };

  services.fstrim.enable = true;

  # Without a cap the journal grows until the root subvolume is the problem.
  services.journald.extraConfig = "SystemMaxUse=2G";
}
