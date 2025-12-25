# Zsh bootstrap (Starship + Atuin + pet) — WSL + Codespaces

This repo provides a single bootstrap script intended for:
- WSL Ubuntu
- GitHub Codespaces (Ubuntu images)

It installs:
- zsh as primary interactive shell
- Starship prompt
- Atuin (global, searchable history + optional encrypted sync)
- pet (snippet manager) with Ctrl-S search binding in zsh
- Useful CLI tools: fzf, ripgrep, fd, bat, jq, yq (if available), zoxide, direnv, delta, tmux, gh (if available)
- Claude Code

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/<YOUR_GH_USER>/shell-bootstrap/main/install.sh | bash
