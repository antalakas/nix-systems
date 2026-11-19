# Tessera on the NUC: a NixOS translation of the repo's docs/deployment.md
# (Caddy §Phase 5, units/*.service + override.conf, the Cloudflare tunnel).
# The checkout itself is not managed here — it lives at /srv/tessera/tessera
# (the 850 PRO) and is cloned and built by hand. Until it exists the units
# below just fail and restart.
#
# Imported alongside ./secrets.nix, since it names sops secrets.
# nix-ld, which pixi/conda envs and npm-native binaries need (generic-Linux
# ELFs), is already on via modules/common.nix.

{ config, pkgs, ... }:
let
  home = "/srv/tessera";
  repo = "${home}/tessera";
  envFile = config.sops.secrets.tessera_env.path;
  path = with pkgs; [ pixi nodejs_22 docker bash coreutils git ];
in {
  # The same pixi/node the units use, on PATH for interactive shells (cloning,
  # `pixi install`, `npm ci && npm run build` by hand). Taken from the same
  # pkgs, so shell and services stay in lockstep across nixpkgs updates.
  environment.systemPackages = with pkgs; [ pixi nodejs_22 ];

  users.users.tessera = {
    isSystemUser = true; group = "tessera"; extraGroups = [ "docker" ];
    home = home; createHome = true; shell = pkgs.bash;
  };
  users.groups.tessera = {};

  sops.secrets.tessera_env       = { owner = "tessera"; mode = "0400"; };
  sops.secrets.cloudflared_creds = { mode = "0400"; };

  # ── Caddy: translation of deployment.md §Phase 5 (or reference/Caddyfile) ──
  services.caddy = {
    enable = true;
    virtualHosts.":80".extraConfig = ''
      @api_direct path /auth/* /storage/* /projects/linear/* /teams/* /events/* /ask/*
      handle @api_direct {
        reverse_proxy 127.0.0.1:8000 {
          flush_interval -1
        }
      }
      handle_path /api/* {
        reverse_proxy 127.0.0.1:8000 {
          flush_interval -1
        }
      }
      handle {
        reverse_proxy 127.0.0.1:3001
      }
    '';
  };

  # ── Cloudflare Tunnel: existing UUID, existing DNS route ──
  services.cloudflared = {
    enable = true;
    tunnels."5701d481-18dd-4d94-bd8b-c7999f66f27d" = {
      credentialsFile = config.sops.secrets.cloudflared_creds.path;
      ingress."tesseralabs.co" = "http://127.0.0.1:80";
      default = "http_status:404";
    };
  };

  # ── Tessera units: translation of units/*.service + override.conf ──
  systemd.services.tessera-api = {
    after = [ "network.target" "docker.service" ]; requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ]; inherit path;
    environment.PYTHONPATH = "${repo}/src";
    serviceConfig = {
      User = "tessera"; WorkingDirectory = repo; EnvironmentFile = envFile;
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'until docker compose -f docker-compose.dev.yml -f docker-compose.nuc.yml exec -T db pg_isready -U tessera; do sleep 1; done'";
      ExecStart = "${pkgs.pixi}/bin/pixi run python -m uvicorn tessera.api.main:app --host 127.0.0.1 --port 8000 --timeout-graceful-shutdown 10";
      Restart = "on-failure"; RestartSec = 5;
    };
  };
  systemd.services.tessera-web = {
    after = [ "network.target" ]; wantedBy = [ "multi-user.target" ]; inherit path;
    environment.NODE_ENV = "production";
    serviceConfig = {
      User = "tessera"; WorkingDirectory = "${repo}/apps/web";
      ExecStart = "${pkgs.nodejs_22}/bin/npm start";   # port 3001 from package.json
      Restart = "on-failure"; RestartSec = 5;
    };
  };
  systemd.services.tessera-mcp = {
    after = [ "network.target" ]; wantedBy = [ "multi-user.target" ]; inherit path;
    environment.PYTHONPATH = "${repo}/src";
    serviceConfig = {
      Type = "oneshot"; RemainAfterExit = true; KillMode = "process";  # launcher forks 16 children
      User = "tessera"; WorkingDirectory = repo; EnvironmentFile = envFile;
      ExecStart = "${pkgs.pixi}/bin/pixi run mcp-start";
      ExecStop  = "${pkgs.pixi}/bin/pixi run mcp-stop";
    };
  };
}
