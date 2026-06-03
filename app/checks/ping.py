import asyncio
import subprocess


async def check_ping(host: str, count: int = 1, timeout: int = 3, **kwargs):
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(
        None,
        lambda: subprocess.run(
            ["ping", "-c", str(count), "-W", str(timeout), host],
            capture_output=True,
        ),
    )
    if result.returncode == 0:
        return True, "Ping OK"
    return False, "Ping failed: host unreachable"
