import os
import re
from datetime import datetime
from config import settings


DATE_PREFIX_RE = re.compile(r"^\d{4}-\d{2}-\d{2}")


def _safe_list_logs() -> list[str]:
    if not os.path.isdir(settings.LOGS_DIR):
        return []
    try:
        files = []
        for name in os.listdir(settings.LOGS_DIR):
            full = os.path.join(settings.LOGS_DIR, name)
            if os.path.isfile(full):
                files.append(name)
        return sorted(files)
    except Exception:
        return []


def list_available_log_dates() -> dict:
    files = _safe_list_logs()
    dates = sorted({name[:10] for name in files if DATE_PREFIX_RE.match(name)})

    return {
        "ok": True,
        "logs_dir": settings.LOGS_DIR,
        "dates": dates,
        "count": len(dates),
        "time": datetime.now().isoformat(),
    }


def list_logs_by_date(date_str: str) -> dict:
    files = _safe_list_logs()
    selected = [name for name in files if name.startswith(date_str)]

    return {
        "ok": True,
        "logs_dir": settings.LOGS_DIR,
        "date": date_str,
        "files": selected,
        "count": len(selected),
        "time": datetime.now().isoformat(),
    }
