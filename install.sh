#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

log() { printf '%s\n' "shell-bootstrap: $*"; }

require_cmd() { command -v "$1" >/dev/null 2>&1; }

SUDO="sudo"
if ! require_cmd sudo; then
  SUDO=""
fi

DEFAULT_ATUIN_USERNAME="kirderfg"
DEFAULT_ATUIN_EMAIL="fredrik@thegustavssons.se"
DEFAULT_PET_SNIPPETS_REPO="https://github.com/kirderfg/shell-snippets-private"

BOOTSTRAP_HOME="${HOME}/.config/shell-bootstrap"
BOOTSTRAP_SHARE="${HOME}/.local/share/shell-bootstrap"
BOOTSTRAP_BIN="${HOME}/.local/bin"
ZSH_PLUGINS_DIR="${HOME}/.local/share/zsh-plugins"

mkdir -p "${BOOTSTRAP_HOME}" "${BOOTSTRAP_SHARE}" "${BOOTSTRAP_BIN}" "${ZSH_PLUGINS_DIR}"

# Optional local secrets file (recommended for WSL)
if [[ -f "${BOOTSTRAP_HOME}/secrets.env" ]]; then
  # shellcheck disable=SC1090
  source "${BOOTSTRAP_HOME}/secrets.env"
fi

ATUIN_USERNAME="${ATUIN_USERNAME:-$DEFAULT_ATUIN_USERNAME}"
ATUIN_EMAIL="${ATUIN_EMAIL:-$DEFAULT_ATUIN_EMAIL}"
PET_SNIPPETS_REPO="${PET_SNIPPETS_REPO:-$DEFAULT_PET_SNIPPETS_REPO}"

append_block_once() {
  local file="$1"
  local marker_begin="$2"
  local marker_end="$3"
  local content="$4"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -qF "$marker_begin" "$file"; then
    # Remove existing managed block, then re-add
    local tmpfile
    tmpfile="$(mktemp)"
    awk -v begin="$marker_begin" -v end="$marker_end" '
      $0 == begin { skip=1; next }
      $0 == end { skip=0; next }
      !skip { print }
    ' "$file" > "$tmpfile"
    mv "$tmpfile" "$file"
  fi

  {
    echo ""
    echo "$marker_begin"
    echo "$content"
    echo "$marker_end"
  } >>"$file"
}

install_apt_packages() {
  log "Installing base packages via apt..."
  ${SUDO} apt-get update -y

  ${SUDO} apt-get install -y \
    ca-certificates curl git unzip zip \
    build-essential pkg-config make gawk \
    zsh tmux fzf \
    ripgrep fd-find bat jq \
    direnv zoxide \
    fonts-firacode fonts-powerline

  # Optional (nice-to-have) packages; don't hard-fail if not present in the image
  ${SUDO} apt-get install -y gh || true
}

install_delta() {
  if require_cmd delta; then
    log "delta already installed."
    return
  fi
  log "Installing delta (git-delta) from GitHub releases..."
  local arch tag asset url tmpdir
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) log "Unsupported arch for delta: $arch"; return ;;
  esac

  tag="$(curl -fsSL https://api.github.com/repos/dandavison/delta/releases/latest | jq -r .tag_name)"
  asset="delta-${tag}-${arch}-unknown-linux-gnu.tar.gz"
  url="https://github.com/dandavison/delta/releases/download/${tag}/${asset}"

  tmpdir="$(mktemp -d)"
  curl -fsSL "$url" -o "${tmpdir}/delta.tgz"
  tar -xzf "${tmpdir}/delta.tgz" -C "${tmpdir}"
  install -m 0755 "${tmpdir}/delta-${tag}-${arch}-unknown-linux-gnu/delta" "${BOOTSTRAP_BIN}/delta"
  rm -rf "${tmpdir}"
}

install_atuin() {
  if require_cmd atuin; then
    log "Atuin already installed."
    return
  fi
  log "Installing Atuin..."
  curl -fsSL https://setup.atuin.sh | bash
}

install_claude_code() {
  if require_cmd claude; then
    log "Claude Code already installed."
    return
  fi
  log "Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
}

configure_claude_code() {
  log "Configuring Claude Code..."

  local claude_dir="${HOME}/.claude"
  local settings_file="${claude_dir}/settings.json"
  local statusline_script="${claude_dir}/statusline.sh"
  local startup_script="${claude_dir}/startup-tips.sh"

  mkdir -p "${claude_dir}"

  # Create status line script with git info, cost tracking, and context usage
  cat > "${statusline_script}" <<'STATUSLINE_EOF'
#!/bin/bash
# Claude Code Status Line - shell-bootstrap
# Shows: model, git branch, cost, context usage

input=$(cat)

# Parse JSON input
MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
INPUT_TOKENS=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')

# Format cost (show if > $0.001)
COST_STR=""
if (( $(echo "$COST > 0.001" | bc -l 2>/dev/null || echo 0) )); then
  COST_STR=" | \$$(printf '%.3f' "$COST")"
fi

# Context usage percentage
if [[ "$CONTEXT_SIZE" -gt 0 && "$INPUT_TOKENS" -gt 0 ]]; then
  PCT=$(( INPUT_TOKENS * 100 / CONTEXT_SIZE ))
  CTX_STR=" | ctx:${PCT}%"
else
  CTX_STR=""
fi

# Git branch (if in a repo)
GIT_STR=""
if git rev-parse --git-dir > /dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null)
  if [[ -n "$BRANCH" ]]; then
    # Check for uncommitted changes
    if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
      GIT_STR=" | ${BRANCH}*"
    else
      GIT_STR=" | ${BRANCH}"
    fi
  fi
fi

# Assemble status line
echo "[${MODEL}]${GIT_STR}${COST_STR}${CTX_STR}"
STATUSLINE_EOF

  chmod +x "${statusline_script}"

  # Create startup tips script that shows a random tip
  cat > "${startup_script}" <<'STARTUP_EOF'
#!/bin/bash
# Claude Code Startup Tips - shell-bootstrap
# Shows a random tip when Claude starts

TIPS=(
  "Use @file.txt to include file contents in your prompt"
  "Use /compact to save context when conversations get long"
  "Use /model haiku for simple tasks (cheaper & faster)"
  "Press Escape twice to interrupt generation"
  "Use @folder/ to include directory structure"
  "Prefix with ! to run shell commands: ! git status"
  "Use /cost to check your session spending"
  "Use Ctrl+C to cancel, Ctrl+D to exit"
  "Pipe input: claude 'explain this' < error.log"
  "Use /clear to reset conversation (loses history)"
  "Use /doctor to diagnose setup issues"
  "Review diffs: claude 'review this' < <(git diff)"
  "Generate commits: claude 'write commit msg' < <(git diff --staged)"
  "Use /vim for vim-style keybindings"
  "See ~/CLAUDE.md for more tips and tricks"
)

# Pick a random tip
TIP="${TIPS[$RANDOM % ${#TIPS[@]}]}"

# Print with formatting
echo ""
echo -e "\033[1;36m╭─────────────────────────────────────────────────────────────╮\033[0m"
echo -e "\033[1;36m│\033[0m \033[1;33m💡 Tip:\033[0m ${TIP}"
echo -e "\033[1;36m╰─────────────────────────────────────────────────────────────╯\033[0m"
echo ""
STARTUP_EOF

  chmod +x "${startup_script}"

  # Create settings.json with statusLine and startup hook
  cat > "${settings_file}" <<SETTINGS_EOF
{
  "statusLine": {
    "type": "command",
    "command": "${statusline_script}",
    "padding": 0
  },
  "hooks": {
    "PostStart": [
      {
        "type": "command",
        "command": "${startup_script}"
      }
    ]
  }
}
SETTINGS_EOF

  # Create CLAUDE.md tips file in home directory
  local tips_file="${HOME}/CLAUDE.md"
  cat > "${tips_file}" <<'TIPS_EOF'
# Claude Code Tips & Tricks

## Quick Commands
| Command | Action |
|---------|--------|
| `/help` | Show all slash commands |
| `/model` | Switch models (opus, sonnet, haiku) |
| `/compact` | Compress conversation context |
| `/clear` | Clear conversation history |
| `/cost` | Show session costs |
| `/doctor` | Diagnose setup issues |
| `/vim` | Enable vim keybindings |

## Keyboard Shortcuts
| Shortcut | Action |
|----------|--------|
| `Ctrl+C` | Cancel current operation |
| `Ctrl+D` | Exit Claude Code |
| `Escape` (2x) | Interrupt generation |
| `Tab` | Accept autocomplete |

## Include Files in Prompts
- `@file.txt` - Include file contents
- `@folder/` - Include directory structure
- `! command` - Run shell command inline

## Useful Patterns
```bash
# Quick one-liner
claude "explain this error" < error.log

# Code review
claude "review this diff for issues" < <(git diff)

# Generate commit message
claude "write a commit message" < <(git diff --staged)

# Explain a file
claude "explain what this does" < script.sh

# Continue last session
claude -c
```

## Cost Awareness
| Model | Best For | Cost |
|-------|----------|------|
| Haiku | Simple tasks, quick answers | $ |
| Sonnet | Balanced capability | $$ |
| Opus | Complex reasoning | $$$ |

Use `/compact` when context gets large to reduce token usage.

## Context Management Tips
- Large files consume context quickly
- Reference specific files instead of whole directories
- `/clear` resets but loses conversation history
- `/compact` preserves key info while reducing tokens
- Watch the ctx:% in your status line

## Pro Tips
- Run `claude --dangerously-skip-permissions` for unattended scripts
- Use `/init` to create a CLAUDE.md for your project
- Check `/config` for all available settings
TIPS_EOF
  log "Created ~/CLAUDE.md with tips and tricks"
}

install_starship() {
  if require_cmd starship; then
    log "Starship already installed."
    return
  fi

  log "Installing Starship (latest release) to ${BOOTSTRAP_BIN}..."
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *)
      log "Unsupported arch for Starship auto-install: $(uname -m)."
      log "You can install manually from https://starship.rs/"
      return
      ;;
  esac

  local tag asset url tmpdir
  tag="$(curl -fsSL https://api.github.com/repos/starship/starship/releases/latest | jq -r .tag_name)"
  asset="starship-${arch}-unknown-linux-gnu.tar.gz"
  url="https://github.com/starship/starship/releases/download/${tag}/${asset}"

  tmpdir="$(mktemp -d)"
  curl -fsSL "$url" -o "${tmpdir}/starship.tgz"
  tar -xzf "${tmpdir}/starship.tgz" -C "${tmpdir}"
  install -m 0755 "${tmpdir}/starship" "${BOOTSTRAP_BIN}/starship"
  rm -rf "${tmpdir}"
}

install_go() {
  local required_major=1
  local required_minor=21

  if require_cmd go; then
    local version
    version="$(go version | grep -oP 'go\K[0-9]+\.[0-9]+')"
    local major minor
    major="${version%%.*}"
    minor="${version#*.}"
    if (( major > required_major || (major == required_major && minor >= required_minor) )); then
      log "Go ${version} already installed (>= ${required_major}.${required_minor})."
      return
    fi
    log "Go ${version} too old, need >= ${required_major}.${required_minor}. Installing newer version..."
  else
    log "Go not found. Installing..."
  fi

  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) log "Unsupported arch for Go: $arch"; return 1 ;;
  esac

  local go_version="1.23.4"
  local tarball="go${go_version}.linux-${arch}.tar.gz"
  local url="https://go.dev/dl/${tarball}"
  local go_install_dir="${HOME}/.local/go"

  log "Downloading Go ${go_version}..."
  local tmpdir
  tmpdir="$(mktemp -d)"
  curl -fsSL "$url" -o "${tmpdir}/${tarball}"

  rm -rf "${go_install_dir}"
  mkdir -p "${go_install_dir}"
  tar -xzf "${tmpdir}/${tarball}" -C "${go_install_dir}" --strip-components=1
  rm -rf "${tmpdir}"

  export PATH="${go_install_dir}/bin:${PATH}"
  log "Go ${go_version} installed to ${go_install_dir}."
}

install_pet() {
  if require_cmd pet; then
    log "pet already installed."
    return
  fi
  log "Installing pet..."
  install_go
  export PATH="${HOME}/.local/go/bin:${PATH}"
  GOBIN="${BOOTSTRAP_BIN}" go install github.com/knqyf263/pet@latest
}

install_zsh_plugins() {
  log "Installing zsh plugins (autosuggestions + syntax-highlighting)..."

  if [[ ! -d "${ZSH_PLUGINS_DIR}/zsh-autosuggestions" ]]; then
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "${ZSH_PLUGINS_DIR}/zsh-autosuggestions"
  fi

  if [[ ! -d "${ZSH_PLUGINS_DIR}/zsh-syntax-highlighting" ]]; then
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_PLUGINS_DIR}/zsh-syntax-highlighting"
  fi
}

configure_starship() {
  log "Writing Starship config..."
  mkdir -p "${HOME}/.config"
  cat > "${HOME}/.config/starship.toml" <<'EOF'
# Minimal, fast Starship config. Extend as desired.
add_newline = false
command_timeout = 800

[git_branch]
symbol = " "

[python]
disabled = false

[nodejs]
disabled = false

[azure]
disabled = false
EOF
}

configure_atuin() {
  log "Writing Atuin config..."
  mkdir -p "${HOME}/.config/atuin"

  cat > "${HOME}/.config/atuin/config.toml" <<EOF
# Atuin config (bootstrap default)
auto_sync = true
sync_frequency = "10m"
sync_address = "https://api.atuin.sh"

# Reduce risk of capturing secrets.
secrets_filter = true

# Additional custom filters (regex). Adjust over time.
history_filter = [
  "(?i)password",
  "(?i)passwd",
  "(?i)secret",
  "(?i)token",
  "(?i)apikey",
  "(?i)api_key",
  "(?i)bearer\\\\s+[a-z0-9\\\\._\\\\-]+",
  "(?i)ghp_[A-Za-z0-9_]+",
  "(?i)github_pat_[A-Za-z0-9_]+",
  "(?i)AZURE_.*KEY",
]
EOF

  # Attempt non-interactive login if secrets are present (useful in Codespaces).
  if [[ -n "${ATUIN_PASSWORD:-}" && -n "${ATUIN_KEY:-}" ]]; then
    log "Attempting Atuin login (non-interactive; requires ATUIN_PASSWORD + ATUIN_KEY)..."
    set +e
    atuin login -u "${ATUIN_USERNAME}" -p "${ATUIN_PASSWORD}" -k "${ATUIN_KEY}"
    atuin sync
    set -e
  else
    log "Atuin installed. Set ATUIN_KEY + ATUIN_PASSWORD in secrets.env, then re-run."
  fi
}

configure_git() {
  log "Configuring git to use delta..."
  if command -v delta >/dev/null 2>&1; then
    git config --global core.pager delta
    git config --global interactive.diffFilter "delta --color-only"
    git config --global delta.navigate true
    git config --global delta.line-numbers true
    git config --global delta.side-by-side false
    git config --global merge.conflictstyle diff3
    git config --global diff.colorMoved default
  fi
}

configure_pet() {
  log "Configuring pet..."
  mkdir -p "${HOME}/.config/pet"
  touch "${HOME}/.config/pet/snippet.toml"

  # Use relative paths; env vars in pet config are historically problematic, but "~/" is supported.
  cat > "${HOME}/.config/pet/config.toml" <<'EOF'
[General]
  snippetfile = "~/.config/pet/snippet.toml"
  editor = "nano"
  column = 40
  selectcmd = "fzf --ansi --layout=reverse --border --height=80%"

EOF

  if require_cmd code; then
    perl -i -pe 's/editor = "nano"/editor = "code --wait"/' "${HOME}/.config/pet/config.toml" || true
  fi

  # Clone private snippets repo and symlink snippet.toml
  if [[ -n "${PET_SNIPPETS_TOKEN:-}" ]]; then
    local_repo="${HOME}/.config/pet/snippets-repo"
    mkdir -p "$(dirname "$local_repo")"

    # Normalize PET_SNIPPETS_REPO into an https URL
    repo="${PET_SNIPPETS_REPO}"
    if [[ "$repo" != https://* && "$repo" != http://* ]]; then
      repo="https://${repo}"
    fi
    # Ensure .git suffix
    if [[ "$repo" != *.git ]]; then
      repo="${repo}.git"
    fi

    gh_user="${PET_SNIPPETS_GIT_USERNAME:-fredrik}"
    repo_with_user="$(echo "$repo" | sed -E "s#^https://#https://${gh_user}@#")"

    askpass="$(mktemp)"
    cat > "$askpass" <<'EOF'
#!/usr/bin/env bash
# Git will call this for the HTTPS password prompt.
echo "${PET_SNIPPETS_TOKEN}"
EOF
    chmod 700 "$askpass"

    if [[ -d "${local_repo}/.git" ]]; then
      log "Updating pet snippets repo..."
      (cd "${local_repo}" && GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0 git pull --rebase) || true
    else
      log "Cloning pet snippets repo..."
      GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0 git clone "${repo_with_user}" "${local_repo}" || true
    fi
    rm -f "$askpass"

    if [[ -f "${local_repo}/snippet.toml" ]]; then
      ln -sf "${local_repo}/snippet.toml" "${HOME}/.config/pet/snippet.toml"
      log "pet snippet.toml linked to private repo."
    else
      log "Repo cloned but snippet.toml not found at repo root; expected ${local_repo}/snippet.toml"
    fi
  else
    log "Pet snippets repo not configured (set PET_SNIPPETS_TOKEN in secrets.env to enable)."
  fi
}

write_bootstrap_zshrc() {
  log "Writing bootstrap zshrc fragment..."
  cat > "${BOOTSTRAP_HOME}/zshrc" <<EOF
# shell-bootstrap zsh config

# ============================================================================
# Zsh options for better usability
# ============================================================================
setopt AUTO_CD              # cd by typing directory name
setopt AUTO_PUSHD           # push directories onto stack
setopt PUSHD_IGNORE_DUPS    # don't push duplicates
setopt PUSHD_SILENT         # don't print directory stack
setopt CORRECT              # command auto-correction
setopt EXTENDED_GLOB        # extended globbing
setopt NO_BEEP              # no beeping
setopt HIST_IGNORE_DUPS     # ignore duplicate history entries
setopt HIST_IGNORE_SPACE    # ignore commands starting with space
setopt SHARE_HISTORY        # share history between sessions
setopt APPEND_HISTORY       # append to history file
setopt INC_APPEND_HISTORY   # add commands immediately
setopt INTERACTIVE_COMMENTS # allow comments in interactive shell

# Case-insensitive completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Ensure local bins are available
export PATH="${BOOTSTRAP_BIN}:\$HOME/.local/go/bin:\$HOME/.atuin/bin:\$PATH"

# Quality-of-life aliases for Ubuntu naming
if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
  alias bat='batcat'
fi
if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
  alias fd='fdfind'
fi

export EDITOR="\${EDITOR:-nano}"

# ============================================================================
# Convenience aliases
# ============================================================================

# Better ls defaults: long format, human sizes, show hidden (except . ..), classify
alias ls='ls --color=auto -F'
alias ll='ls -lAFh --color=auto'
alias la='ls -lAFh --color=auto'
alias l='ls -lFh --color=auto'
alias lt='ls -lAFht --color=auto'    # sorted by time, newest first
alias lS='ls -lAFhS --color=auto'    # sorted by size, largest first

# Safer defaults for destructive commands
alias rm='rm -I'
alias cp='cp -iv'
alias mv='mv -iv'

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias mkdir='mkdir -pv'

# Grep with color
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# Disk usage helpers
alias df='df -h'
alias du='du -h'
alias duf='du -sh * | sort -h'

# Quick history search
alias h='history | tail -50'

# Git shortcuts
alias gs='git status'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline -20'
alias gp='git pull'

# Python
alias py='python3'
alias pip='pip3'

# Docker shortcuts (if docker is available)
if command -v docker >/dev/null 2>&1; then
  alias dps='docker ps'
  alias dpsa='docker ps -a'
  alias di='docker images'
fi

# ============================================================================
# Utility functions
# ============================================================================

# Create directory and cd into it
take() { mkdir -p "\$1" && cd "\$1"; }

# Extract various archive formats
extract() {
  if [[ -f "\$1" ]]; then
    case "\$1" in
      *.tar.bz2) tar xjf "\$1" ;;
      *.tar.gz)  tar xzf "\$1" ;;
      *.tar.xz)  tar xJf "\$1" ;;
      *.bz2)     bunzip2 "\$1" ;;
      *.gz)      gunzip "\$1" ;;
      *.tar)     tar xf "\$1" ;;
      *.tbz2)    tar xjf "\$1" ;;
      *.tgz)     tar xzf "\$1" ;;
      *.zip)     unzip "\$1" ;;
      *.Z)       uncompress "\$1" ;;
      *.7z)      7z x "\$1" ;;
      *)         echo "Cannot extract '\$1'" ;;
    esac
  else
    echo "'\$1' is not a valid file"
  fi
}

# Quick find file by name
ff() { find . -type f -iname "*\$1*" 2>/dev/null; }

# Quick find directory by name
fd_dir() { find . -type d -iname "*\$1*" 2>/dev/null; }

# Show PATH entries one per line
path() { echo "\$PATH" | tr ':' '\n'; }

# zoxide
if command -v zoxide >/dev/null 2>&1; then
  eval "\$(zoxide init zsh)"
fi

# direnv
if command -v direnv >/dev/null 2>&1; then
  eval "\$(direnv hook zsh)"
fi

# Starship prompt
if command -v starship >/dev/null 2>&1; then
  export STARSHIP_CONFIG="\$HOME/.config/starship.toml"
  eval "\$(starship init zsh)"
fi

# Atuin (history + search + sync + integrates with zsh)
if command -v atuin >/dev/null 2>&1; then
  eval "\$(atuin init zsh)"
fi

# zsh-autosuggestions
if [[ -f "${ZSH_PLUGINS_DIR}/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "${ZSH_PLUGINS_DIR}/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# pet: Ctrl-S snippet search (inline)
if command -v pet >/dev/null 2>&1; then
  function pet-select() {
    BUFFER=\$(pet search --query "\$LBUFFER")
    CURSOR=\${#BUFFER}
    zle redisplay
  }
  zle -N pet-select
  stty -ixon 2>/dev/null || true
  bindkey '^S' pet-select 2>/dev/null || true

  function prev() {
    PREV=\$(fc -lrn | head -n 1)
    sh -c "pet new \`printf %q \"\$PREV\"\`"
  }
fi

# zsh-syntax-highlighting MUST be last
if [[ -f "${ZSH_PLUGINS_DIR}/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "${ZSH_PLUGINS_DIR}/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

# Local secrets (WSL) if present
if [[ -f "\$HOME/.config/shell-bootstrap/secrets.env" ]]; then
  source "\$HOME/.config/shell-bootstrap/secrets.env"
fi
EOF
}

wire_user_shell_rc_files() {
  log "Wiring .zshrc and .bashrc..."

  zsh_marker_begin="# >>> shell-bootstrap (managed) >>>"
  zsh_marker_end="# <<< shell-bootstrap (managed) <<<"
  zsh_content='
# Load bootstrap zsh config
if [[ -f "$HOME/.config/shell-bootstrap/zshrc" ]]; then
  source "$HOME/.config/shell-bootstrap/zshrc"
fi
'
  append_block_once "${HOME}/.zshrc" "$zsh_marker_begin" "$zsh_marker_end" "$zsh_content"

  bash_marker_begin="# >>> shell-bootstrap (managed) >>>"
  bash_marker_end="# <<< shell-bootstrap (managed) <<<"
  bash_content='
# Prefer zsh for interactive shells
case $- in
  *i*)
    if command -v zsh >/dev/null 2>&1 && [[ -z "${ZSH_VERSION:-}" ]]; then
      exec zsh
    fi
  ;;
esac

# Ensure local bins are available even in bash
export PATH="$HOME/.local/bin:$HOME/.atuin/bin:$PATH"
'
  append_block_once "${HOME}/.bashrc" "$bash_marker_begin" "$bash_marker_end" "$bash_content"
}

try_set_default_shell_zsh() {
  if require_cmd zsh && require_cmd chsh; then
    local current_shell
    current_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [[ "$current_shell" == "$(command -v zsh)" ]]; then
      log "Default shell is already zsh."
      return
    fi
    log "To set zsh as your default shell, run: chsh -s \$(which zsh)"
    log "(The .bashrc fallback will auto-exec zsh for interactive sessions anyway.)"
  fi
}

install_readme_locally() {
  log "Installing zsh_readme.md locally..."
  cat > "${BOOTSTRAP_SHARE}/zsh_readme.md" <<'EOF'
See the repo's zsh_readme.md for full documentation.
EOF
}

generate_secrets_template() {
  local secrets_file="${BOOTSTRAP_HOME}/secrets.env"
  if [[ -f "$secrets_file" ]]; then
    return
  fi

  log "Generating secrets.env template..."
  cat > "$secrets_file" <<'EOF'
# Shell Bootstrap Secrets
# Fill in these values and re-run install.sh to enable sync features.
# This file is sourced by the installer and zshrc.

# ============================================================================
# ATUIN - Shell history sync (https://atuin.sh)
# ============================================================================
# Get your key from a machine where you're logged in: atuin key
# Or register at: https://atuin.sh
#
# export ATUIN_PASSWORD="your_atuin_password"
# export ATUIN_KEY="your_atuin_encryption_key"

# ============================================================================
# PET SNIPPETS - Shell snippet sync
# ============================================================================
# GitHub Personal Access Token for private snippets repo.
#
# Create a fine-grained token at: https://github.com/settings/tokens?type=beta
#   - Repository access: Only select repositories -> shell-snippets-private
#   - Permissions: Contents -> Read and write
#
# Or classic token at: https://github.com/settings/tokens/new
#   - Select scope: repo
#
# export PET_SNIPPETS_TOKEN="ghp_your_token_here"
EOF
}

print_next_steps() {
  local secrets_file="${BOOTSTRAP_HOME}/secrets.env"
  local missing=()

  if [[ -z "${ATUIN_KEY:-}" || -z "${ATUIN_PASSWORD:-}" ]]; then
    missing+=("Atuin sync")
  fi
  if [[ -z "${PET_SNIPPETS_TOKEN:-}" ]]; then
    missing+=("Pet snippets sync")
  fi

  echo ""
  log "============================================"
  log "Done! Run: exec zsh"
  log "============================================"

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo ""
    log "Optional: To enable ${missing[*]}:"
    log "  1. Edit ${secrets_file}"
    log "  2. Uncomment and fill in the values"
    log "  3. Re-run: ~/shell-bootstrap/install.sh"
  fi
}

main() {
  generate_secrets_template
  install_apt_packages
  install_delta
  install_atuin
  install_starship
  install_pet
  install_zsh_plugins
  install_claude_code

  configure_starship
  configure_atuin
  configure_git
  configure_pet
  configure_claude_code

  write_bootstrap_zshrc
  wire_user_shell_rc_files
  try_set_default_shell_zsh
  install_readme_locally

  print_next_steps
}
main "$@"
