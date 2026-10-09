# The tile.ai REST API as MCP tools on this machine, tunnelled to forge so the
# Claude Code sandbox there can list, change and query tiles as you. The API
# token never leaves this machine: the sandbox only gets an HTTP endpoint on
# forge's loopback. No DELETE is ever served. Setup and limits:
# docs/tileai-mcp.md.
#
# Run by hand (`tileai-mcp up`), like k8s-mcp, so it is up only when you mean
# it to be.

{ config, pkgs, lib, ... }:

let
  cfg = config.my.tileaiMcp;
  server = pkgs.callPackage ../pkgs/tileai-mcp/package.nix { };

  tileai-mcp = pkgs.writeShellApplication {
    name = "tileai-mcp";
    runtimeInputs = with pkgs; [ openssh curl coreutils procps util-linux jq ];
    text = ''
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/tileai-mcp"
      umask 077
      mkdir -p "$state"
      port=${toString cfg.port}
      token=${lib.escapeShellArg cfg.tokenFile}
      spec=${lib.escapeShellArg cfg.specFile}
      token="''${token/#\~/$HOME}"

      # Kill only what we started: a pid file can outlive its process and the
      # number be reused.
      stop() {
        local name="$1" comm="$2" pid
        [[ -f "$state/$name.pid" ]] || return 0
        pid="$(cat "$state/$name.pid")"
        if [[ "$(ps -p "$pid" -o comm= 2>/dev/null || true)" == "$comm" ]]; then
          kill "$pid"
          echo "tileai-mcp: stopped $name"
        fi
        rm -f "$state/$name.pid"
      }

      running() {
        local name="$1" comm="$2"
        [[ -f "$state/$name.pid" ]] &&
          [[ "$(ps -p "$(cat "$state/$name.pid")" -o comm= 2>/dev/null || true)" == "$comm" ]]
      }

      # Ask the running server who it acts as; the token stays inside it.
      whoami() {
        curl -s --max-time 20 "http://127.0.0.1:$port/mcp" \
          -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
          -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_self_user","arguments":{}}}' |
          jq -r '.result.content[0].text // "no answer"'
      }

      up() {
        stop tunnel ssh
        stop server tileai-mcp
        [[ -f "$token" ]] || { echo "tileai-mcp: no token at $token (docs/tileai-mcp.md)" >&2; exit 1; }
        [[ -f "$spec" ]] || { echo "tileai-mcp: no spec at $spec; pull tile-ai" >&2; exit 1; }

        nohup setsid ${lib.getExe server} \
          -spec "$spec" -base-url ${lib.escapeShellArg cfg.baseUrl} -token-file "$token" \
          -listen "127.0.0.1:$port" ${lib.optionalString cfg.readOnly "-read-only"} \
          < /dev/null > "$state/server.log" 2>&1 &
        echo $! > "$state/server.pid"

        for _ in $(seq 40); do
          curl -s -o /dev/null "http://127.0.0.1:$port/mcp" && break
          running server tileai-mcp || { tail -n 20 "$state/server.log" >&2; exit 1; }
          sleep 0.25
        done

        local self
        self="$(whoami)"
        if [[ "$self" != "HTTP 200"* ]]; then
          echo "tileai-mcp: the API refused or did not answer; not tunnelling:" >&2
          echo "$self" | head -n 5 >&2
          stop server tileai-mcp
          exit 1
        fi
        echo "tileai-mcp: server on 127.0.0.1:$port, acting as $(echo "$self" | tail -n +2 | jq -r '.username // .email // "?"')"

        ${lib.optionalString (cfg.forwardTo != null) ''
          nohup setsid ssh -N \
            -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
            -R "127.0.0.1:$port:127.0.0.1:$port" ${lib.escapeShellArg cfg.forwardTo} \
            < /dev/null > "$state/tunnel.log" 2>&1 &
          echo $! > "$state/tunnel.pid"
          sleep 3
          if ! running tunnel ssh; then
            echo "tileai-mcp: tunnel to ${cfg.forwardTo} failed:" >&2
            cat "$state/tunnel.log" >&2
            exit 1
          fi
          echo "tileai-mcp: tunnelled to 127.0.0.1:$port on ${cfg.forwardTo}"
        ''}
        status
      }

      status() {
        if running server tileai-mcp; then echo "server: running"; else echo "server: stopped"; fi
        ${lib.optionalString (cfg.forwardTo != null) ''
          if running tunnel ssh; then echo "tunnel: running"; else echo "tunnel: stopped"; fi
        ''}
        echo "api: ${cfg.baseUrl}${lib.optionalString cfg.readOnly " (read-only)"}"
        return 0
      }

      case "''${1:-}" in
        up) up ;;
        down) stop tunnel ssh; stop server tileai-mcp ;;
        status) status ;;
        logs) tail -f "$state/server.log" ;;
        *) echo "usage: tileai-mcp up|down|status|logs" >&2; exit 2 ;;
      esac
    '';
  };
in
{
  options.my.tileaiMcp = {
    enable = lib.mkEnableOption "the tile.ai REST API as MCP tools, tunnelled to forge";

    baseUrl = lib.mkOption {
      type = lib.types.str;
      example = "https://api.dev.tile.ai/v1";
      description = "API base URL, including /v1.";
    };

    specFile = lib.mkOption {
      type = lib.types.str;
      description = ''
        tile-ai's v1 OpenAPI spec, read at `up`, so tools follow the checkout:
        services/server/openapi/v1/build/spec/openapi.yaml in a tile-ai clone.
      '';
    };

    tokenFile = lib.mkOption {
      type = lib.types.str;
      default = "~/.config/tileai-mcp/token";
      description = "File holding the API token, mode 600. The server refuses a file others can read.";
    };

    readOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Serve GET operations only.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8091;
      description = "Port on this machine's loopback and on forge's.";
    };

    forwardTo = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "forge.taile6c0b.ts.net";
      description = "ssh destination the port is forwarded to. null serves this machine only.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ tileai-mcp ];
  };
}
