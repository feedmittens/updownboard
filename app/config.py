import yaml
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class CheckConfig:
    type: str
    params: dict = field(default_factory=dict)


@dataclass
class SystemConfig:
    name: str
    host: str
    checks: list = field(default_factory=list)


@dataclass
class AppConfig:
    poll_interval: int = 30
    history_limit: int = 500
    systems: list = field(default_factory=list)


def load_config(path: str) -> AppConfig:
    data = yaml.safe_load(Path(path).read_text())
    settings = data.get("settings", {})

    systems = []
    for s in data.get("systems", []):
        checks = []
        for c in s.get("checks", []):
            check_type = c["type"]
            params = {k: v for k, v in c.items() if k != "type"}
            checks.append(CheckConfig(type=check_type, params=params))
        systems.append(SystemConfig(name=s["name"], host=s["host"], checks=checks))

    return AppConfig(
        poll_interval=settings.get("poll_interval", 30),
        history_limit=settings.get("history_limit", 500),
        systems=systems,
    )
