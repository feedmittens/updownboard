import asyncio

try:
    from pysnmp.hlapi import (
        CommunityData,
        ContextData,
        ObjectIdentity,
        ObjectType,
        SnmpEngine,
        UdpTransportTarget,
        getCmd,
    )
    SNMP_AVAILABLE = True
except ImportError:
    SNMP_AVAILABLE = False


async def check_snmp(
    host: str,
    community: str = "public",
    oid: str = "1.3.6.1.2.1.1.1.0",
    port: int = 161,
    timeout: int = 5,
    label: str = None,
    **kwargs,
):
    if not SNMP_AVAILABLE:
        return False, "pysnmp not installed — run: pip install pysnmp"

    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, _snmp_get, host, community, oid, port, timeout)


def _snmp_get(host, community, oid, port, timeout):
    try:
        error_indication, error_status, error_index, var_binds = next(
            getCmd(
                SnmpEngine(),
                CommunityData(community, mpModel=0),  # nosec B508 — SNMPv1/v2 support is intentional
                UdpTransportTarget((host, port), timeout=timeout, retries=1),
                ContextData(),
                ObjectType(ObjectIdentity(oid)),
            )
        )

        if error_indication:
            return False, f"SNMP: {error_indication}"
        if error_status:
            return False, f"SNMP error: {error_status.prettyPrint()}"

        value = str(var_binds[0][1])
        return True, f"SNMP OK: {value[:60]}"

    except StopIteration:
        return False, "SNMP: no response"
    except Exception as e:
        return False, f"SNMP error: {e}"
