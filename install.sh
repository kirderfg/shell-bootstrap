#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

log() { printf '%s\n' "shell-bootstrap: $*"; }

require_cmd() { command -v "$1" >/dev/null 2>&1; }

SUDO="sudo"
if ! require_cmd sudo; then
  SUDO=""
fi

DEFAULT_ATUIN_USERNAME="fredrik-gustavsson"
DEFAULT_ATUIN_EMAIL="fredrik@thegustavssons.se"

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

append_block_once() {
  local file="$1"
  local marker_begin="$2"
  local marker_end="$3"
  local content="$4"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -qF "$marker_begin" "$file"; then
    # Replace existing managed block
    perl -0777 -i -pe "s/\Q$marker_begin\E.*?\Q$marker_end\E/$marker_begin\n$content\n$marker_end/s" "$file"
  else
    {
      echo ""
      echo "$marker_begin"
      echo "$content"
      echo "$marker_end"
    } >>"$file"
  fi
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
    git-delta || true

  # Optional (nice-to-have) packages; don't hard-fail if not present in the image
  ${SUDO} apt-get install -y yq gh || true
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

  local tag ver asset url tmpdir
  tag="$(curl -fsSL https://api.github.com/repos/starship/starship/releases/latest | jq -r .tag_name)"
  ver="${tag#v}"
  asset="starship-${ver}-${arch}-unknown-linux-gnu.tar.gz"
  url="https://github.com/starship/starship/releases/download/${tag}/${asset}"

  tmpdir="$(mktemp -d)"
  curl -fsSL "$url" -o "${tmpdir}/starship.tgz"
  tar -xzf "${tmpdir}/starship.tgz" -C "${tmpdir}"
  install -m 0755 "${tmpdir}/starship" "${BOOTSTRAP_BIN}/starship"
  rm -rf "${tmpdir}"
}

install_pet() {
  if require_cmd pet; then
    log "pet already installed."
    return
  fi
  log "Installing pet (Go)..."
  if ! require_cmd go; then
    ${SUDO} apt-get install -y golang-go
  fi
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
  "(?i)bearer\\s+[a-z0-9\\._\\-]+",
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
    log "Atuin installed. To enable sync: atuin register/login + atuin key + atuin sync"
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

  # Optional: clone private snippets repo and symlink snippet.toml
  if [[ -n "${PET_SNIPPETS_REPO:-}" && -n "${PET_SNIPPETS_TOKEN:-}" ]]; then
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
    log "Private pet repo not configured (set PET_SNIPPETS_REPO + PET_SNIPPETS_TOKEN to enable)."
  fi
}

write_bootstrap_zshrc() {
  log "Writing bootstrap zshrc fragment..."
  cat > "${BOOTSTRAP_HOME}/zshrc" <<EOF
# shell-bootstrap zsh config

# Ensure local bins are available
export PATH="${BOOTSTRAP_BIN}:\$HOME/.atuin/bin:\$PATH"

# Quality-of-life aliases for Ubuntu naming
if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
  alias bat='batcat'
fi
if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
  alias fd='fdfind'
fi

export EDITOR="\${EDITOR:-nano}"

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
    log "Attempting to set default shell to zsh (may fail in containers/Codespaces)..."
    set +e
    chsh -s "$(command -v zsh)" "$USER" >/dev/null 2>&1
    set -e
  fi
}

install_readme_locally() {
  log "Installing zsh_readme.md locally..."
  cat > "${BOOTSTRAP_SHARE}/zsh_readme.md" <<'EOF'
See the repo's zsh_readme.md for full documentation.
EOF
}

main() {
  install_apt_packages
  install_atuin
  install_starship
  install_pet
  install_zsh_plugins
  install_claude_code

  configure_starship
  configure_atuin
  configure_pet

  write_bootstrap_zshrc
  wire_user_shell_rc_files
  try_set_default_shell_zsh
  install_readme_locally

  log "Done."
  log "Open a new terminal (or run: exec zsh)."
  log "If this is your first Atuin machine: atuin register -u ${ATUIN_USERNAME} -e ${ATUIN_EMAIL}"
}
main "$@"
