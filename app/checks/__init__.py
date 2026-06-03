from ..config import CheckConfig


async def run_check(host: str, check: CheckConfig):
    if check.type == "ping":
        from .ping import check_ping
        return await check_ping(host, **check.params)
    if check.type == "http":
        from .http import check_http
        return await check_http(host, **check.params)
    if check.type == "tcp":
        from .tcp import check_tcp
        return await check_tcp(host, **check.params)
    if check.type == "ssh_metrics":
        from .ssh_metrics import check_ssh_metrics
        return await check_ssh_metrics(host, **check.params)
    if check.type == "snmp":
        from .snmp import check_snmp
        return await check_snmp(host, **check.params)
    return False, f"Unknown check type: {check.type}"
