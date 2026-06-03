import asyncio
import base64
import json
from pathlib import Path

try:
    import paramiko
    PARAMIKO_AVAILABLE = True
except ImportError:
    PARAMIKO_AVAILABLE = False

# Runs on the remote host via python3 — no external deps required there
_METRICS_SCRIPT = """
import json, os, shutil
load = float(open('/proc/loadavg').read().split()[0])
cpus = len([l for l in open('/proc/cpuinfo') if l.startswith('processor')])
cpu_pct = round(load * 100 / max(cpus, 1))
meminfo = {}
for line in open('/proc/meminfo'):
    k, v = line.split(':', 1)
    meminfo[k.strip()] = int(v.split()[0])
mem_total = meminfo.get('MemTotal', 1)
mem_avail = meminfo.get('MemAvailable', 0)
mem_pct = round((mem_total - mem_avail) * 100 / mem_total)
disk = shutil.disk_usage('/')
disk_pct = round(disk.used * 100 / disk.total)
print(json.dumps({'cpu': cpu_pct, 'mem': mem_pct, 'disk': disk_pct}))
"""


async def check_ssh_metrics(
    host: str,
    username: str,
    key_file: str,
    thresholds: dict = None,
    port: int = 22,
    **kwargs,
):
    if not PARAMIKO_AVAILABLE:
        return False, "paramiko not installed"

    thresholds = thresholds or {}
    cpu_max = thresholds.get("cpu_percent", 90)
    mem_max = thresholds.get("memory_percent", 90)
    disk_max = thresholds.get("disk_percent", 85)

    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(
        None, _run_ssh, host, port, username, key_file, cpu_max, mem_max, disk_max
    )


def _run_ssh(host, port, username, key_file, cpu_max, mem_max, disk_max):
    try:
        client = paramiko.SSHClient()
        client.load_system_host_keys()
        client.set_missing_host_key_policy(paramiko.RejectPolicy())
        client.connect(
            host,
            port=port,
            username=username,
            key_filename=str(Path(key_file).expanduser()),
            timeout=10,
        )

        encoded = base64.b64encode(_METRICS_SCRIPT.strip().encode()).decode()
        cmd = f"echo {encoded} | base64 -d | python3"
        _, stdout, stderr = client.exec_command(cmd, timeout=20)  # nosec B601 — cmd is a hardcoded base64-encoded static script
        out = stdout.read().decode().strip()
        client.close()

        metrics = json.loads(out)
        failures = []
        if metrics["cpu"] > cpu_max:
            failures.append(f"CPU {metrics['cpu']}% > {cpu_max}%")
        if metrics["mem"] > mem_max:
            failures.append(f"Memory {metrics['mem']}% > {mem_max}%")
        if metrics["disk"] > disk_max:
            failures.append(f"Disk {metrics['disk']}% > {disk_max}%")

        if failures:
            return False, "; ".join(failures)
        return True, f"CPU {metrics['cpu']}% Mem {metrics['mem']}% Disk {metrics['disk']}%"

    except json.JSONDecodeError:
        return False, "Failed to parse metrics — is python3 installed on the remote host?"
    except Exception as e:
        return False, f"SSH error: {e}"
