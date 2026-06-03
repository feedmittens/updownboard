#!/usr/bin/env bash
# UpDownBoard installer — Linux
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
INSTALL_DIR="/opt/updownboard"
CONFIG_FILE="/etc/updownboard/config.yaml"
SERVICE_USER="updownboard"
SYSTEMD_UNIT="/etc/systemd/system/updownboard.service"
PORT=8080

header() {
  echo
  echo "${BOLD}${CYAN}  ╔══════════════════════════════════════════════╗${RESET}"
  echo "${BOLD}${CYAN}  ║         UpDownBoard — Linux installer        ║${RESET}"
  echo "${BOLD}${CYAN}  ║         github.com/feedmittens/updownboard   ║${RESET}"
  echo "${BOLD}${CYAN}  ╚══════════════════════════════════════════════╝${RESET}"
  echo
}

info()    { echo "  ${BLUE}→${RESET} $*"; }
ok()      { echo "  ${GREEN}✓${RESET} $*"; }
warn()    { echo "  ${YELLOW}⚠${RESET}  $*"; }
die()     { echo "  ${RED}✗${RESET}  $*" >&2; exit 1; }
section() { echo; echo "${BOLD}$*${RESET}"; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "This installer must be run as root (sudo ./install-linux.sh)"
  fi
}

# ── Deployment mode picker ───────────────────────────────────────────────────────
pick_mode() {
  section "Deployment mode"
  echo "  How do you want to run UpDownBoard?"
  echo
  echo "  ${BOLD}1)${RESET} Docker          — easiest; container managed by systemd"
  echo "  ${BOLD}2)${RESET} Standalone      — native Python venv, systemd service (no Docker)"
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
    die "Python 3 not found. Install it: apt install python3 python3-pip python3-venv  OR  dnf install python3"
  fi
  PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
  PY_MAJ=$(echo "$PY_VER" | cut -d. -f1)
  PY_MIN=$(echo "$PY_VER" | cut -d. -f2)
  if [[ $PY_MAJ -lt 3 || ($PY_MAJ -eq 3 && $PY_MIN -lt 11) ]]; then
    die "Python 3.11+ required (found $PY_VER). On Ubuntu: add-apt-repository ppa:deadsnakes/ppa && apt install python3.11"
  fi
  ok "Python $PY_VER"
}

check_docker() {
  if ! command -v docker &>/dev/null; then
    die "Docker not found. Install it: curl -fsSL https://get.docker.com | sh"
  fi
  if ! docker info &>/dev/null; then
    die "Docker daemon isn't running: systemctl start docker"
  fi
  ok "Docker $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
}

check_apache() {
  if ! command -v apache2 &>/dev/null && ! command -v httpd &>/dev/null; then
    die "Apache not found. Install it: apt install apache2  OR  dnf install httpd"
  fi
  ok "Apache found"
}

# ── Service user ─────────────────────────────────────────────────────────────────
create_user() {
  if ! id "$SERVICE_USER" &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
    ok "Created system user: $SERVICE_USER"
  else
    ok "Service user already exists: $SERVICE_USER"
  fi
}

# ── Download source ──────────────────────────────────────────────────────────────
download_source() {
  section "Downloading UpDownBoard"
  mkdir -p "$INSTALL_DIR"
  TMP=$(mktemp -d)
  info "Fetching $REPO_ZIP"
  curl -fsSL "$REPO_ZIP" -o "$TMP/updownboard.zip"
  if ! command -v unzip &>/dev/null; then
    apt-get install -y unzip 2>/dev/null || yum install -y unzip 2>/dev/null || die "unzip not found"
  fi
  unzip -q "$TMP/updownboard.zip" -d "$TMP"
  cp -r "$TMP"/updownboard-main/* "$INSTALL_DIR/"
  rm -rf "$TMP"
  ok "Installed to $INSTALL_DIR"
}

# ── Config setup ─────────────────────────────────────────────────────────────────
setup_config() {
  section "Configuration"
  mkdir -p "$(dirname "$CONFIG_FILE")"
  if [[ ! -f "$CONFIG_FILE" ]]; then
    cp "$INSTALL_DIR/config.example.yaml" "$CONFIG_FILE"
    info "Created $CONFIG_FILE from example"
    warn "Edit $CONFIG_FILE to add your systems before starting."
  else
    ok "Config already exists at $CONFIG_FILE — leaving it alone"
  fi
  ln -sf "$CONFIG_FILE" "$INSTALL_DIR/config.yaml"
  chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR" "$(dirname "$CONFIG_FILE")"
}

# ── Systemd service helpers ──────────────────────────────────────────────────────
write_systemd_unit() {
  local exec_start="$1"
  local working_dir="$2"

  cat > "$SYSTEMD_UNIT" <<UNIT
[Unit]
Description=UpDownBoard network monitoring dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=${working_dir}
ExecStart=${exec_start}
Restart=on-failure
RestartSec=5

# Allow ICMP raw sockets for ping checks
AmbientCapabilities=CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_RAW

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable updownboard
  ok "systemd unit installed and enabled"
}

# ── Docker deployment ─────────────────────────────────────────────────────────────
install_docker() {
  section "Docker deployment"
  check_docker

  cat > "$INSTALL_DIR/docker-compose.yml" <<COMPOSE
services:
  updownboard:
    build: .
    ports:
      - "${PORT}:8080"
    volumes:
      - ${CONFIG_FILE}:/app/config.yaml:ro
    cap_add:
      - NET_RAW
    restart: unless-stopped
COMPOSE
  ok "docker-compose.yml written"

  section "Building container"
  cd "$INSTALL_DIR"
  docker compose build
  ok "Image built"

  # systemd unit that manages docker compose
  cat > "$SYSTEMD_UNIT" <<UNIT
[Unit]
Description=UpDownBoard network monitoring dashboard (Docker)
After=docker.service
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=$(command -v docker) compose up
ExecStop=$(command -v docker) compose down
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable updownboard
  systemctl start updownboard
  ok "systemd service started"
  ok "Running at http://localhost:${PORT}"
}

# ── Standalone deployment ─────────────────────────────────────────────────────────
install_standalone() {
  section "Standalone deployment"
  check_python
  create_user
  download_source
  setup_config

  section "Python virtualenv"
  python3 -m venv "$INSTALL_DIR/venv"
  "$INSTALL_DIR/venv/bin/pip" install --quiet --upgrade pip
  "$INSTALL_DIR/venv/bin/pip" install --quiet -r "$INSTALL_DIR/requirements.txt"
  chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/venv"
  ok "Dependencies installed"

  section "systemd service"
  write_systemd_unit \
    "$INSTALL_DIR/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port $PORT" \
    "$INSTALL_DIR"
  systemctl start updownboard
  ok "Service started at http://localhost:${PORT}"
}

# ── Apache deployment ─────────────────────────────────────────────────────────────
install_apache() {
  section "Apache reverse proxy deployment"
  check_apache
  install_standalone

  section "Apache virtual host"
  # Detect distro Apache config location
  if [[ -d /etc/apache2/sites-available ]]; then
    VHOST_FILE="/etc/apache2/sites-available/updownboard.conf"
    a2enmod proxy proxy_http 2>/dev/null || true
  else
    VHOST_FILE="/etc/httpd/conf.d/updownboard.conf"
    # mod_proxy is usually built-in on RHEL-family
  fi

  cat > "$VHOST_FILE" <<APACHE
# UpDownBoard — reverse proxy
# Generated by install-linux.sh
<VirtualHost *:80>
    ServerName updownboard

    ProxyPreserveHost On
    ProxyPass        / http://127.0.0.1:${PORT}/
    ProxyPassReverse / http://127.0.0.1:${PORT}/

    ErrorLog  /var/log/apache2/updownboard_error.log
    CustomLog /var/log/apache2/updownboard_access.log combined
</VirtualHost>
APACHE

  if [[ -d /etc/apache2/sites-enabled ]]; then
    a2ensite updownboard 2>/dev/null || true
    systemctl reload apache2 2>/dev/null || true
  else
    systemctl reload httpd 2>/dev/null || true
  fi

  ok "Virtual host written to $VHOST_FILE"
  info "To add TLS: install certbot and run: certbot --apache -d your-hostname"
  info "To add basic auth: add AuthType Basic / AuthUserFile / Require valid-user directives"
}

# ── Main ──────────────────────────────────────────────────────────────────────────
header
require_root
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
echo "  Config:     ${CYAN}${CONFIG_FILE}${RESET}"
echo "  Logs:       ${CYAN}journalctl -u updownboard -f${RESET}"
echo
echo "  Edit config.yaml, then: systemctl restart updownboard"
echo "  Repo: ${DIM}$REPO${RESET}"
echo
