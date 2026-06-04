# UpDownBoard

[![CI](https://github.com/feedmittens/updownboard/actions/workflows/ci.yml/badge.svg)](https://github.com/feedmittens/updownboard/actions/workflows/ci.yml)
[![CodeQL](https://github.com/feedmittens/updownboard/actions/workflows/codeql.yml/badge.svg)](https://github.com/feedmittens/updownboard/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Python 3.11+](https://img.shields.io/badge/python-3.11%2B-blue.svg)](https://www.python.org/)

A lightweight network monitoring dashboard. Each system gets a GREEN or RED tile. Click a RED tile to see what broke.

**[feedmittens.github.io/updownboard](https://feedmittens.github.io/updownboard)** — project page with install instructions

**Version: 0.3.0**

---

## Quick Install

Download and run the installer for your platform — it handles Python, config, and service setup.

**Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/feedmittens/updownboard/main/install-linux.sh -o install.sh
chmod +x install.sh && ./install.sh
```

**macOS**
```bash
curl -fsSL https://raw.githubusercontent.com/feedmittens/updownboard/main/install.sh -o install.sh
chmod +x install.sh && ./install.sh
```

**Windows** (PowerShell)
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/feedmittens/updownboard/main/install.ps1" -OutFile install.ps1
.\install.ps1
```

> If scripts are blocked: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

Each installer will ask which deployment mode you want:
- **Docker** — easiest; container + auto-start service
- **Standalone** — native Python, systemd/launchd/Windows Service
- **Apache / IIS** — standalone behind a reverse proxy (TLS, auth, access logs)

---

## Features

- **Dashboard** — responsive RED/GREEN tile grid, auto-refreshes every 15 seconds
- **Click to diagnose** — expand any RED tile to see exactly which check failed and why
- **Status feed** — `/status` plain text: current state + state-change history (great with `watch curl`)
- **Configurable checks** per system:
  - `ping` — ICMP reachability
  - `http` — GET with configurable expected status code
  - `tcp` — TCP port open check
  - `ssh_metrics` — CPU load, memory, disk usage via SSH (key auth, no agent)
  - `snmp` — OID poll (routers, switches, Linux, Windows SNMP)
- **YAML config** — add/remove systems by editing `config.yaml` and restarting
- **Local history** — state changes persisted to SQLite, no external DB required

---

## Configuration

Copy `config.example.yaml` to `config.yaml` (gitignored — keep your IPs local).

```yaml
settings:
  poll_interval: 30       # seconds between check cycles
  history_limit: 500      # max state-change events kept in DB

systems:
  - name: "Router"
    host: "10.0.0.1"
    checks:
      - type: ping
      - type: snmp
        community: "public"
        oid: "1.3.6.1.2.1.1.1.0"

  - name: "Linux Server"
    host: "10.0.0.20"
    checks:
      - type: ping
      - type: tcp
        port: 22
      - type: ssh_metrics
        username: monitor
        key_file: "~/.ssh/id_rsa"
        thresholds:
          cpu_percent: 90
          memory_percent: 90
          disk_percent: 85

  - name: "Web App"
    host: "10.0.0.20"
    checks:
      - type: http
        url: "http://10.0.0.20:8080/health"
        expect_status: 200

  - name: "Windows PC"
    host: "10.0.0.30"
    checks:
      - type: ping
      - type: tcp
        port: 3389
        label: "RDP"
```

### Check reference

| Type | Required params | Optional params |
|------|----------------|-----------------|
| `ping` | — | `count` (default 1), `timeout` (default 3s) |
| `http` | `url` | `expect_status` (default 200), `timeout` (default 10s) |
| `tcp` | `port` | `timeout` (default 5s), `label` |
| `ssh_metrics` | `username`, `key_file` | `port` (default 22), `thresholds` (cpu/memory/disk %) |
| `snmp` | — | `community` (default `public`), `oid`, `port` (default 161), `timeout` |

#### `ssh_metrics` notes
- Requires SSH key auth from the UpDownBoard service user to the monitored host
- Requires `python3` on the remote host (standard on all modern Linux distros)
- CPU metric is 1-minute load average relative to CPU count — not instantaneous usage

---

## URLs

| URL | Description |
|-----|-------------|
| `/` | Dashboard — RED/GREEN tile grid |
| `/settings` | Notification settings UI (SMTP, cadence, templates) |
| `/status` | Plain text: current state + recent changes (good for `watch curl http://host:8080/status`) |
| `/api/systems` | JSON: current state of all systems |
| `/api/settings` | GET/POST notification settings |

---

## Docker (local / dev)

```bash
cp config.example.yaml config.yaml
# edit config.yaml

docker compose up -d
```

Open `http://localhost:8080`. The container needs `NET_RAW` capability (already set in `docker-compose.yml`) for ICMP ping to work.

---

## Manual / Dev Setup

```bash
git clone https://github.com/feedmittens/updownboard.git
cd updownboard

python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

cp config.example.yaml config.yaml
# edit config.yaml

uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
```

---

## LXC / Bare-Metal Deployment (Proxmox)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/feedmittens/updownboard/main/deploy/setup.sh)
```

Edit `/opt/updownboard/config.yaml`, then `systemctl start updownboard`.

### SSH key setup for `ssh_metrics`

```bash
# On the UpDownBoard host:
sudo -u updownboard ssh-keygen -t ed25519 -f /home/updownboard/.ssh/id_ed25519 -N ""
sudo -u updownboard cat /home/updownboard/.ssh/id_ed25519.pub
# Append that public key to ~/.ssh/authorized_keys on each monitored host
```

In `config.yaml`, set `key_file: "/home/updownboard/.ssh/id_ed25519"`.

---

## Contributing

PRs welcome. Please:
1. Fork and branch from `main`
2. All PRs go through the CI pipeline (security scan, linting, Trivy image scan)
3. Keep `config.yaml` out of commits — it's gitignored for a reason

---

## TODO

- [ ] Tests: smoke tests for each check type
- [ ] UI: in-app config editor (add/edit/remove systems without restarting) — in progress
- [ ] SNMP v3 support
- [ ] Windows: WMI metrics check (CPU/mem/disk without SSH)
- [ ] Webhook notifications (Slack, Teams, etc.) in addition to email

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

---

## License

MIT — see [LICENSE](LICENSE).
A [Corkscrew Consulting Group](https://www.corkscrewconsulting.net) project.
