# The tile.ai REST API as MCP tools, generated from the API's own OpenAPI
# spec. Source here because it is a personal tool, not tile-ai code.
{ lib, buildGoModule }:

buildGoModule {
  pname = "tileai-mcp";
  version = "0.1.0";
  src = lib.cleanSource ./.;
  vendorHash = "sha256-O+25wICSpJL20PZ6Iq9XETLRXZ1tWeZgw/eGNRP/aM4=";
  meta.mainProgram = "tileai-mcp";
}
