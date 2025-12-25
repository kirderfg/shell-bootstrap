# shell-bootstrap

One-command shell setup for WSL Ubuntu and GitHub Codespaces. Installs and configures a modern, productive terminal environment.

## What's Included

| Tool | Purpose |
|------|---------|
| **zsh** | Primary shell with sensible defaults |
| **Starship** | Fast, customizable prompt |
| **Atuin** | Searchable shell history with sync |
| **pet** | Snippet manager (Ctrl+S to search) |
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
curl -fsSL https://raw.githubusercontent.com/kirderfg/shell-bootstrap/main/install.sh | bash
exec zsh
```

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

## Aliases

| Alias | Command |
|-------|---------|
| `ll` | `ls -lAFh` (long listing, hidden files) |
| `lt` | `ls -lAFht` (sorted by time) |
| `gs` | `git status` |
| `gd` | `git diff` |
| `..` | `cd ..` |

## Useful Functions

| Function | Usage |
|----------|-------|
| `take mydir` | Create directory and cd into it |
| `extract file.tar.gz` | Extract any archive format |
| `prev` | Save last command as pet snippet |

## File Locations

| Path | Purpose |
|------|---------|
| `~/.config/shell-bootstrap/zshrc` | Main zsh config |
| `~/.config/shell-bootstrap/secrets.env` | Sync credentials |
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
