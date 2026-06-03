#!/usr/bin/env bash
# UpDownBoard LXC setup script
# Run as root on a fresh Debian/Ubuntu LXC container
set -euo pipefail

REPO="https://github.com/feedmittens/updownboard.git"
INSTALL_DIR="/opt/updownboard"
SVC_USER="updownboard"

echo "=== UpDownBoard Setup ==="
echo "Target: ${INSTALL_DIR}"

apt-get update -qq
apt-get install -y --no-install-recommends \
  python3 python3-pip python3-venv git iputils-ping

# Create a system user with no shell login
if ! id "${SVC_USER}" &>/dev/null; then
  useradd -r -m -d /home/${SVC_USER} -s /usr/sbin/nologin "${SVC_USER}"
  echo "Created user: ${SVC_USER}"
fi

# Clone or pull
if [ -d "${INSTALL_DIR}/.git" ]; then
  echo "Updating existing checkout..."
  git -C "${INSTALL_DIR}" pull --ff-only
else
  git clone "${REPO}" "${INSTALL_DIR}"
fi

chown -R "${SVC_USER}:${SVC_USER}" "${INSTALL_DIR}"

# Virtualenv + deps
echo "Installing Python dependencies..."
sudo -u "${SVC_USER}" python3 -m venv "${INSTALL_DIR}/venv"
sudo -u "${SVC_USER}" "${INSTALL_DIR}/venv/bin/pip" install -q --upgrade pip
sudo -u "${SVC_USER}" "${INSTALL_DIR}/venv/bin/pip" install -q -r "${INSTALL_DIR}/requirements.txt"

# Config
if [ ! -f "${INSTALL_DIR}/config.yaml" ]; then
  cp "${INSTALL_DIR}/config.example.yaml" "${INSTALL_DIR}/config.yaml"
  chown "${SVC_USER}:${SVC_USER}" "${INSTALL_DIR}/config.yaml"
  echo ""
  echo "  config.yaml created from example."
  echo "  Edit ${INSTALL_DIR}/config.yaml before starting the service."
fi

# Systemd
cp "${INSTALL_DIR}/deploy/updownboard.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable updownboard

echo ""
echo "=== Setup complete ==="
echo "  1. Edit ${INSTALL_DIR}/config.yaml"
echo "  2. systemctl start updownboard"
echo "  3. Open http://<this-host>:8080"
