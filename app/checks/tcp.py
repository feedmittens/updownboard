import asyncio


async def check_tcp(host: str, port: int, timeout: int = 5, label: str = None, **kwargs):
    try:
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(host, port), timeout=timeout
        )
        writer.close()
        await writer.wait_closed()
        return True, f"Port {port} open"
    except asyncio.TimeoutError:
        return False, f"Port {port} timed out"
    except ConnectionRefusedError:
        return False, f"Port {port} refused"
    except Exception as e:
        return False, f"Port {port} error: {e}"
