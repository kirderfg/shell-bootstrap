# Zsh bootstrap (Starship + Atuin + pet) — WSL + Codespaces

This repo provides a single bootstrap script intended for:
- WSL Ubuntu
- GitHub Codespaces (Ubuntu images)

It installs:
- zsh as primary interactive shell
- Starship prompt
- Atuin (global, searchable history + optional encrypted sync)
- pet (snippet manager) with Ctrl-S search binding in zsh
- Useful CLI tools: fzf, ripgrep, fd, bat, jq, zoxide, direnv, delta, tmux, gh
- Claude Code CLI

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/<YOUR_GH_USER>/shell-bootstrap/main/install.sh | bash
```

Or clone and run:
```bash
git clone https://github.com/<YOUR_GH_USER>/shell-bootstrap.git ~/shell-bootstrap
~/shell-bootstrap/install.sh
exec zsh
```

---

## Tips & Tricks

### Atuin (Shell History)

Atuin replaces your shell history with a searchable, syncable database.

| Shortcut | Action |
|----------|--------|
| `Ctrl+R` | Search history (fuzzy) |
| `Up/Down` | Navigate results |
| `Enter` | Execute selected command |
| `Tab` | Insert command to edit first |
| `Ctrl+D` | Delete entry from history |

**Useful commands:**
```bash
atuin search <query>       # Search history
atuin stats                # Show history statistics
atuin sync                 # Sync history with server
atuin key                  # Show your encryption key (for new machines)
atuin login -u USER        # Login to sync service
atuin logout               # Logout from sync
```

**Pro tips:**
- Prefix command with a space to exclude from history (requires `HIST_IGNORE_SPACE`)
- Use `atuin search --exit 0` to only show successful commands
- Filter by directory: `atuin search --cwd .`

---

### Pet (Snippet Manager)

Pet stores and retrieves shell snippets/commands you use frequently.

| Shortcut | Action |
|----------|--------|
| `Ctrl+S` | Search snippets (inline insert) |

**Useful commands:**
```bash
pet new                    # Add new snippet interactively
pet new "command here"     # Add specific command as snippet
pet list                   # List all snippets
pet search                 # Search snippets with fzf
pet edit                   # Edit snippets file
pet sync                   # Sync with gist (if configured)
prev                       # Save previous command as snippet (custom function)
```

**Pro tips:**
- Use `<param=default>` in snippets for parameterized commands
- Example: `curl -X GET https://api.example.com/<endpoint=users>`
- Organize with tags in the description field

---

### Zoxide (Smart cd)

Zoxide learns your most-used directories and lets you jump to them quickly.

| Command | Action |
|---------|--------|
| `z foo` | Jump to most frecent dir matching "foo" |
| `z foo bar` | Jump to dir matching "foo" and "bar" |
| `zi` | Interactive selection with fzf |
| `z -` | Jump to previous directory |

**Useful commands:**
```bash
zoxide query foo           # Show what z would match
zoxide query -l            # List all tracked directories
zoxide add /path           # Manually add a path
zoxide remove /path        # Remove a path from database
```

**Pro tips:**
- Just type partial directory names: `z proj` might match `~/projects/myproject`
- The more you use a directory, the higher it ranks

---

### Fzf (Fuzzy Finder)

Fzf is integrated into many tools for interactive selection.

| Shortcut | Action |
|----------|--------|
| `Ctrl+T` | Find files in current directory |
| `Ctrl+R` | Search history (if not using Atuin) |
| `Alt+C` | cd into selected directory |

**Pro tips:**
- Pipe anything to fzf: `cat file | fzf`
- Preview files: `fzf --preview 'bat --color=always {}'`
- Multi-select with `Tab`: `fzf -m`

---

### Ripgrep (rg) - Fast Search

```bash
rg pattern                 # Search current dir recursively
rg pattern -t py           # Search only Python files
rg pattern -g '*.js'       # Search matching glob
rg pattern -i              # Case insensitive
rg pattern -l              # Only show filenames
rg pattern -C 3            # Show 3 lines of context
rg pattern --hidden        # Include hidden files
rg -F 'literal string'     # Fixed string (no regex)
```

---

### Fd - Fast Find

```bash
fd pattern                 # Find files matching pattern
fd -e py                   # Find by extension
fd -t d                    # Find directories only
fd -t f                    # Find files only
fd -H                      # Include hidden files
fd pattern -x cmd          # Execute command on each result
```

---

### Bat - Better Cat

```bash
bat file                   # View file with syntax highlighting
bat -l json file           # Force language
bat -A file                # Show non-printable characters
bat --diff file            # Show git diff
bat -r 10:20 file          # Show lines 10-20
```

**Note:** On Ubuntu, use `batcat` or the alias `bat` we set up.

---

### Delta - Better Git Diff

Delta is configured as the default git pager. Features:
- Syntax highlighting in diffs
- Line numbers
- Side-by-side view available

```bash
git diff                   # Uses delta automatically
delta file1 file2          # Compare two files directly
```

---

### Direnv - Directory Environments

Direnv auto-loads `.envrc` files when entering directories.

```bash
direnv allow               # Trust current .envrc
direnv deny                # Untrust current .envrc
direnv edit                # Edit .envrc and auto-allow
```

**Example `.envrc`:**
```bash
export DATABASE_URL="postgres://localhost/mydb"
export AWS_PROFILE="dev"
PATH_add bin               # Add ./bin to PATH
```

---

### Starship Prompt

Starship shows git status, language versions, and more.

**Customize:** Edit `~/.config/starship.toml`

```toml
# Example customizations
[character]
success_symbol = "[➜](bold green)"
error_symbol = "[✗](bold red)"

[directory]
truncation_length = 5
```

---

### Shell Aliases Quick Reference

| Alias | Command |
|-------|---------|
| `ll` / `la` | `ls -lAFh` (long, hidden, human sizes) |
| `lt` | `ls -lAFht` (sorted by time) |
| `lS` | `ls -lAFhS` (sorted by size) |
| `..` | `cd ..` |
| `...` | `cd ../..` |
| `gs` | `git status` |
| `gd` | `git diff` |
| `gds` | `git diff --staged` |
| `gl` | `git log --oneline -20` |
| `gp` | `git pull` |
| `dps` | `docker ps` |
| `py` | `python3` |

---

### Utility Functions

| Function | Usage |
|----------|-------|
| `take dir` | Create directory and cd into it |
| `extract file` | Extract any archive (tar, zip, gz, etc.) |
| `ff pattern` | Find files by name |
| `fd_dir pattern` | Find directories by name |
| `path` | Show PATH entries, one per line |
| `prev` | Save previous command as pet snippet |

---

### Zsh Features

These options are enabled:
- **AUTO_CD**: Type directory name to cd (no `cd` needed)
- **CORRECT**: Suggests corrections for typos
- **EXTENDED_GLOB**: Advanced globbing patterns

**Useful zsh shortcuts:**
| Shortcut | Action |
|----------|--------|
| `Ctrl+A` | Beginning of line |
| `Ctrl+E` | End of line |
| `Ctrl+U` | Delete to beginning |
| `Ctrl+K` | Delete to end |
| `Ctrl+W` | Delete word backward |
| `Alt+B` | Move word backward |
| `Alt+F` | Move word forward |
| `Ctrl+L` | Clear screen |

---

## Secrets Configuration

For Atuin sync and pet snippets sync, create `~/.config/shell-bootstrap/secrets.env`:

```bash
# Atuin sync
export ATUIN_PASSWORD="your_password"
export ATUIN_KEY="your_encryption_key"  # Get with: atuin key

# Pet snippets (GitHub PAT)
export PET_SNIPPETS_TOKEN="ghp_xxxxx"
```

Then re-run `install.sh` to apply.

---

## Claude Code

Claude Code is installed and configured automatically with a custom status line.

### Status Line

The status line shows:
- **Model name** - Which Claude model is active
- **Git branch** - Current branch with `*` if there are uncommitted changes
- **Cost** - Running session cost (when > $0.001)
- **Context usage** - Percentage of context window used

Example: `[Opus] | main* | $0.042 | ctx:15%`

### Quick Commands

| Command | Action |
|---------|--------|
| `/help` | Show all slash commands |
| `/model` | Switch models (opus, sonnet, haiku) |
| `/compact` | Compress conversation to save context |
| `/clear` | Clear conversation history |
| `/cost` | Show session costs |
| `/doctor` | Diagnose setup issues |
| `/vim` | Enable vim keybindings |

### Usage Examples

```bash
claude                     # Start interactive session
claude "your prompt"       # One-shot query
claude -p "prompt" file.py # Include file in prompt

# Pipe input
claude "explain this error" < error.log
claude "review this diff" < <(git diff)
claude "write commit msg" < <(git diff --staged)

# Continue previous session
claude -c                  # Continue last session
claude -r                  # Resume with history
```

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+C` | Cancel current operation |
| `Ctrl+D` | Exit Claude Code |
| `Escape` (2x) | Interrupt generation |
| `Tab` | Accept autocomplete |

### Pro Tips

- **Include files**: Use `@file.txt` in your prompt to include file contents
- **Include folders**: Use `@folder/` to include directory structure
- **Shell commands**: Prefix with `!` to run shell: `! git status`
- **Cheaper tasks**: Use `/model haiku` for simple tasks
- **Save context**: Use `/compact` when context gets large

### Configuration

- Settings: `~/.claude/settings.json`
- Status line script: `~/.claude/statusline.sh`
- Tips file: `~/CLAUDE.md`

See `~/CLAUDE.md` for more tips after installation.

---

## Troubleshooting

**Atuin not syncing:**
```bash
atuin status               # Check sync status
atuin sync -f              # Force sync
```

**Pet snippets not loading:**
- Check `~/.config/pet/snippet.toml` exists
- Verify token in secrets.env if using private repo

**Zoxide not jumping correctly:**
```bash
zoxide query -l            # See what's indexed
z --help                   # Check available options
```

**Delta not showing colors:**
```bash
git config --global core.pager delta
```
