# Tile questions from the forge sandbox, through the laptop

`home/tileai-mcp.nix` gives the Claude Code sandbox on forge the tile.ai API on
dev as MCP tools: organizations, collections and their contents, tile search,
tiles and their metadata, templates, tile operations, and registration into a
collection. The server is tile-ai's own (`services/mcp`), taken from the
tile-ai flake input, which follows tile-ai's main at the commit in
`flake.lock`. It runs on the laptop, which is on
the company VPN, and an ssh tunnel puts its port on forge's loopback, the same
way as [k8s-mcp](k8s-mcp.md).

The laptop holds no token. The server takes the caller's token from the
`Authorization` header of every request, so the token lives in the sandbox's
MCP config on forge, and everything the tools do is done as whoever owns that
token.

## One-time setup

1. **Let Nix fetch tile-ai.** The repository is private. Whoever evaluates the
   flake needs a GitHub token with read access to `TileDB-Inc/tile-ai` in its
   nix.conf, and `nrs` evaluates as root:
   ```
   access-tokens = github.com=<token>
   ```
   in `/root/.config/nix/nix.conf` (mode 600), and in `~/.config/nix/nix.conf`
   for `nix flake lock` as yourself.
2. `nrs`.
3. **Make a new API token** in the console on dev (API Tokens page), with the
   organization you want open. The console pins a token to that organization.
   A token made before 2026-10-24 may be pinned to a workspace instead, and
   every call then fails with 403 code 811.
4. **On forge**, in a sandbox session, replace any older `tileai` entry:
   ```sh
   claude mcp remove tileai
   claude mcp add --transport http tileai http://127.0.0.1:8091/mcp \
     --header "Authorization: Bearer <token>"
   ```
   then restart the session.

## Daily

With the VPN on, `tileai-mcp up` starts the server against
`https://api.dev.tile.ai`, sends it one request with no token, and prints the
HTTP code. It wants 401, which means the server is up and refusing callers
without a token. On anything else it stops the server and does not tunnel.
Then it tunnels port 8091 to forge. `tileai-mcp status`, `logs`, `down`.

To move to a newer server (new tools merged on tile-ai's main):
`tileai-mcp down`, `nix flake update tile-ai`, commit `flake.lock`, `nrs`,
`tileai-mcp up`, then reconnect `tileai` with `/mcp` in the forge sandbox.

## Checks after a change

1. `tileai-mcp up` prints the no-token check as 401.
2. `list_my_organizations` returns your organizations.
3. Browsing: `list_organization_collections`, `get_collection`,
   `list_collection_contents`, `list_organization_tiles` with a search term,
   `get_filed_tile`.
4. `get_filed_tile_metadata`, then `update_filed_tile_metadata` with a test
   key, then with `null` to remove it.
5. `get_tile_template` lists a template's operation names.
6. `run_filed_tile_operation` with `sync_metadata` and `query_h5ad`.
7. A very large answer is refused with its size, not cut short.
8. On a test collection: `register_into_collection`,
   `get_collection_registration`, `commit_collection_registration`.
9. A wrong or expired token gets HTTP 401 from the server.

## Limits

- Up only while the laptop is awake, on the VPN, and `up` has been run.
- The token is yours: whatever you may do on dev, the sandbox may do. Revoke
  the token in the console to cut it off.
