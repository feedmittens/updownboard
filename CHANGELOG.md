# Changelog

All notable changes to UpDownBoard are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [0.3.0] — 2026-06-03

### Added
- Email notification system: SMTP-based alerts on state changes, configurable cadence (down / recovery / both), subject + body templates
- Web settings UI at `/settings`: SMTP config, addressing, cadence picker, template editor, test-email button; password masked in API responses; settings stored in `notifications.yaml` (gitignored)
- Screenshots page on GitHub Pages (`/screenshots.html`) with HTML/CSS mockups of the dashboard, failure modal, `/status` output, and `/api/systems` JSON

### Fixed
- CI pipeline was failing on every PR due to incorrect `trivy-action` version pin and Bandit findings; all resolved:
  - `trivy-action` pinned to correct tag `v0.36.0`
  - CVE-2026-23949 (`jaraco.context`) and CVE-2026-24049 (`wheel`) patched by upgrading `pip`, `setuptools`, and `wheel` in the Docker build
  - B508 (SNMPv1/v2), B507 (paramiko AutoAddPolicy), B601 (paramiko exec_command) suppressed with `# nosec` and documented rationale
  - B608 (SQL f-string) fixed with parameterized query in `state.py`
- SSH host key policy tightened: replaced `AutoAddPolicy` with `RejectPolicy` + `load_system_host_keys()` in `ssh_metrics` check

### Changed
- CCG website link corrected to `www.corkscrewconsulting.net` across docs and README
- `StateStore.update()` now returns `(old_state, new_state, reason)` to let the monitor detect transitions without duplicating logic
- `docker-compose.yml`: `config.yaml` mount changed from `:ro` to read-write to support config editor
- `Dockerfile`: upgrades `pip`, `setuptools`, `wheel` before installing app deps

---

## [0.2.0] — 2026-06-03

### Added
- GitHub Pages landing page (`docs/`) with CCG branding, feature overview, and platform install tabs
- Installer scripts for Linux (`install-linux.sh`), macOS (`install.sh`), and Windows (`install.ps1`)
  - Each offers three deployment modes: Docker, standalone uvicorn, and reverse proxy (Apache / IIS)
  - Linux/macOS: systemd and launchd service setup included
  - Windows: NSSM-based Windows Service + IIS ARR reverse proxy config
- CI pipeline via GitHub Actions: `pip-audit`, `Bandit`, `Trivy` Docker image scan on every PR
- CodeQL SAST workflow (GitHub's static analysis, runs on push and PR to `main`)
- Dependabot config for pip dependencies and GitHub Actions version pins
- `Dockerfile` and `docker-compose.yml` for container-based deployment and local dev

### Fixed
- Crash on startup (SIGILL / exit 132) caused by `paramiko` import on ARM64 Docker builds — check-type imports are now lazy, so `ssh_metrics` is only imported when that check type is actually configured

### Changed
- README rewritten: quick-install section, deployment options, CI badges

---

## [0.1.0] — 2026-05-30

### Added
- Initial release
- Dashboard: RED/GREEN tile grid, auto-refreshes every 15 seconds
- Click any RED tile to see which checks failed and why
- Checks supported: `ping`, `http`, `tcp`, `ssh_metrics`, `snmp`
- `ssh_metrics` check: CPU (load avg), memory, and disk usage via SSH key auth
- `/status` plain-text endpoint showing current state + recent state-change history
- YAML-based configuration (`config.yaml`, documented example in `config.example.yaml`)
- SQLite state-change history (last N events, configurable)
- Systemd service unit + LXC setup script (`deploy/`)
