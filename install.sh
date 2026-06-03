#!/usr/bin/env bash
# UpDownBoard installer — macOS
# https://github.com/feedmittens/updownboard
set -euo pipefail

# ── Formatting ──────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RESET=$'\033[0m'

REPO="https://github.com/feedmittens/updownboard"
REPO_ZIP="https://github.com/feedmittens/updownboard/archive/refs/heads/main.zip"
INSTALL_DIR="$HOME/.local/share/updownboard"
CONFIG_DIR="$HOME/.config/updownboard"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/net.corkscrew-consulting.updownboard.plist"
PORT=8080

header() {
  echo
  echo "${BOLD}${CYAN}  ╔══════════════════════════════════════════════╗${RESET}"
  echo "${BOLD}${CYAN}  ║         UpDownBoard — macOS installer        ║${RESET}"
  echo "${BOLD}${CYAN}  ║         github.com/feedmittens/updownboard   ║${RESET}"
  echo "${BOLD}${CYAN}  ╚══════════════════════════════════════════════╝${RESET}"
  echo
}

info()    { echo "  ${BLUE}→${RESET} $*"; }
ok()      { echo "  ${GREEN}✓${RESET} $*"; }
warn()    { echo "  ${YELLOW}⚠${RESET}  $*"; }
die()     { echo "  ${RED}✗${RESET}  $*" >&2; exit 1; }
section() { echo; echo "${BOLD}$*${RESET}"; }

# ── Deployment mode picker ───────────────────────────────────────────────────────
pick_mode() {
  section "Deployment mode"
  echo "  How do you want to run UpDownBoard?"
  echo
  echo "  ${BOLD}1)${RESET} Docker          — easiest; container managed by launchd (starts on login)"
  echo "  ${BOLD}2)${RESET} Standalone      — native Python venv, launchd service (no Docker)"
  echo "  ${BOLD}3)${RESET} Behind Apache   — standalone + Apache reverse proxy (TLS, auth, logs)"
  echo
  while true; do
    read -rp "  Choice [1/2/3]: " MODE
    case "$MODE" in
      1) MODE=docker;     break ;;
      2) MODE=standalone; break ;;
      3) MODE=apache;     break ;;
      *) warn "Enter 1, 2, or 3." ;;
    esac
  done
}

# ── Dependency checks ────────────────────────────────────────────────────────────
check_python() {
  if ! command -v python3 &>/dev/null; then
    die "Python 3 not found. Install it from https://www.python.org/ or via Homebrew: brew install python3"
  fi
  PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
  PY_MAJ=$(echo "$PY_VER" | cut -d. -f1)
  PY_MIN=$(echo "$PY_VER" | cut -d. -f2)
  if [[ $PY_MAJ -lt 3 || ($PY_MAJ -eq 3 && $PY_MIN -lt 11) ]]; then
    die "Python 3.11+ required (found $PY_VER). Upgrade via Homebrew: brew install python3"
  fi
  ok "Python $PY_VER"
}

check_docker() {
  if ! command -v docker &>/dev/null; then
    die "Docker not found. Install Docker Desktop from https://docs.docker.com/desktop/install/mac-install/"
  fi
  if ! docker info &>/dev/null; then
    die "Docker daemon isn't running. Open Docker Desktop and try again."
  fi
  ok "Docker $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
}

check_apache() {
  if ! command -v apachectl &>/dev/null && ! command -v httpd &>/dev/null; then
    warn "Apache not found. Install via Homebrew: brew install httpd"
    warn "Or enable the built-in macOS Apache: sudo apachectl start"
    read -rp "  Continue anyway? [y/N] " yn
    [[ "${yn,,}" == "y" ]] || exit 0
  else
    ok "Apache $(apachectl -v 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo 'found')"
  fi
}

# ── Download source ──────────────────────────────────────────────────────────────
download_source() {
  section "Downloading UpDownBoard"
  mkdir -p "$INSTALL_DIR"
  TMP=$(mktemp -d)
  info "Fetching $REPO_ZIP"
  curl -fsSL "$REPO_ZIP" -o "$TMP/updownboard.zip"
  unzip -q "$TMP/updownboard.zip" -d "$TMP"
  cp -r "$TMP"/updownboard-main/* "$INSTALL_DIR/"
  rm -rf "$TMP"
  ok "Installed to $INSTALL_DIR"
}

# ── Config setup ─────────────────────────────────────────────────────────────────
setup_config() {
  section "Configuration"
  mkdir -p "$CONFIG_DIR"
  if [[ ! -f "$CONFIG_DIR/config.yaml" ]]; then
    cp "$INSTALL_DIR/config.example.yaml" "$CONFIG_DIR/config.yaml"
    info "Created $CONFIG_DIR/config.yaml from example"
    warn "Edit $CONFIG_DIR/config.yaml to add your systems before starting."
  else
    ok "Config already exists at $CONFIG_DIR/config.yaml — leaving it alone"
  fi
  # Symlink config into install dir so the app finds it
  ln -sf "$CONFIG_DIR/config.yaml" "$INSTALL_DIR/config.yaml"
}

# ── Docker deployment ─────────────────────────────────────────────────────────────
install_docker() {
  section "Docker deployment"
  check_docker

  # Write compose file pointing at the versioned image or build
  cat > "$INSTALL_DIR/docker-compose.yml" <<COMPOSE
services:
  updownboard:
    build: .
    ports:
      - "${PORT}:8080"
    volumes:
      - ${CONFIG_DIR}/config.yaml:/app/config.yaml:ro
    cap_add:
      - NET_RAW
    restart: unless-stopped
COMPOSE
  ok "docker-compose.yml written"

  section "Building container"
  cd "$INSTALL_DIR"
  docker compose build
  ok "Image built"

  section "launchd service"
  mkdir -p "$(dirname "$LAUNCHD_PLIST")"
  cat > "$LAUNCHD_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>net.corkscrew-consulting.updownboard</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/docker</string>
    <string>compose</string>
    <string>-f</string>
    <string>${INSTALL_DIR}/docker-compose.yml</string>
    <string>up</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${INSTALL_DIR}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>${HOME}/Library/Logs/updownboard.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/Library/Logs/updownboard.log</string>
</dict>
</plist>
PLIST
  launchctl load "$LAUNCHD_PLIST" 2>/dev/null || true
  ok "launchd plist installed (starts on login)"

  section "Starting UpDownBoard"
  cd "$INSTALL_DIR"
  docker compose up -d
  ok "Running at http://localhost:${PORT}"
}

# ── Standalone deployment ─────────────────────────────────────────────────────────
install_standalone() {
  section "Standalone deployment"
  check_python
  download_source
  setup_config

  section "Python virtualenv"
  python3 -m venv "$INSTALL_DIR/venv"
  "$INSTALL_DIR/venv/bin/pip" install --quiet --upgrade pip
  "$INSTALL_DIR/venv/bin/pip" install --quiet -r "$INSTALL_DIR/requirements.txt"
  ok "Dependencies installed"

  section "launchd service"
  mkdir -p "$(dirname "$LAUNCHD_PLIST")"
  cat > "$LAUNCHD_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>net.corkscrew-consulting.updownboard</string>
  <key>ProgramArguments</key>
  <array>
    <string>${INSTALL_DIR}/venv/bin/uvicorn</string>
    <string>app.main:app</string>
    <string>--host</string>
    <string>0.0.0.0</string>
    <string>--port</string>
    <string>${PORT}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${INSTALL_DIR}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${HOME}/Library/Logs/updownboard.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/Library/Logs/updownboard.log</string>
</dict>
</plist>
PLIST
  launchctl load "$LAUNCHD_PLIST" 2>/dev/null || true
  launchctl start net.corkscrew-consulting.updownboard 2>/dev/null || true
  ok "launchd service installed and started"
  ok "Running at http://localhost:${PORT}"
}

# ── Apache deployment ─────────────────────────────────────────────────────────────
install_apache() {
  section "Apache reverse proxy deployment"
  check_apache
  install_standalone

  section "Apache virtual host"
  # Homebrew httpd uses /opt/homebrew/etc/httpd/extra/
  # macOS built-in httpd uses /etc/apache2/other/
  if [[ -d /opt/homebrew/etc/httpd ]]; then
    APACHE_CONF_DIR="/opt/homebrew/etc/httpd/extra"
    APACHE_BIN="$(brew --prefix)/bin/httpd"
    APACHE_CTL="$(brew --prefix)/bin/apachectl"
  else
    APACHE_CONF_DIR="/etc/apache2/other"
    APACHE_BIN="/usr/sbin/httpd"
    APACHE_CTL="/usr/sbin/apachectl"
  fi

  VHOST_FILE="$APACHE_CONF_DIR/updownboard.conf"
  cat > "$VHOST_FILE" <<APACHE
# UpDownBoard — reverse proxy
# Generated by install.sh
<VirtualHost *:80>
    ServerName updownboard.local

    ProxyPreserveHost On
    ProxyPass        / http://127.0.0.1:${PORT}/
    ProxyPassReverse / http://127.0.0.1:${PORT}/

    ErrorLog  /var/log/apache2/updownboard_error.log
    CustomLog /var/log/apache2/updownboard_access.log combined
</VirtualHost>
APACHE

  ok "Virtual host written to $VHOST_FILE"
  warn "Make sure mod_proxy and mod_proxy_http are enabled in your Apache config."
  warn "Restart Apache to apply: sudo $APACHE_CTL restart"
  echo
  info "To add TLS: install a certificate and wrap the VirtualHost in a *:443 block"
  info "To add basic auth: add AuthType Basic / AuthUserFile / Require valid-user directives"
}

# ── Main ──────────────────────────────────────────────────────────────────────────
header
pick_mode

case "$MODE" in
  docker)
    download_source
    setup_config
    install_docker
    ;;
  standalone)
    install_standalone
    ;;
  apache)
    install_apache
    ;;
esac

echo
echo "${BOLD}${GREEN}  Done.${RESET}"
echo
echo "  Dashboard:  ${CYAN}http://localhost:${PORT}${RESET}"
echo "  Status:     ${CYAN}http://localhost:${PORT}/status${RESET}"
echo "  Config:     ${CYAN}$CONFIG_DIR/config.yaml${RESET}"
echo "  Logs:       ${CYAN}$HOME/Library/Logs/updownboard.log${RESET}"
echo
echo "  Edit config.yaml, then restart the service to pick up changes."
echo "  Repo: ${DIM}$REPO${RESET}"
echo
