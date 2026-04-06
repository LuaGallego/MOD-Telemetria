from __future__ import annotations

import json
import os
from datetime import datetime
from typing import Any

from config import settings


def _ensure_parent_dir(path: str) -> None:
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)


def _safe_int(value: Any, default: int | None = None) -> int | None:
    if value is None:
        return default
    try:
        return int(value)
    except Exception:
        return default


def _safe_float(value: Any, default: float | None = None) -> float | None:
    if value is None:
        return default
    try:
        return float(value)
    except Exception:
        return default


def _load_acked_ids() -> set[str]:
    path = settings.DOOMTELEMETRY_ACK_FILE

    if not path or not os.path.isfile(path):
        return set()

    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)

        ids = data.get("acked_ids", [])
        return {str(x).strip() for x in ids if str(x).strip()}
    except Exception:
        return set()


def _save_acked_ids(acked_ids: set[str]) -> None:
    path = settings.DOOMTELEMETRY_ACK_FILE
    if not path:
        return

    _ensure_parent_dir(path)

    payload = {
        "acked_ids": sorted(str(x).strip() for x in acked_ids if str(x).strip()),
        "updated_at": datetime.now().isoformat(),
    }

    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)


def _dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _build_meta(line_no: int) -> dict[str, Any]:
    return {
        "line": line_no,
        "source": "doomtelemetry_queue.jsonl",
    }


def _normalize_event(obj: dict[str, Any], line_no: int) -> dict[str, Any]:
    obj = _dict(obj)

    raw_payload = _dict(obj.get("payload"))
    raw_player = _dict(obj.get("player"))

    event_type = str(obj.get("event_type") or "unknown").strip().lower()

    event_id = str(obj.get("event_id") or "").strip()
    ts = obj.get("ts")
    if ts is None:
        ts = obj.get("server_timestamp")
    if ts is None:
        ts = obj.get("timestamp")
    ts = _safe_float(ts)

    steam_id = (
        str(raw_payload.get("steam_id") or "").strip()
        or str(raw_player.get("steam_id") or "").strip()
        or str(obj.get("steam_id") or "").strip()
    )

    username = (
        raw_payload.get("username")
        if raw_payload.get("username") is not None
        else raw_player.get("username")
    )
    if username is None:
        username = obj.get("username")

    display_name = (
        raw_payload.get("display_name")
        if raw_payload.get("display_name") is not None
        else raw_player.get("display_name")
    )
    if display_name is None:
        display_name = obj.get("display_name")

    character_name = (
        raw_payload.get("character_name")
        if raw_payload.get("character_name") is not None
        else raw_player.get("character_name")
    )
    if character_name is None:
        character_name = obj.get("character_name")

    online_id = raw_payload.get("online_id")
    if online_id is None:
        online_id = raw_player.get("online_id")
    if online_id is None:
        online_id = obj.get("online_id")
    online_id = _safe_int(online_id)

    if not event_id:
        fallback_ts = ts if ts is not None else "no_ts"
        event_id = f"{event_type}:{steam_id}:{username or ''}:{character_name or ''}:{fallback_ts}:{line_no}"

    merged_payload = dict(raw_payload)

    if steam_id and "steam_id" not in merged_payload:
        merged_payload["steam_id"] = steam_id
    if username is not None and "username" not in merged_payload:
        merged_payload["username"] = username
    if display_name is not None and "display_name" not in merged_payload:
        merged_payload["display_name"] = display_name
    if character_name is not None and "character_name" not in merged_payload:
        merged_payload["character_name"] = character_name
    if online_id is not None and "online_id" not in merged_payload:
        merged_payload["online_id"] = online_id

    reserved_root_keys = {
        "event_id",
        "event_type",
        "schema_version",
        "source",
        "server_id",
        "mod_version",
        "timestamp",
        "server_timestamp",
        "payload",
        "player",
    }

    for key, value in obj.items():
        if key not in reserved_root_keys and key not in merged_payload:
            merged_payload[key] = value

    player_block = {
        "steam_id": steam_id,
        "username": username,
        "display_name": display_name,
        "character_name": character_name,
        "online_id": online_id,
        "player_id": raw_player.get("player_id"),
    }

    return {
        "event_id": event_id,
        "event_type": event_type,
        "ts": ts,
        "server_id": obj.get("server_id"),
        "schema_version": obj.get("schema_version"),
        "mod_version": obj.get("mod_version"),
        "source": obj.get("source"),
        "player": player_block,
        "payload": merged_payload,
        "meta": _build_meta(line_no),
        "raw": obj,
    }


def _read_queue_events() -> list[dict[str, Any]]:
    path = settings.DOOMTELEMETRY_QUEUE_FILE

    if not path or not os.path.isfile(path):
        return []

    events: list[dict[str, Any]] = []

    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for line_no, line in enumerate(f, start=1):
                raw = line.strip()
                if not raw:
                    continue

                try:
                    obj = json.loads(raw)
                except Exception:
                    events.append(
                        {
                            "event_id": f"invalid_json_line_{line_no}",
                            "event_type": "invalid_json",
                            "ts": None,
                            "server_id": None,
                            "schema_version": None,
                            "mod_version": None,
                            "source": "doomtelemetry_queue.jsonl",
                            "player": {},
                            "payload": {
                                "raw": raw,
                                "line_no": line_no,
                            },
                            "meta": _build_meta(line_no),
                            "raw": {"raw": raw},
                        }
                    )
                    continue

                if not isinstance(obj, dict):
                    continue

                events.append(_normalize_event(obj, line_no))

    except Exception as e:
        return [{"error": str(e)}]

    return events


def get_telemetry_pending(limit: int = 100) -> dict[str, Any]:
    rows = _read_queue_events()

    if rows and "error" in rows[0]:
        return {
            "ok": False,
            "status": "read_error",
            "message": rows[0]["error"],
            "queue_file": settings.DOOMTELEMETRY_QUEUE_FILE,
            "ack_file": settings.DOOMTELEMETRY_ACK_FILE,
            "count": 0,
            "remaining": 0,
            "events": [],
            "time": datetime.now().isoformat(),
        }

    acked = _load_acked_ids()

    pending = [
        ev
        for ev in rows
        if str(ev.get("event_id") or "").strip()
        and str(ev.get("event_id")) not in acked
    ]

    batch = pending[:limit]

    return {
        "ok": True,
        "status": "ok",
        "queue_file": settings.DOOMTELEMETRY_QUEUE_FILE,
        "ack_file": settings.DOOMTELEMETRY_ACK_FILE,
        "count": len(batch),
        "remaining": max(0, len(pending) - len(batch)),
        "events": batch,
        "time": datetime.now().isoformat(),
    }


def ack_telemetry_events(event_ids: list[str]) -> dict[str, Any]:
    cleaned_ids = [
        str(event_id).strip()
        for event_id in (event_ids or [])
        if str(event_id).strip()
    ]

    acked = _load_acked_ids()

    added = 0
    for event_id in cleaned_ids:
        if event_id not in acked:
            added += 1
        acked.add(event_id)

    _save_acked_ids(acked)

    return {
        "ok": True,
        "status": "ok",
        "acked_count": len(cleaned_ids),
        "newly_acked": added,
        "total_acked": len(acked),
        "ack_file": settings.DOOMTELEMETRY_ACK_FILE,
        "time": datetime.now().isoformat(),
    }


def get_telemetry_debug() -> dict[str, Any]:
    queue_path = settings.DOOMTELEMETRY_QUEUE_FILE
    ack_path = settings.DOOMTELEMETRY_ACK_FILE

    rows = _read_queue_events()
    acked = _load_acked_ids()

    total_events = 0 if (rows and "error" in rows[0]) else len(rows)
    pending_total = 0

    if not (rows and "error" in rows[0]):
        pending_total = sum(
            1 for ev in rows
            if str(ev.get("event_id") or "").strip() not in acked
        )

    return {
        "ok": True,
        "status": "ok",
        "paths": {
            "queue_file": queue_path,
            "ack_file": ack_path,
        },
        "exists": {
            "queue_file": bool(queue_path and os.path.isfile(queue_path)),
            "ack_file": bool(ack_path and os.path.isfile(ack_path)),
        },
        "counts": {
            "queue_events_total": total_events,
            "acked_total": len(acked),
            "pending_total": pending_total,
        },
        "time": datetime.now().isoformat(),
    }
