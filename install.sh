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
  # Unset empty values so prompts will trigger for them
  [[ -z "${ATUIN_KEY:-}" ]] && unset ATUIN_KEY
  [[ -z "${ATUIN_PASSWORD:-}" ]] && unset ATUIN_PASSWORD
  [[ -z "${PET_SNIPPETS_TOKEN:-}" ]] && unset PET_SNIPPETS_TOKEN
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

prompt_for_credentials() {
  local secrets_file="${BOOTSTRAP_HOME}/secrets.env"
  local need_prompts=false

  # Check if any credentials are missing
  if [[ -z "${ATUIN_USERNAME:-}" || -z "${ATUIN_PASSWORD:-}" || -z "${ATUIN_KEY:-}" || -z "${PET_SNIPPETS_TOKEN:-}" ]]; then
    need_prompts=true
  fi

  if [[ "$need_prompts" != "true" ]]; then
    return
  fi

  echo ""
  log "╔════════════════════════════════════════════════════════════════╗"
  log "║  SYNC CREDENTIALS SETUP                                       ║"
  log "║  Press Enter to skip any field you don't want to configure.   ║"
  log "╚════════════════════════════════════════════════════════════════╝"
  echo ""

  # Ensure secrets file exists with proper header
  if [[ ! -f "$secrets_file" ]]; then
    cat > "$secrets_file" <<'EOF'
# Shell Bootstrap Secrets - Auto-generated
# These credentials enable sync features across machines.

EOF
  else
    # Remove empty export lines from previous runs
    sed -i '/^export [A-Z_]*=""$/d' "$secrets_file"
  fi

  # Prompt for Atuin credentials if not set
  if [[ -z "${ATUIN_USERNAME:-}" || -z "${ATUIN_PASSWORD:-}" || -z "${ATUIN_KEY:-}" ]]; then
    echo "ATUIN SYNC - Sync shell history across machines"
    echo "  Already have an account? Enter credentials below."
    echo "  New user? Run 'atuin register' after install, then re-run install.sh"
    echo ""

    # Username
    if [[ -z "${ATUIN_USERNAME:-}" ]]; then
      read -rp "  Atuin username [${DEFAULT_ATUIN_USERNAME}]: " input_user
      input_user="${input_user:-$DEFAULT_ATUIN_USERNAME}"
      if [[ -n "$input_user" ]]; then
        export ATUIN_USERNAME="$input_user"
        if ! grep -q "^export ATUIN_USERNAME=" "$secrets_file" 2>/dev/null; then
          echo "export ATUIN_USERNAME=\"$input_user\"" >> "$secrets_file"
        else
          sed -i "s|^export ATUIN_USERNAME=.*|export ATUIN_USERNAME=\"$input_user\"|" "$secrets_file"
        fi
        log "  Saved ATUIN_USERNAME to secrets.env"
      fi
    fi

    # Password
    if [[ -z "${ATUIN_PASSWORD:-}" ]]; then
      read -rsp "  Atuin password (blank to skip): " input_pass
      echo ""
      if [[ -n "$input_pass" ]]; then
        export ATUIN_PASSWORD="$input_pass"
        if ! grep -q "^export ATUIN_PASSWORD=" "$secrets_file" 2>/dev/null; then
          echo "export ATUIN_PASSWORD=\"$input_pass\"" >> "$secrets_file"
        else
          sed -i "s|^export ATUIN_PASSWORD=.*|export ATUIN_PASSWORD=\"$input_pass\"|" "$secrets_file"
        fi
        log "  Saved ATUIN_PASSWORD to secrets.env"
      fi
    fi

    # Key (optional - will be auto-captured after login)
    if [[ -z "${ATUIN_KEY:-}" ]]; then
      read -rp "  Atuin encryption key (blank to auto-capture after login): " input_key
      if [[ -n "$input_key" ]]; then
        export ATUIN_KEY="$input_key"
        if ! grep -q "^export ATUIN_KEY=" "$secrets_file" 2>/dev/null; then
          echo "export ATUIN_KEY=\"$input_key\"" >> "$secrets_file"
        else
          sed -i "s|^export ATUIN_KEY=.*|export ATUIN_KEY=\"$input_key\"|" "$secrets_file"
        fi
        log "  Saved ATUIN_KEY to secrets.env"
      fi
    fi
  fi

  echo ""

  # Prompt for Pet snippets token if not set
  if [[ -z "${PET_SNIPPETS_TOKEN:-}" ]]; then
    echo "PET SNIPPETS SYNC - Sync command snippets across machines"
    echo "  Create a GitHub token at: https://github.com/settings/tokens"
    echo "  Needs 'repo' scope for private repos"
    echo ""
    read -rp "  GitHub token for snippets repo (blank to skip): " input_token
    if [[ -n "$input_token" ]]; then
      export PET_SNIPPETS_TOKEN="$input_token"
      if ! grep -q "^export PET_SNIPPETS_TOKEN=" "$secrets_file" 2>/dev/null; then
        echo "export PET_SNIPPETS_TOKEN=\"$input_token\"" >> "$secrets_file"
      else
        sed -i "s|^export PET_SNIPPETS_TOKEN=.*|export PET_SNIPPETS_TOKEN=\"$input_token\"|" "$secrets_file"
      fi
      log "  Saved PET_SNIPPETS_TOKEN to secrets.env"
    fi
  fi

  echo ""
  chmod 600 "$secrets_file"
  log "Credentials saved to $secrets_file (chmod 600)"
  echo ""
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
  ${SUDO} apt-get install -y wslu || true  # WSL utilities (wslview for opening files in Windows)
}

install_glow() {
  if require_cmd glow; then
    log "glow already installed."
    return
  fi
  log "Installing glow (markdown renderer)..."
  local arch tag asset url tmpdir
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch="x86_64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) log "Unsupported arch for glow: $arch"; return ;;
  esac

  tag="$(curl -fsSL https://api.github.com/repos/charmbracelet/glow/releases/latest | jq -r .tag_name)"
  local version="${tag#v}"
  asset="glow_${version}_Linux_${arch}.tar.gz"
  url="https://github.com/charmbracelet/glow/releases/download/${tag}/${asset}"

  tmpdir="$(mktemp -d)"
  curl -fsSL "$url" -o "${tmpdir}/glow.tgz"
  tar -xzf "${tmpdir}/glow.tgz" -C "${tmpdir}"
  install -m 0755 "${tmpdir}/glow_${version}_Linux_${arch}/glow" "${BOOTSTRAP_BIN}/glow"
  rm -rf "${tmpdir}"
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
  # Add to PATH for current session so configure_atuin can find it
  export PATH="$HOME/.atuin/bin:$PATH"
}

install_yazi() {
  if require_cmd yazi; then
    log "Yazi file manager already installed."
    return
  fi
  log "Installing Yazi file manager..."

  local arch tag asset url tmpdir
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) log "Unsupported arch for yazi: $arch"; return ;;
  esac

  tag="$(curl -fsSL https://api.github.com/repos/sxyazi/yazi/releases/latest | jq -r .tag_name)"
  asset="yazi-${arch}-unknown-linux-musl.zip"
  url="https://github.com/sxyazi/yazi/releases/download/${tag}/${asset}"

  tmpdir="$(mktemp -d)"
  curl -fsSL "$url" -o "${tmpdir}/yazi.zip"
  unzip -q "${tmpdir}/yazi.zip" -d "${tmpdir}"
  install -m 0755 "${tmpdir}/yazi-${arch}-unknown-linux-musl/yazi" "${BOOTSTRAP_BIN}/yazi"
  install -m 0755 "${tmpdir}/yazi-${arch}-unknown-linux-musl/ya" "${BOOTSTRAP_BIN}/ya"
  rm -rf "${tmpdir}"
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

  # Create enhanced status line script
  cat > "${statusline_script}" <<'STATUSLINE_EOF'
#!/bin/bash
# Claude Code Status Line - shell-bootstrap (enhanced)
# Shows: model icon, git branch, cost, context bar, cwd

input=$(cat)

# ANSI color codes
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_CYAN="\033[36m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_RED="\033[31m"
C_MAGENTA="\033[35m"
C_BLUE="\033[34m"

# Parse JSON input
MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
MODEL_ID=$(echo "$input" | jq -r '.model.model_id // ""')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
INPUT_TOKENS=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
CWD=$(echo "$input" | jq -r '.cwd // ""')

# Model indicator with icon
MODEL_ICON="◆"
MODEL_COLOR="$C_CYAN"
case "$MODEL_ID" in
  *opus*) MODEL_ICON="◆"; MODEL_COLOR="$C_MAGENTA" ;;
  *sonnet*) MODEL_ICON="●"; MODEL_COLOR="$C_CYAN" ;;
  *haiku*) MODEL_ICON="○"; MODEL_COLOR="$C_GREEN" ;;
esac
# Short model name
SHORT_MODEL=$(echo "$MODEL" | sed -E 's/Claude ([0-9.]+) (Opus|Sonnet|Haiku).*/\2/')
MODEL_STR="${MODEL_COLOR}${MODEL_ICON} ${SHORT_MODEL}${C_RESET}"

# Format cost with color (green < $0.10, yellow < $0.50, red >= $0.50)
COST_STR=""
if (( $(echo "$COST > 0.001" | bc -l 2>/dev/null || echo 0) )); then
  COST_COLOR="$C_GREEN"
  if (( $(echo "$COST >= 0.50" | bc -l 2>/dev/null || echo 0) )); then
    COST_COLOR="$C_RED"
  elif (( $(echo "$COST >= 0.10" | bc -l 2>/dev/null || echo 0) )); then
    COST_COLOR="$C_YELLOW"
  fi
  COST_STR=" ${C_DIM}│${C_RESET} ${COST_COLOR}\$$(printf '%.2f' "$COST")${C_RESET}"
fi

# Context usage with visual bar and color thresholds
CTX_STR=""
if [[ "$CONTEXT_SIZE" -gt 0 && "$INPUT_TOKENS" -gt 0 ]]; then
  PCT=$(( INPUT_TOKENS * 100 / CONTEXT_SIZE ))

  # Color based on usage: green <50%, yellow <80%, red >=80%
  CTX_COLOR="$C_GREEN"
  if [[ $PCT -ge 80 ]]; then
    CTX_COLOR="$C_RED"
  elif [[ $PCT -ge 50 ]]; then
    CTX_COLOR="$C_YELLOW"
  fi

  # Create mini progress bar (5 chars)
  FILLED=$(( PCT / 20 ))
  EMPTY=$(( 5 - FILLED ))
  BAR=""
  for ((i=0; i<FILLED; i++)); do BAR+="█"; done
  for ((i=0; i<EMPTY; i++)); do BAR+="░"; done

  CTX_STR=" ${C_DIM}│${C_RESET} ${CTX_COLOR}${BAR} ${PCT}%${C_RESET}"
fi

# Git branch with status (if in a repo)
GIT_STR=""
if git rev-parse --git-dir > /dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null)
  if [[ -n "$BRANCH" ]]; then
    # Truncate long branch names
    if [[ ${#BRANCH} -gt 20 ]]; then
      BRANCH="${BRANCH:0:18}.."
    fi

    # Check for changes
    DIRTY=""
    STAGED=$(git diff --cached --numstat 2>/dev/null | wc -l)
    UNSTAGED=$(git diff --numstat 2>/dev/null | wc -l)
    UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)

    if [[ $STAGED -gt 0 || $UNSTAGED -gt 0 || $UNTRACKED -gt 0 ]]; then
      DIRTY="${C_YELLOW}*${C_RESET}"
    fi

    GIT_STR=" ${C_DIM}│${C_RESET} ${C_BLUE} ${BRANCH}${DIRTY}${C_RESET}"
  fi
fi

# Working directory (last 2 path segments)
CWD_STR=""
if [[ -n "$CWD" ]]; then
  SHORT_CWD=$(echo "$CWD" | sed "s|^$HOME|~|" | awk -F'/' '{if(NF>2) print $(NF-1)"/"$NF; else print $0}')
  CWD_STR=" ${C_DIM}│${C_RESET} ${C_DIM}${SHORT_CWD}${C_RESET}"
fi

# Assemble status line
echo -e "${MODEL_STR}${GIT_STR}${COST_STR}${CTX_STR}${CWD_STR}"
STATUSLINE_EOF

  chmod +x "${statusline_script}"

  # Create startup tips script that shows 5 random tips
  cat > "${startup_script}" <<'STARTUP_EOF'
#!/bin/bash
# Claude Code Startup Tips - shell-bootstrap
# Shows 5 random tips when Claude starts

TIPS=(
  "@file.txt - include file contents in prompt"
  "@folder/ - include directory structure"
  "/compact - compress context when it gets large"
  "/model haiku - cheaper & faster for simple tasks"
  "/model opus - best reasoning (costs more)"
  "/cost - check your session spending"
  "/clear - reset conversation (loses history)"
  "/doctor - diagnose setup issues"
  "/vim - enable vim keybindings"
  "Escape (2x) - interrupt generation"
  "Ctrl+C cancel, Ctrl+D exit"
  "! cmd - run shell inline: ! git status"
  "claude 'prompt' < file - pipe input"
  "claude -c - continue last session"
  "claude -r - resume with history"
  "claude 'review' < <(git diff) - review changes"
  "claude 'commit msg' < <(git diff --staged)"
  "Tab - accept autocomplete suggestion"
  "~/CLAUDE.md - full tips reference"
  "/init - create project CLAUDE.md"
)

# Shuffle and pick 5 unique tips
SELECTED=()
INDICES=($(shuf -i 0-$((${#TIPS[@]}-1)) -n 5))
for i in "${INDICES[@]}"; do
  SELECTED+=("${TIPS[$i]}")
done

# Print with formatting
echo ""
echo -e "\033[1;36m┌─ 💡 Quick Tips ─────────────────────────────────────────────┐\033[0m"
for tip in "${SELECTED[@]}"; do
  echo -e "\033[1;36m│\033[0m  \033[1;33m•\033[0m ${tip}"
done
echo -e "\033[1;36m└─────────────────────────────────────────────────────────────┘\033[0m"
echo ""
STARTUP_EOF

  chmod +x "${startup_script}"

  # Create settings.json with statusLine and startup hook
  # Note: SessionStart doesn't need a matcher (only PreToolUse/PostToolUse do)
  cat > "${settings_file}" <<SETTINGS_EOF
{
  "statusLine": {
    "type": "command",
    "command": "${statusline_script}",
    "padding": 0
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${startup_script}"
          }
        ]
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
sync_frequency = "5m"
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

  # Check if atuin is available
  if ! command -v atuin >/dev/null 2>&1; then
    log "Atuin not found in PATH, skipping sync setup."
    return
  fi

  # Check if already logged in by testing sync
  if atuin sync 2>/dev/null; then
    log "Atuin already logged in and synced."
    return
  fi

  local secrets_file="${BOOTSTRAP_HOME}/secrets.env"

  # Attempt non-interactive login if secrets are present
  if [[ -n "${ATUIN_PASSWORD:-}" && -n "${ATUIN_USERNAME:-}" ]]; then
    log "Attempting Atuin login..."
    set +e

    # If we have the key, use it; otherwise login will prompt/generate
    if [[ -n "${ATUIN_KEY:-}" ]]; then
      if atuin login -u "${ATUIN_USERNAME}" -p "${ATUIN_PASSWORD}" -k "${ATUIN_KEY}" 2>/dev/null; then
        log "Atuin login successful!"
      else
        log "Atuin login failed. Check credentials in: ${BOOTSTRAP_HOME}/secrets.env"
      fi
    else
      # Login without key - atuin will use existing or prompt
      if atuin login -u "${ATUIN_USERNAME}" -p "${ATUIN_PASSWORD}" 2>/dev/null; then
        log "Atuin login successful!"
      else
        log "Atuin login failed. Check credentials in: ${BOOTSTRAP_HOME}/secrets.env"
      fi
    fi

    # Auto-capture and save the key after successful login
    local captured_key
    captured_key=$(atuin key 2>/dev/null || true)
    if [[ -n "$captured_key" && "$captured_key" != "${ATUIN_KEY:-}" ]]; then
      export ATUIN_KEY="$captured_key"
      if ! grep -q "^export ATUIN_KEY=" "$secrets_file" 2>/dev/null; then
        echo "export ATUIN_KEY=\"$captured_key\"" >> "$secrets_file"
      else
        sed -i "s|^export ATUIN_KEY=.*|export ATUIN_KEY=\"$captured_key\"|" "$secrets_file"
      fi
      log "Auto-captured ATUIN_KEY to secrets.env"
    fi

    atuin sync 2>/dev/null && log "Atuin history synced." || true
    set -e
  else
    log "Atuin sync not configured. Run 'atuin register' or re-run install.sh with credentials."
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

configure_yazi() {
  log "Configuring Yazi file manager..."

  local yazi_conf_dir="${HOME}/.config/yazi"
  mkdir -p "${yazi_conf_dir}"

  # Yazi config
  cat > "${yazi_conf_dir}/yazi.toml" <<'YAZI_CONF'
# Yazi configuration - shell-bootstrap

[manager]
ratio = [1, 3, 4]
sort_by = "natural"
sort_sensitive = false
sort_reverse = false
sort_dir_first = true
linemode = "size"
show_hidden = true
show_symlink = true

[preview]
tab_size = 2
max_width = 600
max_height = 900

[opener]
edit = [
  { run = '${EDITOR:-nano} "$@"', block = true, for = "unix" },
]
open = [
  { run = 'xdg-open "$@"', desc = "Open", for = "linux" },
]
# Open with Windows native app (WSL)
windows = [
  { run = 'wslview "$@"', desc = "Open in Windows", for = "unix" },
]
YAZI_CONF

  # Yazi keymap
  cat > "${yazi_conf_dir}/keymap.toml" <<'YAZI_KEYS'
# Yazi keybindings - shell-bootstrap

[manager]
prepend_keymap = [
  { on = ["<Esc>"], run = "escape", desc = "Exit visual mode / clear selection" },
  { on = ["q"], run = "quit", desc = "Quit" },
  { on = ["Q"], run = "quit --no-cwd-file", desc = "Quit without changing cwd" },
  { on = ["<C-c>"], run = "close", desc = "Close current tab or quit if last" },

  # Navigation
  { on = ["h"], run = "leave", desc = "Go to parent directory" },
  { on = ["l"], run = "enter", desc = "Enter directory" },
  { on = ["j"], run = "arrow 1", desc = "Move down" },
  { on = ["k"], run = "arrow -1", desc = "Move up" },
  { on = ["g", "g"], run = "arrow -99999999", desc = "Go to top" },
  { on = ["G"], run = "arrow 99999999", desc = "Go to bottom" },

  # Selection
  { on = ["<Space>"], run = ["select --state=none", "arrow 1"], desc = "Toggle selection" },
  { on = ["v"], run = "visual_mode", desc = "Enter visual mode" },
  { on = ["V"], run = "visual_mode --unset", desc = "Enter visual mode (unset)" },

  # Operations
  { on = ["y"], run = "yank", desc = "Yank (copy)" },
  { on = ["x"], run = "yank --cut", desc = "Cut" },
  { on = ["p"], run = "paste", desc = "Paste" },
  { on = ["P"], run = "paste --force", desc = "Paste (overwrite)" },
  { on = ["d"], run = "remove", desc = "Move to trash" },
  { on = ["D"], run = "remove --permanently", desc = "Delete permanently" },
  { on = ["a"], run = "create", desc = "Create file/directory" },
  { on = ["r"], run = "rename --cursor=before_ext", desc = "Rename" },
  { on = ["o"], run = "open", desc = "Open file" },
  { on = ["O"], run = "open --interactive", desc = "Open with..." },
  { on = ["w"], run = "shell 'wslview \"$0\"' --confirm", desc = "Open in Windows" },
  { on = ["W"], run = "shell 'wslview \"$0\"' --confirm", desc = "Open in Windows" },

  # Search
  { on = ["/"], run = "find --smart", desc = "Find" },
  { on = ["n"], run = "find_arrow", desc = "Next match" },
  { on = ["N"], run = "find_arrow --previous", desc = "Previous match" },

  # Sorting (s prefix)
  { on = ["s", "n"], run = "sort natural --dir-first", desc = "Sort by name" },
  { on = ["s", "s"], run = "sort size --dir-first --reverse", desc = "Sort by size" },
  { on = ["s", "m"], run = "sort mtime --dir-first --reverse", desc = "Sort by modified" },

  # Quick jumps
  { on = ["g", "h"], run = "cd ~", desc = "Go home" },
  { on = ["g", "d"], run = "cd ~/Downloads", desc = "Go to Downloads" },
  { on = ["g", "p"], run = "cd ~/projects", desc = "Go to projects" },

  # Hidden files
  { on = ["."], run = "hidden toggle", desc = "Toggle hidden files" },
]
YAZI_KEYS

  # Yazi theme (Tokyo Night)
  cat > "${yazi_conf_dir}/theme.toml" <<'YAZI_THEME'
# Yazi theme - Tokyo Night inspired

[manager]
cwd = { fg = "#7aa2f7" }

# Hovered
hovered = { fg = "#1a1b26", bg = "#7aa2f7" }
preview_hovered = { underline = true }

# Find
find_keyword = { fg = "#e0af68", bold = true }
find_position = { fg = "#bb9af7", bg = "reset", bold = true }

# Marker
marker_copied = { fg = "#9ece6a", bg = "#9ece6a" }
marker_cut = { fg = "#f7768e", bg = "#f7768e" }
marker_selected = { fg = "#7aa2f7", bg = "#7aa2f7" }

# Tab
tab_active = { fg = "#1a1b26", bg = "#7aa2f7" }
tab_inactive = { fg = "#545c7e", bg = "#1a1b26" }
tab_width = 1

# Status bar
[status]
separator_open = ""
separator_close = ""
separator_style = { fg = "#1a1b26", bg = "#1a1b26" }

# Mode
mode_normal = { fg = "#1a1b26", bg = "#7aa2f7", bold = true }
mode_select = { fg = "#1a1b26", bg = "#9ece6a", bold = true }
mode_unset = { fg = "#1a1b26", bg = "#f7768e", bold = true }

# Progress
progress_label = { fg = "#c0caf5", bold = true }
progress_normal = { fg = "#7aa2f7", bg = "#1a1b26" }
progress_error = { fg = "#f7768e", bg = "#1a1b26" }

[filetype]
rules = [
  { mime = "image/*", fg = "#bb9af7" },
  { mime = "video/*", fg = "#e0af68" },
  { mime = "audio/*", fg = "#e0af68" },
  { mime = "application/zip", fg = "#f7768e" },
  { mime = "application/gzip", fg = "#f7768e" },
  { mime = "application/x-tar", fg = "#f7768e" },
  { mime = "application/pdf", fg = "#9ece6a" },
  { name = "*.md", fg = "#7dcfff" },
  { name = "*.json", fg = "#e0af68" },
  { name = "*.yml", fg = "#bb9af7" },
  { name = "*.yaml", fg = "#bb9af7" },
  { name = "*.toml", fg = "#bb9af7" },
]
YAZI_THEME
}

configure_tmux() {
  log "Configuring tmux..."

  local tmux_conf="${HOME}/.tmux.conf"
  local dev_script="${BOOTSTRAP_BIN}/dev-session"

  # Create tmux.conf with sensible defaults
  cat > "${tmux_conf}" <<'TMUX_CONF'
# tmux configuration - shell-bootstrap

# Use Ctrl+A as prefix (easier than Ctrl+B)
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# Enable mouse support
set -g mouse on

# Start windows and panes at 1, not 0
set -g base-index 1
setw -g pane-base-index 1

# Renumber windows when one is closed
set -g renumber-windows on

# Increase history limit
set -g history-limit 50000

# Faster escape time (for vim)
set -sg escape-time 10

# Enable 256 colors and true color
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",*256col*:Tc"

# Status bar styling
set -g status-style 'bg=#1a1b26 fg=#c0caf5'
set -g status-left '#[fg=#7aa2f7,bold][#S] '
set -g status-left-length 20
set -g status-right '#[fg=#9ece6a]%H:%M #[fg=#bb9af7]%d-%b'
set -g status-right-length 40

# Window status
setw -g window-status-current-style 'fg=#1a1b26 bg=#7aa2f7 bold'
setw -g window-status-current-format ' #I:#W '
setw -g window-status-style 'fg=#545c7e'
setw -g window-status-format ' #I:#W '

# Pane borders
set -g pane-border-style 'fg=#3b4261'
set -g pane-active-border-style 'fg=#7aa2f7'

# Vi mode for copy
setw -g mode-keys vi
bind -T copy-mode-vi v send-keys -X begin-selection
bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel

# Easier splits (| and -)
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

# Vim-like pane navigation
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Resize panes with Ctrl+hjkl
bind -r C-h resize-pane -L 5
bind -r C-j resize-pane -D 5
bind -r C-k resize-pane -U 5
bind -r C-l resize-pane -R 5

# Quick window switching
bind -n M-1 select-window -t 1
bind -n M-2 select-window -t 2
bind -n M-3 select-window -t 3
bind -n M-4 select-window -t 4

# Reload config
bind r source-file ~/.tmux.conf \; display "Config reloaded!"

# Toggle zoom with z
bind z resize-pane -Z

# New window in current path
bind c new-window -c "#{pane_current_path}"
TMUX_CONF

  # Create dev session launcher script
  cat > "${dev_script}" <<'DEV_SESSION'
#!/usr/bin/env bash
# Dev session - Four tabs: claude, shell, files, help

SESSION="dev"
WORKING_DIR="${1:-$(pwd)}"

# Check if session exists
if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux attach-session -t "$SESSION"
  exit 0
fi

# Tab 1: Claude
tmux new-session -d -s "$SESSION" -n "claude" -c "$WORKING_DIR"
tmux send-keys "claude" Enter

# Tab 2: zsh shell
tmux new-window -t "$SESSION" -n "shell" -c "$WORKING_DIR"

# Tab 3: yazi file manager
tmux new-window -t "$SESSION" -n "files" -c "$WORKING_DIR"
tmux send-keys "yazi" Enter

# Tab 4: reference/shortcuts
tmux new-window -t "$SESSION" -n "help"
tmux send-keys "less -R ~/.config/shell-bootstrap/shell-reference.txt" Enter

# Start on Claude tab
tmux select-window -t "$SESSION:1"

# Attach to session
tmux attach-session -t "$SESSION"
DEV_SESSION

  chmod +x "${dev_script}"
  log "Created dev-session launcher at ${dev_script}"
}

configure_shell_reference() {
  log "Creating shell reference file..."
  cat > "${BOOTSTRAP_HOME}/shell-reference.txt" <<'SHELL_REF'
═══════════════════════════════════════════════════════════════════════════════════════════════════════
                              SHELL ENVIRONMENT REFERENCE  (type 'help' to show)
═══════════════════════════════════════════════════════════════════════════════════════════════════════

┌─ ZSH VI MODE ────────────────────────────────────┐  ┌─ ATUIN (History Search & Sync) ─────────────────┐
│ ESC/Ctrl+[    Normal mode (block cursor)         │  │ Ctrl+R        Interactive history search        │
│ i/a           Insert mode (beam cursor)          │  │ Up/Down       Navigate history (prefix search)  │
│ h/l           Move left/right                    │  │ ─ In search UI ─                                │
│ w/b           Forward/backward by word           │  │ Enter         Execute selected command          │
│ 0/$           Start/end of line                  │  │ Tab           Insert to prompt (don't execute)  │
│ j/k           Previous/next history              │  │ Ctrl+D        Delete entry from history         │
│ x             Delete character                   │  │ ESC/Ctrl+C    Cancel search                     │
│ dw/dd         Delete word/line                   │  │ ─ Commands ─                                    │
│ cw/cc         Change word/line                   │  │ atuin sync    Sync history with server          │
│ yy/p          Yank line / paste                  │  │ atuin stats   Show history statistics           │
│ u             Undo                               │  │ atuin key     Show encryption key               │
│ ─ Insert mode shortcuts ─                        │  │ atuin login   Login to atuin server             │
│ Ctrl+A/E      Start/end of line                  │  └──────────────────────────────────────────────────┘
│ Ctrl+W        Delete word backward               │
│ Ctrl+U/K      Delete to start/end                │  ┌─ PET (Snippet Manager) ──────────────────────────┐
└──────────────────────────────────────────────────┘  │ Ctrl+S        Search snippets (insert to prompt) │
                                                      │ pet new       Create new snippet                 │
┌─ YAZI (File Manager) ────────────────────────────┐  │ prev          Save last command as snippet       │
│ y             Open yazi (cd on exit)             │  │ pet search    Interactive snippet search         │
│ h/l           Parent / enter directory           │  │ pet edit      Edit snippets file                 │
│ j/k           Move down/up                       │  │ pet list      List all snippets                  │
│ gg/G          First/last item                    │  └──────────────────────────────────────────────────┘
│ gh/gd/gp      Go home/Downloads/projects         │
│ .             Toggle hidden files                │  ┌─ ZOXIDE & FZF ────────────────────────────────────┐
│ Space         Toggle selection                   │  │ z <query>     Jump to matching directory         │
│ y/x           Yank/cut selected                  │  │ zi <query>    Interactive selection with fzf     │
│ p/P           Paste / paste overwrite            │  │ Ctrl+T        Fuzzy find files, insert path      │
│ d/D           Trash / delete permanently         │  │ Alt+C         Fuzzy cd into subdirectory         │
│ a/r           Create / rename                    │  │ **<Tab>       Trigger fzf completion             │
│ o/O           Open / open with picker            │                                                      │
│ w/W           Open in Windows (wslview)          │                                                      │
│ /n/N          Find / next/prev match             │  └──────────────────────────────────────────────────┘
│ sn/ss/sm      Sort: name/size/modified           │
│ q             Quit                               │  ┌─ TMUX (Ctrl+A = prefix) ─────────────────────────┐
└──────────────────────────────────────────────────┘  │ dev           Dev session (3 tabs)               │
                                                      │ Ctrl+A c      Create window                      │
┌─ GIT ALIASES ────────────────────────────────────┐  │ Ctrl+A |/-    Split vertical/horizontal          │
│ gs            git status                         │  │ Ctrl+A h/j/k/l Navigate panes (vim-style)        │
│ gd/gds        git diff / diff --staged           │  │ Ctrl+A z      Toggle pane zoom                   │
│ gl            git log --oneline -20              │  │ Alt+1/2/3/4   Switch to window 1-4               │
│ gp            git pull                           │  │ Ctrl+A d      Detach from session                │
└──────────────────────────────────────────────────┘  │ Ctrl+A [      Scroll/copy mode (q to exit)       │
                                                      │ Ctrl+A r      Reload tmux config                 │
┌─ ALIASES & FUNCTIONS ────────────────────────────┐  └──────────────────────────────────────────────────┘
│ dev           Dev session: claude|files|help     │
│ ll/la         Long list with hidden files        │  ┌─ CLAUDE CODE ──────────────────────────────────────┐
│ lt/lS         List by time/size                  │  │ claude        Start Claude Code                  │
│ ../...        Go up 1/2 directories              │  │ claude -c     Continue last session              │
│ take <dir>    Create dir and cd into it          │  │ claude -p X   Use specific profile               │
│ extract <f>   Extract any archive                │  │ claude --dangerously-skip-permissions            │
│ ff <name>     Find file by name                  │  │               Unattended mode (no prompts)       │
│ path          Show PATH one per line             │  │ ─ Slash Commands ─                               │
│ duf           Disk usage sorted                  │  │ /help         Show all slash commands            │
│ h/help        History / this reference           │  │ /model X      Switch model (opus/sonnet/haiku)   │
└──────────────────────────────────────────────────┘  │ /compact      Compress context                   │
                                                      │ /clear        Clear conversation history         │
┌─ CLAUDE CODE (continued) ───────────────────────┐  │ /cost         Show session token costs           │
│ ─ Include Content ─                              │  │ /doctor       Diagnose setup issues              │
│ @file.txt     Include file in prompt             │  │ /vim          Enable vim keybindings             │
│ @folder/      Include directory structure        │  │ /init         Create CLAUDE.md for project       │
│ ! <cmd>       Run shell command inline           │  │ ─ Keyboard ─                                     │
│ ─ Piping ─                                       │  │ Tab           Accept autocomplete suggestion     │
│ claude "msg" < file     Pipe file to prompt      │  │ Ctrl+C        Cancel current operation           │
│ git diff | claude "..."  Pipe command output     │  │ Ctrl+D        Exit Claude Code                   │
│ ─ Quick Patterns ─                               │  │ Esc Esc       Interrupt generation               │
│ claude "explain" < error.log                     │  └──────────────────────────────────────────────────┘
│ claude "review" < <(git diff --staged)           │
│ claude "commit msg" < <(git diff --staged)       │
└──────────────────────────────────────────────────┘

┌─ WINDOWS TERMINAL ───────────────────────────────┐
│ Ctrl+Tab       Next tab                          │
│ Ctrl+Shift+Tab Previous tab                      │
│ Ctrl+Alt+1-9   Switch to tab 1-9                 │
│ Ctrl+Shift+T   New tab                           │
│ Ctrl+Shift+W   Close tab                         │
│ Ctrl+Shift+D   Duplicate tab                     │
│ Alt+Shift+-    Split pane horizontal             │
│ Alt+Shift++    Split pane vertical               │
│ Alt+Arrow      Move between panes                │
│ Ctrl+Shift+P   Command palette                   │
└──────────────────────────────────────────────────┘

┌─ CONFIG FILES ───────────────────────────────────────────────────────────────────────────────────────────┐
│ ~/.config/starship.toml  ~/.config/atuin/config.toml  ~/.config/pet/{config,snippet}.toml  ~/.config/yazi/│
│ ~/.config/shell-bootstrap/{zshrc,secrets.env}  ~/CLAUDE.md                                               │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────┘
SHELL_REF
}

write_bootstrap_zshrc() {
  log "Writing bootstrap zshrc fragment..."
  cat > "${BOOTSTRAP_HOME}/zshrc" <<EOF
# shell-bootstrap zsh config

# ============================================================================
# WSLg Wayland Setup (native Wayland for better performance)
# ============================================================================
if [[ -d /mnt/wslg ]]; then
  # WSLg detected - configure for native Wayland (faster than X11/XWayland)
  export XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir
  export WAYLAND_DISPLAY=wayland-0
  export XDG_SESSION_TYPE=wayland

  # X11 fallback for apps that don't support Wayland
  export DISPLAY=:0

  # PulseAudio via WSLg
  export PULSE_SERVER=/mnt/wslg/PulseServer
fi

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

# ============================================================================
# Vi mode
# ============================================================================
bindkey -v                  # Enable vi mode
export KEYTIMEOUT=1         # Reduce mode switch delay (10ms)

# Better vi mode indicators and bindings
bindkey '^?' backward-delete-char  # Backspace works in insert mode
bindkey '^h' backward-delete-char  # Ctrl+H backspace
bindkey '^w' backward-kill-word    # Ctrl+W delete word
bindkey '^a' beginning-of-line     # Ctrl+A start of line
bindkey '^e' end-of-line           # Ctrl+E end of line
bindkey '^k' kill-line             # Ctrl+K kill to end
bindkey '^u' backward-kill-line    # Ctrl+U kill to start
bindkey '^r' history-incremental-search-backward  # Ctrl+R search (works with atuin too)
bindkey -M vicmd 'k' up-line-or-history
bindkey -M vicmd 'j' down-line-or-history

# Change cursor shape based on vi mode
function zle-keymap-select {
  if [[ \$KEYMAP == vicmd ]] || [[ \$1 == 'block' ]]; then
    echo -ne '\e[1 q'  # Block cursor for normal mode
  else
    echo -ne '\e[5 q'  # Beam cursor for insert mode
  fi
}
zle -N zle-keymap-select

function zle-line-init {
  echo -ne '\e[5 q'  # Start with beam cursor
}
zle -N zle-line-init

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

# Dev session (tmux: claude|shell|files|help tabs)
alias dev='dev-session'

# Markdown rendering
if command -v glow >/dev/null 2>&1; then
  alias md='glow'
fi

# Yazi file manager with cd on exit
if command -v yazi >/dev/null 2>&1; then
  function y() {
    local tmp="\$(mktemp -t "yazi-cwd.XXXXXX")"
    yazi "\$@" --cwd-file="\$tmp"
    if cwd="\$(cat -- "\$tmp")" && [ -n "\$cwd" ] && [ "\$cwd" != "\$PWD" ]; then
      cd -- "\$cwd"
    fi
    rm -f -- "\$tmp"
  }
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

# Shell help - show comprehensive reference
help() {
  local ref_file="\$HOME/.config/shell-bootstrap/shell-reference.txt"
  if [[ -f "\$ref_file" ]]; then
    less -R "\$ref_file"
  else
    echo "Reference file not found. Run ~/shell-bootstrap/install.sh to create it."
  fi
}

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
# export ATUIN_USERNAME="your_atuin_username"
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
  echo ""
  log "╔════════════════════════════════════════════════════════════════╗"
  log "║  SETUP COMPLETE!                                              ║"
  log "╠════════════════════════════════════════════════════════════════╣"
  log "║  Run: exec zsh                                                ║"
  log "║  Type: dev    (tmux: claude|files|help tabs)                  ║"
  log "║  Type: help   (keyboard shortcuts reference)                  ║"
  log "╚════════════════════════════════════════════════════════════════╝"
  echo ""
}

main() {
  generate_secrets_template
  prompt_for_credentials
  install_apt_packages
  install_glow
  install_delta
  install_atuin
  install_yazi
  install_starship
  install_pet
  install_zsh_plugins
  install_claude_code

  configure_starship
  configure_atuin
  configure_git
  configure_pet
  configure_yazi
  configure_tmux
  configure_shell_reference
  configure_claude_code

  write_bootstrap_zshrc
  wire_user_shell_rc_files
  try_set_default_shell_zsh
  install_readme_locally

  print_next_steps
}
main "$@"
