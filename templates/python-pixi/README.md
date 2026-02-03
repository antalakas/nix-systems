# Python Pixi Template

Nix flake + Pixi for Python environment management.

## Setup

```bash
# Copy this template to your project
cp -r /etc/nixos/templates/python-pixi ~/workspace/my-project
cd ~/workspace/my-project

# Allow direnv
direnv allow

# Initialize pixi
pixi init

# Add dependencies
pixi add python numpy pandas
pixi add --pypi langchain chromadb  # PyPI packages

# Run commands
pixi run python script.py
pixi shell  # enter the environment
```

## Files

- `flake.nix` - Nix devShell providing pixi
- `.envrc` - Auto-loads flake via direnv
- `pixi.toml` - Python dependencies (created by `pixi init`)
- `pixi.lock` - Locked versions (commit this!)

## Why Pixi?

- Faster than pip/venv
- Lock file for reproducibility
- Handles Python version
- Conda + PyPI packages
- Cross-platform
