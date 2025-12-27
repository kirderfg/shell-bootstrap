# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Shell-bootstrap is a one-command shell setup for WSL Ubuntu and GitHub Codespaces. The single `install.sh` script installs and configures a complete terminal environment including zsh, Starship prompt, Atuin (history sync), pet (snippets), yazi (file manager), and various CLI tools.

## Architecture

The project consists of:
- `install.sh` - Monolithic installer script (~1300 lines) that handles everything:
  - Package installation via apt and binary downloads from GitHub releases
  - Configuration file generation (written inline as heredocs)
  - Shell integration (wires `.zshrc` and `.bashrc`)
  - Optional sync setup (Atuin history, pet snippets via GitHub)
  - Claude Code configuration with custom status line and startup hooks

Key patterns in `install.sh`:
- `require_cmd()` checks if a command exists before installing
- `append_block_once()` manages idempotent config blocks with markers
- Tools are installed to `~/.local/bin` (not system-wide)
- Configs go to `~/.config/shell-bootstrap/` and tool-specific locations
- Secrets are stored in `~/.config/shell-bootstrap/secrets.env`

## Testing Changes

To test the installer:
```bash
# Run the installer (safe to re-run, idempotent)
./install.sh

# Start new zsh session to test
exec zsh

# Verify tools installed
command -v starship atuin pet yazi zoxide
```

No build step or tests - this is a shell script that's tested by running it.

## Common Modifications

When modifying `install.sh`:
- New apt packages: add to `install_apt_packages()`
- New binary tools: create `install_<tool>()` function following existing patterns (GitHub API for latest release, architecture detection, install to `$BOOTSTRAP_BIN`)
- New zsh config: add to `write_bootstrap_zshrc()` heredoc
- New tool config: create `configure_<tool>()` function
- Call new functions from `main()` at the end

The managed block markers (`# >>> shell-bootstrap (managed) >>>`) ensure re-running the installer updates config cleanly.
