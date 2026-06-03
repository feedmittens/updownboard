import logging
import smtplib
from datetime import datetime, timezone
from email.mime.text import MIMEText

logger = logging.getLogger(__name__)


class Notifier:
    def __init__(self, settings: dict):
        self._cfg = settings.get("email", {})

    def _enabled(self) -> bool:
        return bool(self._cfg.get("enabled", False))

    def _should_send(self, old_state: str | None, new_state: str) -> bool:
        notify_on = self._cfg.get("notify_on", "both")
        if new_state == "RED" and notify_on in ("down", "both"):
            return True
        if new_state == "GREEN" and old_state == "RED" and notify_on in ("recovery", "both"):
            return True
        return False

    def notify(self, system: str, old_state: str | None, new_state: str, reason: str):
        if not self._enabled():
            return
        if not self._should_send(old_state, new_state):
            return

        cfg = self._cfg
        placeholders = {
            "system": system,
            "state": new_state,
            "reason": reason,
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC"),
        }

        subject = cfg.get("subject_template", "[{state}] {system} — UpDownBoard").format(**placeholders)
        body    = cfg.get("body_template",    "System: {system}\nState: {state}\nReason: {reason}\nTime: {timestamp}").format(**placeholders)

        to_addresses = cfg.get("to_addresses", [])
        if not to_addresses:
            logger.warning("Notifications enabled but no to_addresses configured")
            return

        msg = MIMEText(body, "plain", "utf-8")
        msg["Subject"] = subject
        msg["From"]    = cfg.get("from_address", cfg.get("smtp_user", ""))
        msg["To"]      = ", ".join(to_addresses)

        try:
            self._send(msg, to_addresses)
            logger.info(f"Notification sent: {system} → {new_state}")
        except Exception as e:
            logger.error(f"Failed to send notification for {system}: {e}")

    def _send(self, msg: MIMEText, to_addresses: list):
        cfg = self._cfg
        host     = cfg.get("smtp_host", "")
        port     = int(cfg.get("smtp_port", 587))
        use_tls  = bool(cfg.get("smtp_use_tls", True))
        user     = cfg.get("smtp_user", "")
        password = cfg.get("smtp_password", "")

        with smtplib.SMTP(host, port, timeout=10) as smtp:
            if use_tls:
                smtp.starttls()
            if user and password:
                smtp.login(user, password)
            smtp.sendmail(msg["From"], to_addresses, msg.as_string())

    def send_test(self, to_address: str):
        """Send a test email to verify SMTP settings. Raises on failure."""
        cfg = self._cfg
        msg = MIMEText("This is a test email from UpDownBoard. If you're reading this, notifications are working.", "plain", "utf-8")
        msg["Subject"] = "UpDownBoard — test notification"
        msg["From"]    = cfg.get("from_address", cfg.get("smtp_user", ""))
        msg["To"]      = to_address
        self._send(msg, [to_address])
