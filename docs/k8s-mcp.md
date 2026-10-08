# Cluster questions from the forge sandbox, through the laptop

The laptop can reach the tile-ai clusters; the Claude Code sandbox on forge
cannot, because the personal AWS user is MFA-gated
([sandbox-aws-scoped-identity.md](sandbox-aws-scoped-identity.md)).
`home/k8s-mcp.nix` bridges the two without moving a credential: a read-only
[kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server)
runs on the laptop, and an ssh tunnel puts its port on forge's loopback, where
the sandbox (host network) reaches it.

It is the cheap alternative to the scoped IAM user: nothing new in AWS, but it
only works while the laptop is up and its AWS session lasts.

## What the sandbox can and cannot do

- **Can:** list and get pods and other resources, read pod logs, events, node
  and pod metrics.
- **Cannot:** change anything (`--read-only` exposes only read tools), read
  Secrets (refused by the server's config, whatever the identity allows), or
  see the kubeconfig (the `config` toolset is off).
- **Namespaces:** with `impersonate` set, only what that account's role allows.
  Without it, everything your own login can read.

Checked end to end on 2026-10-08 against a kind cluster: logs and events in
`tile-ai` returned, another namespace and a Secret refused, the server bound to
127.0.0.1 only. The tunnel itself was not exercised there.

## One-time setup

1. **Cluster side, in tiledb-infra** (it names a cluster, so it does not belong
   here). A view-only service account in the namespace, and permission for your
   own identity to act as it if you are not already a cluster admin:

   ```sh
   kubectl -n tileai create serviceaccount claude-view
   kubectl -n tileai create rolebinding claude-view --clusterrole=view --serviceaccount=tileai:claude-view
   ```

   The built-in `view` role reads pods, logs, events and deployments, never
   Secrets.

2. **Laptop**, in `hosts/nixos/home.nix`:

   ```nix
   my.k8sMcp = {
     enable = true;
     impersonate = "system:serviceaccount:tileai:claude-view";
     # context = "...";          # default: kubectl's current context at `up`
     # awsVaultProfile = "...";  # see "Where the AWS session comes from"
   };
   ```

3. **Sandbox on forge**, once per profile. It lands in the profile's
   `.claude.json`, which the sandbox mounts, so it survives restarts:

   ```sh
   claude mcp add --transport http -s user k8s http://127.0.0.1:8090/mcp
   ```

## Where the AWS session comes from

The personal user's `EnforceMFA` deny means the kubeconfig's `aws eks
get-token --role ...` only works from an MFA session. Two ways to give the
server one:

- **Inherit it (default).** Do the MFA step (`avx` in tiledb-infra's app-qa
  shell, an `aws-vault exec` subshell), check `kubectl get pods` works there,
  and run `k8s-mcp up` from that same shell. The server keeps that session's
  keys, so it lasts as long as the session does.
- **aws-vault.** Set `awsVaultProfile` to the profile that shell uses;
  `k8s-mcp up` then asks for the code itself. With aws-vault's ykman prompt,
  set `ykmanOathCredential` to the YubiKey account's name (`ykman oath
  accounts list`) unless it is the full MFA ARN. Check first that
  `aws-vault exec <profile> -- kubectl get pods` works.

`k8s-mcp status` shows the expiry when aws-vault set it.

## Daily use

On the laptop:

```sh
k8s-mcp up       # from the MFA shell, or prompts via awsVaultProfile; then server + tunnel
k8s-mcp status   # what runs, which context and identity, when AWS expires
k8s-mcp logs     # server log
k8s-mcp down
```

`up` again restarts both, which is how an expired session is renewed.

## Limits

- **Laptop asleep or tunnel dropped:** the sandbox's k8s tools fail until
  `k8s-mcp up`.
- **Session length:** `awsSessionDuration` asks for 8h; an assumed role may cap
  it at 1h.
- **Every sandbox on forge sees the port**, whatever its profile: they all share
  forge's network. The view-only identity is what makes that acceptable, so set
  `impersonate` before leaving it running.
- **The server binary is pinned** to upstream's release (not in nixpkgs as of
  2026-10-08); bump `version` and `hash` together.
