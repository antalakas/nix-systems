# Tile questions from the forge sandbox, through the laptop

`home/tileai-mcp.nix` gives the Claude Code sandbox on forge the tile.ai REST
API on dev as MCP tools: list workspaces, teamspaces and tiles, search, read a
tile and its metadata, run tile operations (queries), and update, register and
move tiles. It acts as you, with your API token, which stays on the laptop: the
sandbox only reaches an HTTP endpoint on forge's loopback, the same way as
[k8s-mcp](k8s-mcp.md). The server source is `pkgs/tileai-mcp`.

## What it serves

One tool per OpenAPI operation, generated at `up` from tile-ai's own v1 spec,
so parameters and request bodies follow the checkout. The served set is the
`allowed` list in `pkgs/tileai-mcp/spec.go`:

- **Read:** `get_self_user`, `list_workspaces`, `get_workspace`,
  `list_teamspaces`, `get_teamspace`, `list_tile_templates`,
  `get_tile_template`, `list_tiles`, `get_tiles_in_path`, `search_tiles`,
  `get_tile`, `get_tile_metadata`, `get_tile_properties`, `list_tile_indexes`,
  `get_tile_content` (text up to 200 kB; binary is sized, not shown).
- **Write:** `run_tile_operation` (the server asks for write access when the
  operation mutates), `update_tile`, `update_tile_metadata`,
  `update_tile_properties`, `register_tile`, `move_tiles`.
- **Never:** any DELETE, uploads, users, workspace or teamspace administration.
  An operation not in the list has no tool, and the client refuses DELETE
  outright. `readOnly = true` drops the writes.

Everything it does shows as you in the activity log; the requests carry the
user agent `tileai-mcp/0.1`.

## One-time setup

1. In the console on dev, create an API token, and save it on the laptop:
   ```sh
   install -Dm600 /dev/null ~/.config/tileai-mcp/token
   $EDITOR ~/.config/tileai-mcp/token
   ```
   The server refuses a token file group or others can read.
2. `nrs`.
3. In a sandbox session on forge:
   `claude mcp add --transport http -s user tileai http://127.0.0.1:8091/mcp`,
   then restart the session.

## Daily

`tileai-mcp up` starts the server, checks the token with `/users/self`
(refusing to tunnel on anything but 200), and tunnels port 8091 to forge.
`tileai-mcp status`, `logs`, `down`. Pull tile-ai first when the API changed:
the tools come from the spec in that checkout, and `up` fails naming any
served operation the spec no longer has.

## Limits

- Up only while the laptop is awake and `up` has been run.
- The token is yours: whatever you may do on dev, the sandbox may do through
  these tools, deletes excepted. Revoke the token in the console to cut it off.
- A tile operation's own parameters come from its template; the tool's
  description tells the model to read `get_tile_template` first.
