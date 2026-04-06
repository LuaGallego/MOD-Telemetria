from __future__ import annotations

import json
import os
from datetime import datetime

from config import settings


def _ensure_parent_dir(path: str) -> None:
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)


def append_link_result_queue(result_data: dict) -> dict:
    path = settings.DOOM_LINK_RESULTS_QUEUE_FILE
    if not path:
        return {
            "ok": False,
            "status": "config_error",
            "message": "DOOM_LINK_RESULTS_QUEUE_FILE não configurado",
            "time": datetime.now().isoformat(),
        }

    _ensure_parent_dir(path)

    payload = {
        **result_data,
        "queued_at": datetime.now().isoformat(),
    }

    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False) + "\n")

    return {
        "ok": True,
        "status": "queued",
        "queue_file": path,
        "result": payload,
        "time": datetime.now().isoformat(),
    }
