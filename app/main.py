import asyncio
import logging
from contextlib import asynccontextmanager
from pathlib import Path

import yaml
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, PlainTextResponse
from fastapi.staticfiles import StaticFiles

from .config import load_config
from .monitor import Monitor
from .notifications import Notifier
from .settings_store import load as load_settings, merge_from_api, sanitize_for_api, save as save_settings
from .state import StateStore

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-8s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

CONFIG_PATH = "config.yaml"
_STATIC = Path(__file__).parent / "static"

state_store = StateStore()
_monitor_task: asyncio.Task | None = None
_monitor_lock = asyncio.Lock()


async def _start_monitor():
    global _monitor_task
    config = load_config(CONFIG_PATH)
    state_store.history_limit = config.history_limit
    state_store.remove_stale({s.name for s in config.systems})
    notifier = Notifier(load_settings())
    monitor = Monitor(config, state_store, notifier)
    _monitor_task = asyncio.create_task(monitor.run())


async def _reload_monitor():
    global _monitor_task
    async with _monitor_lock:
        if _monitor_task and not _monitor_task.done():
            _monitor_task.cancel()
            try:
                await _monitor_task
            except asyncio.CancelledError:
                pass
        await _start_monitor()


@asynccontextmanager
async def lifespan(app: FastAPI):
    await _start_monitor()
    yield
    if _monitor_task:
        _monitor_task.cancel()
        try:
            await _monitor_task
        except asyncio.CancelledError:
            pass


app = FastAPI(title="UpDownBoard", version="0.2.0", lifespan=lifespan)
app.mount("/static", StaticFiles(directory=_STATIC), name="static")


# ── Pages ────────────────────────────────────────────────────────────────────────

@app.get("/", response_class=HTMLResponse)
async def dashboard():
    return (_STATIC / "index.html").read_text()


@app.get("/settings", response_class=HTMLResponse)
async def settings_page():
    return (_STATIC / "settings.html").read_text()


@app.get("/config", response_class=HTMLResponse)
async def config_page():
    return (_STATIC / "config.html").read_text()


# ── Systems (read-only state) ─────────────────────────────────────────────────────

@app.get("/api/systems")
async def get_systems():
    return state_store.get_all_states()


# ── Config (read/write with hot-reload) ──────────────────────────────────────────

def _read_raw_config() -> dict:
    path = Path(CONFIG_PATH)
    if not path.exists():
        return {"settings": {"poll_interval": 30, "history_limit": 500}, "systems": []}
    return yaml.safe_load(path.read_text()) or {}


def _write_raw_config(data: dict):
    # Write directly — config.yaml may be a bind-mount so cross-fs atomic
    # rename is not possible; the file is small and writes are serialised
    # by the API layer anyway.
    Path(CONFIG_PATH).write_text(yaml.dump(data, default_flow_style=False, allow_unicode=True))


@app.get("/api/config")
async def get_config():
    return _read_raw_config()


@app.post("/api/config")
async def post_config(request: Request):
    incoming = await request.json()

    # Minimal validation
    if "systems" not in incoming:
        raise HTTPException(status_code=400, detail="Missing 'systems' key")
    if not isinstance(incoming["systems"], list):
        raise HTTPException(status_code=400, detail="'systems' must be a list")
    for i, s in enumerate(incoming["systems"]):
        if not s.get("name", "").strip():
            raise HTTPException(status_code=400, detail=f"System {i}: name is required")
        if not s.get("host", "").strip():
            raise HTTPException(status_code=400, detail=f"System '{s.get('name')}': host is required")

    _write_raw_config(incoming)
    logging.getLogger(__name__).info("Config updated via web — reloading monitor")
    await _reload_monitor()
    return {"ok": True, "systems": len(incoming["systems"])}


# ── Notification settings ─────────────────────────────────────────────────────────

@app.get("/api/settings")
async def get_settings():
    return sanitize_for_api(load_settings())


@app.post("/api/settings")
async def post_settings(request: Request):
    incoming = await request.json()
    merged = merge_from_api(load_settings(), incoming)
    save_settings(merged)
    return sanitize_for_api(merged)


@app.post("/api/settings/test")
async def test_notification(request: Request):
    body = await request.json()
    to_address = body.get("to_address", "").strip()
    if not to_address:
        raise HTTPException(status_code=400, detail="to_address is required")
    try:
        Notifier(load_settings()).send_test(to_address)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"SMTP error: {e}")
    return {"ok": True}


# ── Plain-text status ─────────────────────────────────────────────────────────────

@app.get("/status", response_class=PlainTextResponse)
async def status_text():
    current = state_store.get_all_states()
    events = state_store.get_recent_events(limit=200)

    lines = ["UpDownBoard Status", "=" * 40, ""]
    lines.append("CURRENT STATE:")
    if current:
        for name, data in sorted(current.items()):
            lines.append(f"  {data['state']:<7}  {name}")
    else:
        lines.append("  No systems configured.")

    lines += ["", "RECENT STATE CHANGES:"]
    if events:
        for e in events:
            lines.append(f"  [{e['timestamp']}] {e['system']}: {e['from_state'] or 'UNKNOWN'} -> {e['to_state']} ({e['reason']})")
    else:
        lines.append("  None yet.")

    return "\n".join(lines) + "\n"
