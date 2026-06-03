# UpDownBoard

A lightweight network monitoring dashboard. Each system gets a GREEN or RED tile. Click a RED tile to see what broke.

**Version: 0.1.0**

---

## Features

- **Dashboard** — responsive grid of RED/GREEN status tiles, refreshes every 15 seconds
- **Click to diagnose** — click any RED tile to see exactly which check failed and why
- **Status feed** — `/status` returns plain text: current state + state-change history (useful on a secondary monitor or `watch curl`)
- **Configurable checks** per system:
  - `ping` — ICMP reachability
  - `http` — GET request with configurable expected status code
  - `tcp` — TCP port open check
  - `ssh_metrics` — CPU, memory, and disk usage via SSH (Linux hosts, key auth)
  - `snmp` — OID poll (network gear, Linux, Windows with SNMP enabled)
- **YAML config** — add/remove systems by editing `config.yaml` and restarting
- **SQLite history** — state changes persisted locally, no external DB required
- **Systemd-managed** — ships with a service unit and a one-shot LXC setup script

---

## Quick Start (local / dev)

```bash
git clone https://github.com/feedmittens/updownboard.git
cd updownboard

python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

cp config.example.yaml config.yaml
# Edit config.yaml to add your systems

uvicorn app.main:app --host 0.0.0.0 --port 8080
```

Open `http://localhost:8080` — the dashboard is the landing page.

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
- On Python 3.12+, install `pysnmp-lextudio` instead of `pysnmp` if SNMP checks fail to import

---

## URLs

| URL | Description |
|-----|-------------|
| `/` | Dashboard — RED/GREEN tile grid |
| `/status` | Plain text: current state + recent changes (good for `watch curl http://host:8080/status`) |
| `/api/systems` | JSON: current state of all systems |

---

## LXC Deployment (Proxmox)

1. Create a Debian or Ubuntu LXC container in Proxmox
2. SSH in as root and run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/feedmittens/updownboard/main/deploy/setup.sh)
```

3. Edit `/opt/updownboard/config.yaml`
4. `systemctl start updownboard`

The service runs on port **8080**. To check logs: `journalctl -u updownboard -f`

### SSH key setup for `ssh_metrics`

The service runs as the `updownboard` system user. Set up key auth from that user to any hosts you want to monitor with `ssh_metrics`:

```bash
# On the UpDownBoard LXC:
sudo -u updownboard ssh-keygen -t ed25519 -f /home/updownboard/.ssh/id_ed25519 -N ""
sudo -u updownboard cat /home/updownboard/.ssh/id_ed25519.pub

# Append that public key to ~/.ssh/authorized_keys on each monitored host
# Use a dedicated low-privilege user on the monitored hosts (e.g., "monitor")
```

In `config.yaml`, set `key_file: "/home/updownboard/.ssh/id_ed25519"`.

---

## Development

```bash
# Install deps
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# Run with auto-reload
uvicorn app.main:app --reload --port 8080
```

No test suite yet — tracked in TODO below.

---

## TODO

- [ ] Tests: smoke tests for each check type
- [ ] UI: in-app config editor (add/edit/remove systems without restarting)
- [ ] Config: API endpoint to POST a new config and trigger reload (no restart)
- [ ] Notifications: optional webhook/email on state change
- [ ] SNMP v3 support
- [ ] Windows: WMI metrics check (CPU/mem/disk without SSH)

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

---

## License

MIT
