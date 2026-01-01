# shell-bootstrap

One-command shell setup for WSL Ubuntu, devcontainers, and GitHub Codespaces. Installs and configures a modern, productive terminal environment with 1Password-based secrets management.

## What's Included

| Tool | Purpose |
|------|---------|
| **zsh** | Primary shell with vi-mode |
| **Starship** | Fast, customizable prompt |
| **Atuin** | Searchable shell history with sync |
| **pet** | Snippet manager (Ctrl+S to search) |
| **yazi** | Blazing fast file manager |
| **zoxide** | Smart directory jumping (`z`) |
| **fzf** | Fuzzy finder |
| **ripgrep** | Fast code search (`rg`) |
| **fd** | Fast file finder |
| **bat** | Syntax-highlighted cat |
| **delta** | Better git diffs |
| **glow** | Markdown renderer in terminal |
| **direnv** | Per-directory environments |
| **1Password CLI** | Secrets management (`op`) |
| **GitHub CLI** | GitHub operations (`gh`) |
| **Claude Code** | AI coding assistant |

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/kirderfg/shell-bootstrap/main/install.sh -o /tmp/install.sh
bash /tmp/install.sh
exec zsh
```

> **Note:** Download first, then run. Piping directly to bash (`curl ... | bash`) breaks the interactive credential prompts.

## Manual Install

```bash
git clone https://github.com/kirderfg/shell-bootstrap.git ~/shell-bootstrap
~/shell-bootstrap/install.sh
exec zsh
```

## 1Password Integration

Shell-bootstrap uses 1Password for secrets management. Secrets are fetched on-demand and never stored as plaintext.

### Required 1Password Items (in `DEV_CLI` vault)

| Item | Field | Purpose |
|------|-------|---------|
| `Atuin` | `username`, `password`, `key` | Shell history sync |
| `Pet` | `PAT` | Snippets repo access |
| `GitHub` | `PAT` | GitHub CLI + git credentials |
| `OpenAI` | `api_key` | OpenAI API key (exported) |

### Setup

1. Create a Service Account at: 1Password → Settings → Developer → Service Accounts
2. Grant access to the `DEV_CLI` vault
3. Run the installer - it will prompt for your token

### Non-Interactive Mode (for CI/devcontainers)

```bash
export OP_SERVICE_ACCOUNT_TOKEN="ops_eyJ..."
SHELL_BOOTSTRAP_NONINTERACTIVE=1 bash install.sh
```

Environment variables used in non-interactive mode:
- `OP_SERVICE_ACCOUNT_TOKEN` - 1Password service account token
- `ATUIN_USERNAME`, `ATUIN_PASSWORD`, `ATUIN_KEY` - Atuin credentials
- `GITHUB_TOKEN` - GitHub authentication
- `PET_SNIPPETS_TOKEN` - Pet snippets repo access

## Key Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+R` | Search shell history (Atuin) |
| `Ctrl+S` | Search snippets (pet) |
| `z <dir>` | Jump to directory (zoxide) |
| `zi` | Interactive directory picker |

### Tmux Shortcuts (Ctrl+A = prefix)

| Shortcut | Action |
|----------|--------|
| `dev` | Launch dev session (claude + yazi + shell) |
| `Ctrl+A c` | Create new window |
| `Ctrl+A \|` | Split vertically |
| `Ctrl+A -` | Split horizontally |
| `Ctrl+A h/j/k/l` | Navigate panes (vim-style) |
| `Ctrl+A z` | Toggle pane zoom |
| `Alt+1/2/3/4` | Switch to window 1-4 |
| `Ctrl+A d` | Detach from session |
| `Ctrl+A [` | Scroll/copy mode (q to exit) |
| `Ctrl+A r` | Reload tmux config |

**Dev Session Layout:**
- Window 1 "claude": Claude Code
- Window 2 "shell": Shell
- Window 3 "files": Yazi file manager
- Window 4 "help": Keyboard shortcuts reference

## Aliases

| Alias | Command |
|-------|---------|
| `dev` | Launch tmux dev session |
| `ll` | `ls -lAFh` (long listing, hidden files) |
| `lt` | `ls -lAFht` (sorted by time) |
| `gs` | `git status` |
| `gd` | `git diff` |
| `gds` | `git diff --staged` |
| `gp` | `git pull` |
| `..` | `cd ..` |

## Useful Functions

| Function | Usage |
|----------|-------|
| `take mydir` | Create directory and cd into it |
| `extract file.tar.gz` | Extract any archive format |
| `prev` | Save last command as pet snippet |
| `y` | Yazi file manager (cd on exit) |
| `help` | Show full keyboard shortcuts reference |

## File Locations

| Path | Purpose |
|------|---------|
| `~/.tmux.conf` | Tmux config (Ctrl+A prefix) |
| `~/.config/yazi/` | Yazi file manager config |
| `~/.config/shell-bootstrap/zshrc` | Main zsh config |
| `~/.config/shell-bootstrap/shell-reference.txt` | Shortcuts reference |
| `~/.config/dev_env/op_token` | 1Password service account token |
| `~/.config/dev_env/init.sh` | Shell startup secrets loader |
| `~/.config/starship.toml` | Prompt config |
| `~/.config/atuin/config.toml` | History config |
| `~/.config/pet/snippet.toml` | Saved snippets |
| `~/.claude/settings.json` | Claude Code config |
| `~/CLAUDE.md` | Claude Code tips and tricks |

## Documentation

See [zsh_readme.md](zsh_readme.md) for detailed tips & tricks for all installed tools.

## Requirements

- Ubuntu (WSL, native, or devcontainer)
- Internet connection for initial install
- ~500MB disk space

## Updating

Re-run the installer to update configurations:

```bash
~/shell-bootstrap/install.sh
```

Tools installed via apt will be updated with `apt upgrade`. Binary tools (Starship, delta, etc.) can be updated by removing the binary and re-running the installer.
