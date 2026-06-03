from ..config import CheckConfig


async def run_check(host: str, check: CheckConfig):
    from .ping import check_ping
    from .http import check_http
    from .tcp import check_tcp
    from .ssh_metrics import check_ssh_metrics
    from .snmp import check_snmp

    handlers = {
        "ping": check_ping,
        "http": check_http,
        "tcp": check_tcp,
        "ssh_metrics": check_ssh_metrics,
        "snmp": check_snmp,
    }
    handler = handlers.get(check.type)
    if not handler:
        return False, f"Unknown check type: {check.type}"
    return await handler(host, **check.params)
