{ config, pkgs, lib, ... }:

{
  # WireGuard VPN connection for NetworkManager
  # Using activation script to place file in system-connections directory
  #
  # IMPORTANT: Replace placeholders with real values locally!
  # This file uses git skip-worktree to hide local changes.
  # To edit: git update-index --no-skip-worktree wireguard-secrets.nix
  # After edit: git update-index --skip-worktree wireguard-secrets.nix
  #
  system.activationScripts.wireguard-nm = ''
    mkdir -p /etc/NetworkManager/system-connections
    cat > /etc/NetworkManager/system-connections/tiledb-wg.nmconnection << 'EOF'
[connection]
id=tiledb-wg
type=wireguard
autoconnect=false
interface-name=tiledb-wg

[wireguard]
private-key=REPLACE_WITH_YOUR_PRIVATE_KEY

[wireguard-peer.REPLACE_WITH_PEER_PUBLIC_KEY]
endpoint=wg-prod.tiledb.io:51820
allowed-ips=10.0.0.0/8
persistent-keepalive=15

[ipv4]
address1=10.100.0.4/32
dns=10.20.0.2
method=manual

[ipv6]
addr-gen-mode=default
method=disabled
EOF
    chmod 600 /etc/NetworkManager/system-connections/tiledb-wg.nmconnection
    chown root:root /etc/NetworkManager/system-connections/tiledb-wg.nmconnection
  '';
}
