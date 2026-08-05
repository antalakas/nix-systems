#!/usr/bin/env bash
# Create a kind cluster wired to the host's local registry.
#
# Usage: kind-up [cluster-name] [worker-count]
#
# The registry itself is a systemd-managed container (docker-kind-registry
# .service, see modules/k8s-dev.nix) listening on 127.0.0.1:5000. Push to it
# from the host as localhost:5000/foo, and reference the same image inside the
# cluster as localhost:5000/foo — the hosts.toml written below makes containerd
# on each node resolve that name to the registry container over the `kind`
# docker network.

set -euo pipefail

CLUSTER="${1:-dev}"
WORKERS="${2:-0}"
REG_NAME="kind-registry"
REG_PORT="5000"

if [ "$(docker inspect -f '{{.State.Running}}' "$REG_NAME" 2>/dev/null || true)" != "true" ]; then
    echo "Local registry '$REG_NAME' is not running." >&2
    echo "Start it with: sudo systemctl start docker-kind-registry" >&2
    exit 1
fi

# Build the node list: one control-plane plus however many workers were asked
# for. A single-node cluster is the default because it starts in a few seconds.
nodes="- role: control-plane"
for _ in $(seq 1 "$WORKERS"); do
    nodes="$nodes
- role: worker"
done

kind create cluster --name "$CLUSTER" --config=- <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry]
      config_path = "/etc/containerd/certs.d"
nodes:
$nodes
EOF

# Point every node's containerd at the local registry.
REGISTRY_DIR="/etc/containerd/certs.d/localhost:${REG_PORT}"
for node in $(kind get nodes --name "$CLUSTER"); do
    docker exec "$node" mkdir -p "$REGISTRY_DIR"
    docker exec -i "$node" cp /dev/stdin "$REGISTRY_DIR/hosts.toml" <<EOF
[host."http://${REG_NAME}:${REG_PORT}"]
EOF
done

# Put the registry on the cluster's docker network so the nodes can resolve it
# by name. The `kind` network only exists once a cluster has been created, which
# is why this runs after `kind create`.
if [ "$(docker inspect -f '{{json .NetworkSettings.Networks.kind}}' "$REG_NAME")" = "null" ]; then
    docker network connect kind "$REG_NAME"
fi

# Advertise the registry to anything in-cluster that looks for it (Tilt, Skaffold).
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REG_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

echo
echo "Cluster '$CLUSTER' is up. Context: kind-${CLUSTER}"
echo "Push images with:  docker tag myimage localhost:${REG_PORT}/myimage && docker push localhost:${REG_PORT}/myimage"
echo "Tear down with:    kind delete cluster --name $CLUSTER"
