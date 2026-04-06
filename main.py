from __future__ import annotations
import os

from datetime import datetime
from typing import Any

from fastapi import FastAPI, Header, HTTPException, Query
from pydantic import BaseModel, Field

from config import settings
from providers.rcon_sender import send_rcon_command
from providers.link_results_writer import append_link_result_queue
from providers.logs_reader import list_available_log_dates, list_logs_by_date
from providers.players_reader import get_players_online
from providers.system_reader import (
    get_agent_info,
    get_agent_uptime,
    get_server_status,
    get_sources_debug,
)
from providers.telemetry_reader import (
    ack_telemetry_events,
    get_telemetry_debug,
    get_telemetry_pending,
)

app = FastAPI(title="PZ Server Agent", version="2.1.0")


class TelemetryAckBody(BaseModel):
    event_ids: list[str] = Field(default_factory=list)


class RedeemActionBody(BaseModel):
    request_id: str
    discord_id: int
    steam_id: str | None = None
    username: str | None = None
    redeem_type: str
    payload: dict[str, Any] = Field(default_factory=dict)


class LinkResultBody(BaseModel):
    event_id: str | None = None
    discord_id: int | None = None
    steam_id: str | None = None
    code: str | None = None
    linked: bool = False
    message: str = ""
    username: str | None = None
    display_name: str | None = None
    character_name: str | None = None
    server_id: str | None = None
    extra: dict[str, Any] = Field(default_factory=dict)


def require_api_key(x_api_key: str | None):
    if not x_api_key or x_api_key != settings.API_KEY:
        raise HTTPException(status_code=401, detail="Invalid or missing API key")


@app.post("/actions/redeem")
async def actions_redeem(body: RedeemActionBody, x_api_key: str | None = Header(default=None)):
    require_api_key(x_api_key)

    redeem_type = str(body.redeem_type or "").strip().lower()
    request_id = str(body.request_id or "").strip()

    if not request_id:
        return {
            "ok": False,
            "status": "failed",
            "request_id": "",
            "message": "request_id ausente",
            "time": datetime.now().isoformat(),
        }

    # Lógica para Resgate de ITEM
    if redeem_type == "item":
        item_id = str(body.payload.get("item_id") or "").strip()

        if not body.username:
            return {
                "ok": False,
                "status": "failed",
                "request_id": request_id,
                "message": "username ausente",
                "time": datetime.now().isoformat(),
            }

        if not item_id:
            return {
                "ok": False,
                "status": "failed",
                "request_id": request_id,
                "message": "item_id ausente",
                "time": datetime.now().isoformat(),
            }

        # Comando nativo do Zomboid: additem "username" "module.item"
        comando_rcon = f'additem "{body.username}" "{item_id}"'
        result = await send_rcon_command(comando_rcon)

        return {
            "ok": result.get("ok", False),
            "status": result.get("status", "failed"),
            "request_id": request_id,
            "redeem_type": redeem_type,
            "steam_id": body.steam_id,
            "username": body.username or "",
            "message": "Ação de item executada via RCON",
            "result": result,
            "time": datetime.now().isoformat(),
        }

    # Lógica para Resgate de VEÍCULO
    elif redeem_type == "veiculo":
        item_id = str(body.payload.get("item_id") or "").strip()

        if not body.username:
            return {
                "ok": False,
                "status": "failed",
                "request_id": request_id,
                "message": "username ausente",
                "time": datetime.now().isoformat(),
            }

        if not item_id:
            return {
                "ok": False,
                "status": "failed",
                "request_id": request_id,
                "message": "item_id (id do veículo) ausente",
                "time": datetime.now().isoformat(),
            }

        # Comando nativo do Zomboid: addvehicle "username" "vehiclename"
        comando_rcon = f'addvehicle "{body.username}" "{item_id}"'
        result = await send_rcon_command(comando_rcon)

        return {
            "ok": result.get("ok", False),
            "status": result.get("status", "failed"),
            "request_id": request_id,
            "redeem_type": redeem_type,
            "steam_id": body.steam_id,
            "username": body.username or "",
            "message": "Ação de veículo executada via RCON",
            "result": result,
            "time": datetime.now().isoformat(),
        }

    return {
        "ok": False,
        "status": "failed",
        "request_id": request_id,
        "message": f"redeem_type não suportado ainda: {redeem_type}",
        "time": datetime.now().isoformat(),
    }


@app.post("/link/result")
def link_result(body: LinkResultBody, x_api_key: str | None = Header(default=None)):
    require_api_key(x_api_key)

    result = append_link_result_queue(
        {
            "event_id": body.event_id,
            "discord_id": body.discord_id,
            "steam_id": body.steam_id,
            "code": body.code,
            "linked": bool(body.linked),
            "message": str(body.message or ""),
            "username": body.username,
            "display_name": body.display_name,
            "character_name": body.character_name,
            "server_id": body.server_id,
            "extra": body.extra or {},
        }
    )

    # Inserção no arquivo de texto para o Mod Lua ler (Inbox)
    username = body.username or ""
    linked_str = "1" if body.linked else "0"
    message = str(body.message or "").replace("\n", " ")

    inbox_path = os.path.join(settings.LUA_DIR, "doomtelemetry_inbox.txt")

    try:
        with open(inbox_path, "a", encoding="utf-8") as f:
            f.write(f"{username}|{linked_str}|{message}\n")
    except Exception as e:
        print(f"[ERRO INBOX] Falha ao escrever no arquivo txt: {e}")

    return {
        "ok": result.get("ok", False),
        "status": result.get("status", "failed"),
        "message": "Resultado de vínculo enviado para a fila do servidor e Inbox",
        "result": result,
        "time": datetime.now().isoformat(),
    }


@app.get("/")
def root():
    return {
        "service": "pz-server-agent",
        "status": "online",
        "version": "2.1.0",
        "docs": "/docs",
    }


@app.get("/health")
def health(x_api_key: str | None = Header(default=None)):
    require_api_key(x_api_key)
    return {
        "ok": True,
        "service": "pz-server-agent",
        "status": "online",
        "version": "2.1.0",
        "time": datetime.now().isoformat(),
    }


@app.get("/server/info")
def server_info(x_api_key: str | None = Header(default=None)):
    require_api_key(x_api_key)
    return get_agent_info()


@app.get("/server/status")
def server_status(x_api_key: str | None = Header(default=None)):
    require_api_key(x_api_key)
    return get_server_status()


@app.get("/server/uptime")
def server_uptime(x_api_key: str | None = Header(default=None)):
    require_api_key(x_api_key)
    return get_agent_uptime()


@app.get("/players/online")
def players_online(x_api_key: str | None = Header(default=None)):
    require_api_key(x_api_key)
    return get_players_online()


@app.get("/debug/sources")
def debug_sources(x_api_key: str | None = Header(default=None)):
    require_api_key(x_api_key)
    return get_sources_debug()


@app.get("/logs/dates")
def logs_dates(x_api_key: str | None = Header(default=None)):
    require_api_key(x_api_key)
    return list_available_log_dates()


@app.get("/logs/list")
def logs_list(
    x_api_key: str | None = Header(default=None),
    date: str = Query(..., description="Formato YYYY-MM-DD"),
):
    require_api_key(x_api_key)
    return list_logs_by_date(date)


@app.get("/telemetry/pending")
def telemetry_pending(
    limit: int = Query(100, ge=1, le=1000),
    x_api_key: str | None = Header(default=None),
):
    require_api_key(x_api_key)
    return get_telemetry_pending(limit=limit)


@app.post("/telemetry/ack")
def telemetry_ack(
    body: TelemetryAckBody,
    x_api_key: str | None = Header(default=None),
):
    require_api_key(x_api_key)
    return ack_telemetry_events(body.event_ids)


@app.get("/telemetry/debug")
def telemetry_debug(x_api_key: str | None = Header(default=None)):
    require_api_key(x_api_key)
    return get_telemetry_debug()
