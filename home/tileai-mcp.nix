# tile-ai's MCP server (services/mcp in the tile-ai flake) on this machine,
# tunnelled to forge so the Claude Code sandbox there can list, change and
# query tiles on dev. This side holds no token: the server takes the caller's
# from the Authorization header of every request, so the token lives in the
# sandbox's `claude mcp add`. Setup and checks: docs/tileai-mcp.md.
#
# Run by hand (`tileai-mcp up`), like k8s-mcp, so it is up only when you mean
# it to be.

{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.my.tileaiMcp;
  server = inputs.tile-ai.packages.${pkgs.stdenv.hostPlatform.system}.tileai-mcp;

  tileai-mcp = pkgs.writeShellApplication {
    name = "tileai-mcp";
    runtimeInputs = with pkgs; [ openssh curl coreutils procps util-linux ];
    text = ''
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/tileai-mcp"
      umask 077
      mkdir -p "$state"
      port=${toString cfg.port}

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

      # The server refuses a request with no token; 401 means it is up and
      # guarding. Anything else (000 = no answer) is not.
      no_token_code() {
        curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X POST \
          -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
          -d '{}' "http://127.0.0.1:$port/mcp" || true
      }

      up() {
        stop tunnel ssh
        stop server tileai-mcp

        TILE_API_URL=${lib.escapeShellArg cfg.apiUrl} \
        TILEAI_MCP_HOST=127.0.0.1 \
        TILEAI_MCP_PORT="$port" \
          nohup setsid ${lib.getExe' server "tileai-mcp"} \
          < /dev/null > "$state/server.log" 2>&1 &
        echo $! > "$state/server.pid"

        local code=000
        for _ in $(seq 40); do
          code="$(no_token_code)"
          [[ "$code" != 000 ]] && break
          running server tileai-mcp || { tail -n 20 "$state/server.log" >&2; exit 1; }
          sleep 0.25
        done
        echo "tileai-mcp: server on 127.0.0.1:$port (no-token check: $code, want 401)"
        if [[ "$code" != 401 ]]; then
          echo "tileai-mcp: not refusing a request without a token; not tunnelling" >&2
          tail -n 20 "$state/server.log" >&2
          stop server tileai-mcp
          exit 1
        fi

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
        echo "api: ${cfg.apiUrl}"
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
    enable = lib.mkEnableOption "tile-ai's MCP server, tunnelled to forge";

    apiUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://api.dev.tile.ai";
      description = "tile.ai API the server talks to (TILE_API_URL), without /v1.";
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
