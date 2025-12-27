# shell-bootstrap

One-command shell setup for WSL Ubuntu and GitHub Codespaces. Installs and configures a modern, productive terminal environment.

## What's Included

| Tool | Purpose |
|------|---------|
| **Kitty** | GPU-accelerated terminal with splits |
| **zsh** | Primary shell with sensible defaults |
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
| **direnv** | Per-directory environments |
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

## Post-Install Setup (Optional)

### Enable History Sync (Atuin)

1. Get your encryption key from an existing machine:
   ```bash
   atuin key
   ```

2. Edit secrets file:
   ```bash
   nano ~/.config/shell-bootstrap/secrets.env
   ```

3. Add your credentials:
   ```bash
   export ATUIN_PASSWORD="your_password"
   export ATUIN_KEY="your_encryption_key"
   ```

4. Re-run installer:
   ```bash
   ~/shell-bootstrap/install.sh
   ```

### Enable Snippet Sync (Pet)

1. Create a GitHub Personal Access Token at https://github.com/settings/tokens

2. Add to secrets file:
   ```bash
   export PET_SNIPPETS_TOKEN="ghp_your_token"
   ```

3. Re-run installer

## Key Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+R` | Search shell history (Atuin) |
| `Ctrl+S` | Search snippets (pet) |
| `z <dir>` | Jump to directory (zoxide) |
| `zi` | Interactive directory picker |

### Kitty Terminal Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+\` | Vertical split |
| `Ctrl+Shift+-` | Horizontal split |
| `Ctrl+Shift+H/J/K/L` | Navigate splits |
| `Ctrl+Alt+H/J/K/L` | Resize splits |
| `Ctrl+Shift+Z` | Toggle fullscreen (stack) |
| `Ctrl+Shift+E` | Open file manager (yazi) |
| `Ctrl+Shift+T` | New tab |
| `Ctrl+Alt+1-5` | Switch to tab 1-5 |

### Tmux Shortcuts (Ctrl+A = prefix)

| Shortcut | Action |
|----------|--------|
| `dev` | Launch dev session (Claude + yazi + shell) |
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
- Window 1 "workspace": Claude (2/3 left) | yazi (top right) + shell (bottom right)
- Window 2 "reference": Keyboard shortcuts reference card

## Aliases

| Alias | Command |
|-------|---------|
| `dev` | Launch tmux dev session |
| `ll` | `ls -lAFh` (long listing, hidden files) |
| `lt` | `ls -lAFht` (sorted by time) |
| `gs` | `git status` |
| `gd` | `git diff` |
| `..` | `cd ..` |
| `kdev` | Launch kitty with dev layout |
| `icat` | Display images in kitty |

## Useful Functions

| Function | Usage |
|----------|-------|
| `take mydir` | Create directory and cd into it |
| `extract file.tar.gz` | Extract any archive format |
| `prev` | Save last command as pet snippet |
| `y` | Yazi file manager (cd on exit) |

## File Locations

| Path | Purpose |
|------|---------|
| `~/.tmux.conf` | Tmux config (Ctrl+A prefix) |
| `~/.config/kitty/kitty.conf` | Kitty terminal config |
| `~/.config/kitty/dev.session` | Dev layout session |
| `~/.config/yazi/` | Yazi file manager config |
| `~/.config/shell-bootstrap/zshrc` | Main zsh config |
| `~/.config/shell-bootstrap/secrets.env` | Sync credentials |
| `~/.config/shell-bootstrap/shell-reference.txt` | Shortcuts reference |
| `~/.config/starship.toml` | Prompt config |
| `~/.config/atuin/config.toml` | History config |
| `~/.config/pet/snippet.toml` | Saved snippets |
| `~/.claude/settings.json` | Claude Code config |

## Documentation

See [zsh_readme.md](zsh_readme.md) for detailed tips & tricks for all installed tools.

## Requirements

- Ubuntu (WSL or native) or GitHub Codespaces
- Internet connection for initial install
- ~500MB disk space

## Updating

Re-run the installer to update configurations:

```bash
~/shell-bootstrap/install.sh
```

Tools installed via apt will be updated with `apt upgrade`. Binary tools (Starship, delta, etc.) can be updated by removing the binary and re-running the installer.
