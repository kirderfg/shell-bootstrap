# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Shell-bootstrap is a one-command shell setup for WSL Ubuntu, devcontainers, and GitHub Codespaces. The single `install.sh` script (~1950 lines) installs and configures a complete terminal environment with modern tools and 1Password-based secrets management.

## What Gets Installed

**Package managers:** apt packages, GitHub releases (binary downloads), npm, Go modules

**Tools installed:**
- **Shell:** zsh, tmux, fzf, zoxide, direnv
- **Prompt:** Starship
- **History:** Atuin (sync across machines)
- **Snippets:** pet (Ctrl+S search)
- **Files:** yazi (file manager), fd, ripgrep, bat
- **Git:** delta (diff viewer), GitHub CLI (gh)
- **Secrets:** 1Password CLI (op)
- **AI:** Claude Code CLI
- **Other:** glow (markdown), Go runtime

## Architecture

The project consists of:
- `install.sh` - Monolithic installer script that handles everything:
  - Package installation via apt and binary downloads from GitHub releases
  - Configuration file generation (written inline as heredocs)
  - Shell integration (wires `.zshrc` and `.bashrc`)
  - 1Password integration for secrets (op CLI + service account tokens)
  - GitHub CLI authentication via GITHUB_TOKEN
  - Atuin history sync and pet snippets sync
  - Claude Code configuration with custom status line and startup hooks

Key patterns in `install.sh`:
- `require_cmd()` checks if a command exists before installing
- `append_block_once()` manages idempotent config blocks with markers
- Tools are installed to `~/.local/bin` (not system-wide)
- Configs go to `~/.config/shell-bootstrap/` and tool-specific locations

## Key Directories

| Path | Purpose |
|------|---------|
| `~/.config/shell-bootstrap/` | Main config (zshrc, secrets.env, shell-reference.txt) |
| `~/.config/dev_env/` | 1Password token and secrets loader scripts |
| `~/.local/bin/` | Binary tools (starship, delta, yazi, pet, etc.) |
| `~/.claude/` | Claude Code settings (statusline.sh, startup-tips.sh) |

## Non-Interactive Mode

For CI/devcontainers, set `SHELL_BOOTSTRAP_NONINTERACTIVE=1`:
```bash
SHELL_BOOTSTRAP_NONINTERACTIVE=1 bash install.sh
```

This skips interactive prompts and reads credentials from environment variables:
- `OP_SERVICE_ACCOUNT_TOKEN` - 1Password service account token
- `ATUIN_USERNAME`, `ATUIN_PASSWORD`, `ATUIN_KEY` - Atuin sync
- `GITHUB_TOKEN` - GitHub CLI authentication
- `PET_SNIPPETS_TOKEN` - Pet snippets repo access

## Testing Changes

To test the installer:
```bash
# Run the installer (safe to re-run, idempotent)
./install.sh

# Start new zsh session to test
exec zsh

# Verify tools installed
command -v starship atuin pet yazi zoxide op claude gh
```

No build step or tests - this is a shell script that's tested by running it.

## Common Modifications

When modifying `install.sh`:
- **New apt packages:** add to `install_apt_packages()`
- **New binary tools:** create `install_<tool>()` function (GitHub API for latest release, architecture detection, install to `$BOOTSTRAP_BIN`)
- **New npm tools:** use `npm install -g` pattern
- **New zsh config:** add to `write_bootstrap_zshrc()` heredoc
- **New tool config:** create `configure_<tool>()` function
- **New secrets:** add to `configure_op()` and `op-load-all-secrets()`
- Call new functions from `main()` at the end

## Key Functions

| Function | Purpose |
|----------|---------|
| `install_apt_packages()` | Base Ubuntu packages |
| `install_op()` | 1Password CLI |
| `install_claude_code()` | Claude Code CLI |
| `configure_op()` | 1Password token setup and secrets loading |
| `configure_github()` | GitHub CLI auth via token |
| `configure_atuin()` | Atuin login and sync |
| `configure_claude_code()` | Status line, startup tips, ~/CLAUDE.md |
| `write_bootstrap_zshrc()` | Main zsh configuration |
| `wire_user_shell_rc_files()` | Adds managed blocks to .zshrc/.bashrc |

The managed block markers (`# >>> shell-bootstrap (managed) >>>`) ensure re-running the installer updates config cleanly.
