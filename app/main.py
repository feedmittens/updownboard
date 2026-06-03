import asyncio
import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse, PlainTextResponse
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


@asynccontextmanager
async def lifespan(app: FastAPI):
    config = load_config(CONFIG_PATH)
    state_store.history_limit = config.history_limit
    settings = load_settings()
    notifier = Notifier(settings)
    monitor = Monitor(config, state_store, notifier)
    task = asyncio.create_task(monitor.run())
    yield
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass


app = FastAPI(title="UpDownBoard", version="0.2.0", lifespan=lifespan)
app.mount("/static", StaticFiles(directory=_STATIC), name="static")


@app.get("/", response_class=HTMLResponse)
async def dashboard():
    return (_STATIC / "index.html").read_text()


@app.get("/settings", response_class=HTMLResponse)
async def settings_page():
    return (_STATIC / "settings.html").read_text()


@app.get("/api/systems")
async def get_systems():
    return state_store.get_all_states()


@app.get("/api/settings")
async def get_settings():
    return sanitize_for_api(load_settings())


@app.post("/api/settings")
async def post_settings(request: Request):
    incoming = await request.json()
    existing = load_settings()
    merged = merge_from_api(existing, incoming)
    save_settings(merged)
    return sanitize_for_api(merged)


@app.post("/api/settings/test")
async def test_notification(request: Request):
    body = await request.json()
    to_address = body.get("to_address", "").strip()
    if not to_address:
        raise HTTPException(status_code=400, detail="to_address is required")
    settings = load_settings()
    notifier = Notifier(settings)
    try:
        notifier.send_test(to_address)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"SMTP error: {e}")
    return {"ok": True}


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
            from_s = e["from_state"] or "UNKNOWN"
            lines.append(f"  [{e['timestamp']}] {e['system']}: {from_s} -> {e['to_state']} ({e['reason']})")
    else:
        lines.append("  None yet.")

    return "\n".join(lines) + "\n"
