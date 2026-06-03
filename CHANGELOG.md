# Changelog

All notable changes to UpDownBoard are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

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
