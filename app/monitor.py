import asyncio
import logging

from .checks import run_check
from .config import AppConfig, SystemConfig
from .state import StateStore

logger = logging.getLogger(__name__)


class Monitor:
    def __init__(self, config: AppConfig, state: StateStore):
        self.config = config
        self.state = state

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
        self.state.update(system.name, new_state, failed)

        if failed:
            reasons = "; ".join(f['message'] for f in failed)
            logger.warning(f"RED  {system.name}: {reasons}")
