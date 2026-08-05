# Local Kubernetes development: kind clusters plus a shared local registry.
#
# kind clusters are throwaway; the registry outliving them is the point, so
# rebuilding a cluster does not mean re-pushing every image.

{ config, pkgs, lib, ... }:

let
  kind-up = pkgs.writeShellScriptBin "kind-up" (builtins.readFile ../dotfiles/k8s/kind-up.sh);
in
{
  environment.systemPackages = with pkgs; [
    kind
    kubernetes-helm
    kustomize
    kind-up
  ];

  # Local registry, on loopback only. Managed by systemd rather than
  # `docker run --restart` so it comes back on boot and can be inspected with
  # `systemctl status docker-kind-registry`.
  virtualisation.oci-containers = {
    backend = "docker";
    containers.kind-registry = {
      image = "registry:2";
      ports = [ "127.0.0.1:5000:5000" ];
      volumes = [ "kind-registry-data:/var/lib/registry" ];
    };
  };

  # k3s: installed but inert. Flip `enable` and rebuild to get a long-lived
  # single-node cluster alongside the throwaway kind ones — it runs as a
  # systemd service, so the two coexist without fighting over anything but RAM.
  # Add `extraFlags = [ "--disable=traefik" ];` if the bundled ingress is in
  # the way.
  services.k3s = {
    enable = false;
    role = "server";
  };
}
