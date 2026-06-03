import httpx


async def check_http(
    host: str,
    url: str,
    expect_status: int = 200,
    timeout: int = 10,
    label: str = None,
    **kwargs,
):
    try:
        async with httpx.AsyncClient(timeout=timeout, follow_redirects=True) as client:
            response = await client.get(url)
            if response.status_code == expect_status:
                return True, f"HTTP {response.status_code}"
            return False, f"HTTP {response.status_code} (expected {expect_status})"
    except httpx.ConnectError:
        return False, f"Connection refused: {url}"
    except httpx.TimeoutException:
        return False, f"HTTP timeout after {timeout}s"
    except Exception as e:
        return False, f"HTTP error: {e}"
