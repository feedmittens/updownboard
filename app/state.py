import sqlite3
from datetime import datetime, timezone
from threading import Lock


class StateStore:
    def __init__(self, db_path: str = "updownboard.db", history_limit: int = 500):
        self.db_path = db_path
        self.history_limit = history_limit
        self._lock = Lock()
        self._current: dict = {}
        self._init_db()

    def _init_db(self):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS state_changes (
                    id        INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    system    TEXT NOT NULL,
                    from_state TEXT,
                    to_state  TEXT NOT NULL,
                    reason    TEXT
                )
            """)

    def update(self, system_name: str, new_state: str, failed_checks: list) -> tuple[str | None, str, str]:
        """Update state. Returns (old_state, new_state, reason) — old_state is None on first check."""
        reason = (
            "; ".join(f"{c['type']}: {c['message']}" for c in failed_checks)
            if failed_checks
            else "all checks passed"
        )

        with self._lock:
            old_state = self._current.get(system_name, {}).get("state")
            self._current[system_name] = {
                "state": new_state,
                "failed_checks": failed_checks,
                "last_checked": datetime.now(timezone.utc).isoformat(),
                "reason": reason,
            }

        if old_state != new_state:
            self._record_change(system_name, old_state, new_state, reason)

        return old_state, new_state, reason

    def _record_change(self, system_name: str, from_state, to_state: str, reason: str):
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
        with self._lock:
            limit = self.history_limit
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                "INSERT INTO state_changes (timestamp, system, from_state, to_state, reason) VALUES (?,?,?,?,?)",
                (ts, system_name, from_state, to_state, reason),
            )
            conn.execute(
                "DELETE FROM state_changes WHERE id NOT IN "
                "(SELECT id FROM state_changes ORDER BY id DESC LIMIT ?)",
                (int(limit),),
            )

    def remove_stale(self, active_names: set):
        """Drop in-memory state for systems no longer in the config."""
        with self._lock:
            for name in list(self._current):
                if name not in active_names:
                    del self._current[name]

    def get_all_states(self) -> dict:
        with self._lock:
            return dict(self._current)

    def get_recent_events(self, limit: int = 200) -> list:
        with sqlite3.connect(self.db_path) as conn:
            rows = conn.execute(
                "SELECT timestamp, system, from_state, to_state, reason "
                "FROM state_changes ORDER BY id DESC LIMIT ?",
                (limit,),
            ).fetchall()
        return [
            {"timestamp": r[0], "system": r[1], "from_state": r[2], "to_state": r[3], "reason": r[4]}
            for r in rows
        ]
