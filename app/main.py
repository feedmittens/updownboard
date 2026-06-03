import asyncio
import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, JSONResponse, PlainTextResponse
from fastapi.staticfiles import StaticFiles

from .config import load_config
from .monitor import Monitor
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
    monitor = Monitor(config, state_store)
    task = asyncio.create_task(monitor.run())
    yield
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass


app = FastAPI(title="UpDownBoard", version="0.1.0", lifespan=lifespan)
app.mount("/static", StaticFiles(directory=_STATIC), name="static")


@app.get("/", response_class=HTMLResponse)
async def dashboard():
    return (_STATIC / "index.html").read_text()


@app.get("/api/systems")
async def get_systems():
    return state_store.get_all_states()


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
