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
    fonts-firacode fonts-powerline \
    libxcb-xkb1 libxkbcommon-x11-0 libxcb-cursor0 libxcb-keysyms1 libxcb-shape0

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

install_kitty() {
  if require_cmd kitty; then
    log "Kitty terminal already installed."
    return
  fi
  log "Installing Kitty terminal..."
  curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n

  # Create symlinks
  mkdir -p "${BOOTSTRAP_BIN}"
  ln -sf "${HOME}/.local/kitty.app/bin/kitty" "${BOOTSTRAP_BIN}/kitty"
  ln -sf "${HOME}/.local/kitty.app/bin/kitten" "${BOOTSTRAP_BIN}/kitten"

  # Desktop integration (for GUI environments)
  mkdir -p "${HOME}/.local/share/applications"
  cp "${HOME}/.local/kitty.app/share/applications/kitty.desktop" "${HOME}/.local/share/applications/" 2>/dev/null || true
  cp "${HOME}/.local/kitty.app/share/applications/kitty-open.desktop" "${HOME}/.local/share/applications/" 2>/dev/null || true
  sed -i "s|Icon=kitty|Icon=${HOME}/.local/kitty.app/share/icons/hicolor/256x256/apps/kitty.png|g" \
    "${HOME}/.local/share/applications/kitty.desktop" 2>/dev/null || true
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
  asset="yazi-${arch}-unknown-linux-gnu.zip"
  url="https://github.com/sxyazi/yazi/releases/download/${tag}/${asset}"

  tmpdir="$(mktemp -d)"
  curl -fsSL "$url" -o "${tmpdir}/yazi.zip"
  unzip -q "${tmpdir}/yazi.zip" -d "${tmpdir}"
  install -m 0755 "${tmpdir}/yazi-${arch}-unknown-linux-gnu/yazi" "${BOOTSTRAP_BIN}/yazi"
  install -m 0755 "${tmpdir}/yazi-${arch}-unknown-linux-gnu/ya" "${BOOTSTRAP_BIN}/ya"
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

configure_kitty() {
  log "Configuring Kitty terminal..."

  local kitty_conf_dir="${HOME}/.config/kitty"
  mkdir -p "${kitty_conf_dir}"

  # Main kitty.conf
  cat > "${kitty_conf_dir}/kitty.conf" <<'KITTY_CONF'
# ============================================================================
# Kitty Terminal Configuration - shell-bootstrap
# ============================================================================

# Font
font_family      FiraCode Nerd Font Mono
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size        11.0

# Cursor
cursor_shape               beam
cursor_beam_thickness      1.5
cursor_blink_interval      0.5
cursor_stop_blinking_after 15.0

# Scrollback
scrollback_lines 10000

# Mouse
mouse_hide_wait 3.0
url_style       curly
open_url_with   default
copy_on_select  yes

# Terminal bell
enable_audio_bell no
visual_bell_duration 0.0

# Window
remember_window_size  yes
initial_window_width  1200
initial_window_height 800
window_padding_width  4
hide_window_decorations no
confirm_os_window_close 0

# Tab bar
tab_bar_edge        top
tab_bar_style       powerline
tab_powerline_style slanted
tab_title_template  "{index}: {title}"

# ============================================================================
# Layouts - splits is primary, stack for fullscreen toggle
# ============================================================================
enabled_layouts splits,stack

# ============================================================================
# Color Scheme - Tokyo Night inspired
# ============================================================================
foreground #c0caf5
background #1a1b26
background_opacity 0.95

# Selection
selection_foreground #1a1b26
selection_background #c0caf5

# Cursor colors
cursor #c0caf5
cursor_text_color #1a1b26

# URL underline color
url_color #73daca

# Tab bar colors
active_tab_foreground   #1a1b26
active_tab_background   #7aa2f7
inactive_tab_foreground #545c7e
inactive_tab_background #1a1b26
tab_bar_background      #15161e

# Black
color0 #15161e
color8 #414868

# Red
color1 #f7768e
color9 #f7768e

# Green
color2  #9ece6a
color10 #9ece6a

# Yellow
color3  #e0af68
color11 #e0af68

# Blue
color4  #7aa2f7
color12 #7aa2f7

# Magenta
color5  #bb9af7
color13 #bb9af7

# Cyan
color6  #7dcfff
color14 #7dcfff

# White
color7  #a9b1d6
color15 #c0caf5

# ============================================================================
# Keybindings
# ============================================================================

# Clear default shortcuts for customization
clear_all_shortcuts no

# Clipboard
map ctrl+shift+c copy_to_clipboard
map ctrl+shift+v paste_from_clipboard

# Scrolling
map ctrl+shift+up    scroll_line_up
map ctrl+shift+down  scroll_line_down
map ctrl+shift+page_up   scroll_page_up
map ctrl+shift+page_down scroll_page_down
map ctrl+shift+home  scroll_home
map ctrl+shift+end   scroll_end

# Window/Split management
map ctrl+shift+enter launch --cwd=current
map ctrl+shift+\     launch --location=vsplit --cwd=current
map ctrl+shift+-     launch --location=hsplit --cwd=current
map ctrl+shift+w     close_window

# Navigate between splits
map ctrl+shift+h neighboring_window left
map ctrl+shift+l neighboring_window right
map ctrl+shift+k neighboring_window up
map ctrl+shift+j neighboring_window down

# Resize splits
map ctrl+alt+h resize_window narrower
map ctrl+alt+l resize_window wider
map ctrl+alt+k resize_window taller
map ctrl+alt+j resize_window shorter
map ctrl+alt+r resize_window reset

# Toggle fullscreen (switch to stack layout)
map ctrl+shift+z toggle_layout stack

# Tab management
map ctrl+shift+t new_tab_with_cwd
map ctrl+shift+q close_tab
map ctrl+shift+right next_tab
map ctrl+shift+left  previous_tab
map ctrl+shift+. move_tab_forward
map ctrl+shift+, move_tab_backward
map ctrl+alt+1 goto_tab 1
map ctrl+alt+2 goto_tab 2
map ctrl+alt+3 goto_tab 3
map ctrl+alt+4 goto_tab 4
map ctrl+alt+5 goto_tab 5

# Font size
map ctrl+shift+equal change_font_size all +1.0
map ctrl+shift+minus change_font_size all -1.0
map ctrl+shift+0     change_font_size all 0

# Open file manager (yazi) in split
map ctrl+shift+e launch --location=vsplit --cwd=current yazi

# Reload config
map ctrl+shift+f5 load_config_file

# ============================================================================
# Startup session
# ============================================================================
startup_session ~/.config/kitty/startup.session

# Shell
shell zsh

# ============================================================================
# WSL Compatibility (keeps features, fixes issues)
# ============================================================================

# Force X11 (Wayland not fully supported in WSL)
linux_display_server x11

# Skip update checks (reduces startup noise)
update_check_interval 0

# WSL clipboard fix
clipboard_control write-clipboard write-primary read-clipboard read-primary

# Slightly reduce input delay for snappier feel
input_delay 1
repaint_delay 8
KITTY_CONF

  # Create a launch script for the dev layout
  cat > "${kitty_conf_dir}/dev-layout.sh" <<'DEVLAYOUT'
#!/bin/bash
# Launch kitty with dev layout: file explorer + terminal + bottom pane
kitty --session ~/.config/kitty/dev.session "$@"
DEVLAYOUT
  chmod +x "${kitty_conf_dir}/dev-layout.sh"

  # Dev session with file explorer
  # Note: Session files have limited commands - use launch with --location for splits
  cat > "${kitty_conf_dir}/dev.session" <<'DEVSESSION'
# Dev layout: file explorer left, main terminal right, small bottom pane
# After launch, use Ctrl+Alt+H to make left pane narrower

new_tab dev
layout splits
cd ~

# Main terminal on the right (launched first, takes most space)
launch --title main zsh

# File explorer on the left (vsplit from main)
launch --location=vsplit --title files --bias=25 yazi

# Quick commands pane at bottom of main area
launch --location=hsplit --title quick --bias=20 zsh
DEVSESSION

  # Simpler startup session
  cat > "${kitty_conf_dir}/startup.session" <<'SESSION'
# Kitty startup session - shell-bootstrap
# Just a clean zsh terminal

new_tab home
layout splits
cd ~
launch --title main zsh
SESSION

  log "Kitty configured. Use 'kitty' for normal or 'kitty --session ~/.config/kitty/dev.session' for dev layout"
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

  # Search
  { on = ["/"], run = "find --smart", desc = "Find" },
  { on = ["n"], run = "find_arrow", desc = "Next match" },
  { on = ["N"], run = "find_arrow --previous", desc = "Previous match" },

  # Sorting
  { on = ["o", "n"], run = "sort natural --dir-first", desc = "Sort by name" },
  { on = ["o", "s"], run = "sort size --dir-first --reverse", desc = "Sort by size" },
  { on = ["o", "m"], run = "sort mtime --dir-first --reverse", desc = "Sort by modified" },

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

# Kitty terminal shortcuts
if command -v kitty >/dev/null 2>&1; then
  alias kdev='kitty --session ~/.config/kitty/dev.session'
  alias icat='kitty +kitten icat'  # Display images in terminal
  alias kdiff='kitty +kitten diff' # Better diff viewer
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
  install_kitty
  install_yazi
  install_starship
  install_pet
  install_zsh_plugins
  install_claude_code

  configure_starship
  configure_atuin
  configure_git
  configure_pet
  configure_kitty
  configure_yazi
  configure_claude_code

  write_bootstrap_zshrc
  wire_user_shell_rc_files
  try_set_default_shell_zsh
  install_readme_locally

  print_next_steps
}
main "$@"
