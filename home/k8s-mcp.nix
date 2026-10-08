# A read-only Kubernetes MCP server on this machine, tunnelled to forge so the
# Claude Code sandbox there can ask about a cluster this machine can reach.
# The cluster credentials never leave this machine: the sandbox only gets an
# HTTP endpoint on forge's loopback. Setup and limits: docs/k8s-mcp.md.
#
# Run by hand (`k8s-mcp up`), not as a service, because the AWS session behind
# the kubeconfig needs an MFA prompt at the keyboard.

{ config, pkgs, lib, ... }:

let
  cfg = config.my.k8sMcp;

  # Not in nixpkgs (checked 2026-10-08); upstream's static release binary.
  server = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "kubernetes-mcp-server";
    version = "0.0.67";
    src = pkgs.fetchurl {
      url = "https://github.com/containers/kubernetes-mcp-server/releases/download/v${version}/kubernetes-mcp-server-linux-amd64";
      hash = "sha256-15HCK1NngTzJ58ZuQF2P9/fVEYm1vWGf3YSpnPehwRY=";
    };
    dontUnpack = true;
    installPhase = "install -Dm755 $src $out/bin/kubernetes-mcp-server";
    meta.mainProgram = "kubernetes-mcp-server";
  };

  # Secrets are refused by the server as well as by the cluster role, so a
  # missing `impersonate` still never hands a secret to the sandbox.
  serverConfig = pkgs.writeText "k8s-mcp.toml" ''
    [[denied_resources]]
    group = ""
    version = "v1"
    kind = "Secret"
  '';

  k8s-mcp = pkgs.writeShellApplication {
    name = "k8s-mcp";
    runtimeInputs = with pkgs; [ kubectl yq-go aws-vault openssh curl coreutils procps util-linux server ];
    text = ''
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/k8s-mcp"
      umask 077
      mkdir -p "$state"
      kubeconfig="$state/kubeconfig"
      port=${toString cfg.port}

      # Kill only what we started: a pid file can outlive its process and the
      # number be reused.
      stop() {
        local name="$1" comm="$2" pid
        [[ -f "$state/$name.pid" ]] || return 0
        pid="$(cat "$state/$name.pid")"
        if [[ "$(ps -p "$pid" -o comm= 2>/dev/null || true)" == "$comm" ]]; then
          kill "$pid"
          echo "k8s-mcp: stopped $name"
        fi
        rm -f "$state/$name.pid"
      }

      running() {
        local name="$1" comm="$2"
        [[ -f "$state/$name.pid" ]] &&
          [[ "$(ps -p "$(cat "$state/$name.pid")" -o comm= 2>/dev/null || true)" == "$comm" ]]
      }

      up() {
        stop tunnel ssh
        stop server kubernetes-mcp-
        rm -f "$state/expires"

        local context
        context=${if cfg.context == null then ''"$(kubectl config current-context)"'' else lib.escapeShellArg cfg.context}
        kubectl config view --minify --flatten --context="$context" > "$kubeconfig"
        NS=${lib.escapeShellArg cfg.namespace} yq -i '.contexts[0].context.namespace = strenv(NS)' "$kubeconfig"
        ${lib.optionalString (cfg.impersonate != null) ''
          AS=${lib.escapeShellArg cfg.impersonate} yq -i '.users[0].user.as = strenv(AS)' "$kubeconfig"
        ''}

        (
          ${lib.optionalString (cfg.awsVaultProfile != null) ''
            creds="$(aws-vault export --format=env --duration=${lib.escapeShellArg cfg.awsSessionDuration} ${lib.escapeShellArg cfg.awsVaultProfile})"
            while IFS= read -r line; do
              [[ -n "$line" ]] && export "''${line?}"
              [[ "$line" == AWS_CREDENTIAL_EXPIRATION=* ]] && echo "''${line#*=}" > "$state/expires"
            done <<< "$creds"
          ''}
          if ! kubectl --kubeconfig "$kubeconfig" get pods --request-timeout=15s > /dev/null; then
            echo "k8s-mcp: the cluster refused the pinned kubeconfig; not starting" >&2
            exit 1
          fi
          nohup setsid kubernetes-mcp-server \
            --port "$port" --bind-address 127.0.0.1 \
            --read-only --disable-destructive --disable-multi-cluster \
            --toolsets ${lib.escapeShellArg (lib.concatStringsSep "," cfg.toolsets)} \
            --kubeconfig "$kubeconfig" --config ${serverConfig} \
            --log-file "$state/server.log" < /dev/null > /dev/null 2>&1 &
          echo $! > "$state/server.pid"
        )

        for _ in $(seq 40); do
          curl -s -o /dev/null "http://127.0.0.1:$port/mcp" && break
          running server kubernetes-mcp- || { tail -n 20 "$state/server.log" >&2; exit 1; }
          sleep 0.25
        done
        echo "k8s-mcp: server on 127.0.0.1:$port"

        ${lib.optionalString (cfg.forwardTo != null) ''
          nohup setsid ssh -N \
            -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
            -R "127.0.0.1:$port:127.0.0.1:$port" ${lib.escapeShellArg cfg.forwardTo} \
            < /dev/null > "$state/tunnel.log" 2>&1 &
          echo $! > "$state/tunnel.pid"
          sleep 3
          if ! running tunnel ssh; then
            echo "k8s-mcp: tunnel to ${cfg.forwardTo} failed:" >&2
            cat "$state/tunnel.log" >&2
            exit 1
          fi
          echo "k8s-mcp: tunnelled to 127.0.0.1:$port on ${cfg.forwardTo}"
        ''}
        status
      }

      status() {
        if running server kubernetes-mcp-; then echo "server: running"; else echo "server: stopped"; fi
        ${lib.optionalString (cfg.forwardTo != null) ''
          if running tunnel ssh; then echo "tunnel: running"; else echo "tunnel: stopped"; fi
        ''}
        if [[ -f "$kubeconfig" ]]; then
          yq '"context: " + .contexts[0].name + ", namespace: " + .contexts[0].context.namespace + ", acting as: " + (.users[0].user.as // "your own login")' "$kubeconfig"
        fi
        [[ -f "$state/expires" ]] && echo "AWS session expires: $(cat "$state/expires")"
        return 0
      }

      case "''${1:-}" in
        up) up ;;
        down) stop tunnel ssh; stop server kubernetes-mcp- ;;
        status) status ;;
        logs) tail -f "$state/server.log" ;;
        *) echo "usage: k8s-mcp up|down|status|logs" >&2; exit 2 ;;
      esac
    '';
  };
in
{
  options.my.k8sMcp = {
    enable = lib.mkEnableOption "a read-only Kubernetes MCP server, tunnelled to forge";

    context = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "kubeconfig context to serve. null takes the current context at `k8s-mcp up`.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "tile-ai";
      description = ''
        Default namespace in the served kubeconfig. A default, not a limit:
        only `impersonate` and the cluster role behind it keep the server out
        of other namespaces.
      '';
    };

    impersonate = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "system:serviceaccount:tile-ai:claude-view";
      description = ''
        Identity the server acts as, through Kubernetes impersonation. Your own
        login needs the `impersonate` permission. null serves everything your
        login can read, secrets excepted.
      '';
    };

    awsVaultProfile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        aws-vault profile whose session the server runs with, for a kubeconfig
        that calls plain `aws eks get-token`. Leave null when the kubeconfig
        gets its credentials some other way.
      '';
    };

    awsSessionDuration = lib.mkOption {
      type = lib.types.str;
      default = "8h";
      description = "Requested AWS session length. An assumed role may cap it lower, often at 1h.";
    };

    toolsets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      # Not `config`: it shows the kubeconfig to the sandbox.
      default = [ "core" ];
      description = "kubernetes-mcp-server toolsets to expose.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8090;
      description = "Port on this machine's loopback and on forge's.";
    };

    forwardTo = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      # The full name: the router's stale DHCP records answer the short one
      # (docs/nuc-install.md §6).
      default = "forge.taile6c0b.ts.net";
      description = "ssh destination the port is forwarded to. null serves this machine only.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ k8s-mcp ];
  };
}
