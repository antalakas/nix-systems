# Infrastructure/K8s Template

Nix flake for infrastructure projects with AWS, Kubernetes, and Terraform tooling.

## Setup

```bash
# Copy this template to your project
cp -r /etc/nixos/templates/infra-k8s ~/workspace/my-infra-project
cd ~/workspace/my-infra-project

# Customize flake.nix shellHook:
# - Set AWS_PROFILE to your profile name
# - Set kubectx to your k8s context

# Allow direnv
direnv allow

# Initialize git (optional, for local versioning)
git init
```

## Files

- `flake.nix` - Nix devShell with AWS CLI, kubectl, helm, terraform, etc.
- `.envrc` - Auto-loads flake via direnv
- `avx` - aws-vault wrapper script (automatically in PATH)

## Usage

### AWS with MFA (aws-vault)

```bash
# First time: add your AWS base credentials
aws-vault add default  # or your source_profile name

# Use avx for MFA-protected commands
avx                    # opens shell with 8h credentials
avx kubectl get pods   # run single command
avx terraform plan     # run terraform with credentials
```

Credentials last 8 hours (configured in `~/.config/aws-vault/config`).

### Kubernetes

When you `cd` into the project, direnv automatically:
- Switches to your configured k8s context
- Sets `AWS_PROFILE` environment variable

```bash
kubectl get pods       # uses auto-switched context
k9s                   # opens TUI for current context
```

## AWS Config

Your `~/.aws/config` should have:

```ini
[profile default]
region = us-east-1

[profile your-profile-name]
role_arn = arn:aws:iam::123456789012:role/your-role
source_profile = default
region = us-east-1
assume_role_ttl = 8h
```

Match `your-profile-name` with `AWS_PROFILE` in `flake.nix`.
