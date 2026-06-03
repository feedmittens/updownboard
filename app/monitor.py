import asyncio
import logging

from .checks import run_check
from .config import AppConfig, SystemConfig
from .notifications import Notifier
from .state import StateStore

logger = logging.getLogger(__name__)


class Monitor:
    def __init__(self, config: AppConfig, state: StateStore, notifier: Notifier | None = None):
        self.config = config
        self.state = state
        self.notifier = notifier

    async def run(self):
        logger.info(f"Monitor started — {len(self.config.systems)} systems, {self.config.poll_interval}s interval")
        while True:
            await self._check_all()
            await asyncio.sleep(self.config.poll_interval)

    async def _check_all(self):
        await asyncio.gather(
            *[self._check_system(s) for s in self.config.systems],
            return_exceptions=True,
        )

    async def _check_system(self, system: SystemConfig):
        failed = []
        for check in system.checks:
            try:
                success, message = await run_check(system.host, check)
                if not success:
                    failed.append({"type": check.type, "message": message})
            except Exception as e:
                failed.append({"type": check.type, "message": str(e)})

        new_state = "GREEN" if not failed else "RED"
        old_state, new_state, reason = self.state.update(system.name, new_state, failed)

        if failed:
            logger.warning(f"RED  {system.name}: {reason}")

        if self.notifier and old_state != new_state:
            loop = asyncio.get_event_loop()
            loop.run_in_executor(None, self.notifier.notify, system.name, old_state, new_state, reason)
