from __future__ import annotations

import json
import os
from datetime import datetime
from config import settings


def _ensure_parent_dir(path: str) -> None:
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)


def _extract_request_id(line: str) -> str:
    try:
        obj = json.loads(line)
        return str(obj.get("request_id") or "").strip()
    except Exception:
        return ""


def _request_id_already_exists(path: str, request_id: str) -> bool:
    if not request_id or not os.path.exists(path):
        return False

    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                existing_id = _extract_request_id(line)
                if existing_id == request_id:
                    return True
    except FileNotFoundError:
        return False

    return False


def append_action_queue(action_data: dict) -> dict:
    path = settings.DOOM_ACTIONS_QUEUE_FILE
    if not path:
        return {
            "ok": False,
            "status": "config_error",
            "message": "DOOM_ACTIONS_QUEUE_FILE não configurado",
            "time": datetime.now().isoformat(),
        }

    _ensure_parent_dir(path)

    request_id = str(action_data.get("request_id") or "").strip()
    if not request_id:
        return {
            "ok": False,
            "status": "invalid_request",
            "message": "request_id ausente",
            "time": datetime.now().isoformat(),
        }

    if _request_id_already_exists(path, request_id):
        return {
            "ok": True,
            "status": "already_queued",
            "queue_file": path,
            "action": action_data,
            "message": f"request_id {request_id} já estava na fila",
            "time": datetime.now().isoformat(),
        }

    payload = {
        **action_data,
        "queued_at": datetime.now().isoformat(),
    }

    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False) + "\n")

    return {
        "ok": True,
        "status": "queued",
        "queue_file": path,
        "action": payload,
        "time": datetime.now().isoformat(),
    }
