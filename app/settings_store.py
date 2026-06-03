import copy
from pathlib import Path

import yaml

SETTINGS_PATH = "notifications.yaml"

_DEFAULTS = {
    "email": {
        "enabled": False,
        "smtp_host": "",
        "smtp_port": 587,
        "smtp_use_tls": True,
        "smtp_user": "",
        "smtp_password": "",
        "from_address": "",
        "to_addresses": [],
        "notify_on": "both",
        "subject_template": "[{state}] {system} — UpDownBoard",
        "body_template": (
            "System:    {system}\n"
            "New state: {state}\n"
            "Reason:    {reason}\n"
            "Time:      {timestamp}\n"
        ),
    }
}

_MASK = "••••••••"


def load() -> dict:
    path = Path(SETTINGS_PATH)
    if not path.exists():
        return copy.deepcopy(_DEFAULTS)
    raw = yaml.safe_load(path.read_text()) or {}
    merged = copy.deepcopy(_DEFAULTS)
    email = raw.get("email", {})
    merged["email"].update(email)
    return merged


def save(settings: dict):
    Path(SETTINGS_PATH).write_text(yaml.dump(settings, default_flow_style=False, allow_unicode=True))


def sanitize_for_api(settings: dict) -> dict:
    """Return settings safe to send to the browser — password masked."""
    out = copy.deepcopy(settings)
    if out.get("email", {}).get("smtp_password"):
        out["email"]["smtp_password"] = _MASK
    return out


def merge_from_api(existing: dict, incoming: dict) -> dict:
    """Merge browser POST back into full settings, preserving the real password if masked."""
    merged = copy.deepcopy(existing)
    email_in = incoming.get("email", {})
    for key, val in email_in.items():
        if key == "smtp_password" and val == _MASK:
            continue  # keep the stored password
        merged["email"][key] = val
    return merged
