from __future__ import annotations

import os
from dotenv import load_dotenv
from pydantic_settings import BaseSettings

load_dotenv()


def _norm(path: str | None) -> str | None:
    if not path:
        return None
    return os.path.normpath(os.path.expandvars(path))


class Settings(BaseSettings):
    API_KEY: str = os.getenv("PZ_AGENT_API_KEY", "trocar_essa_chave")

    API_HOST: str = os.getenv("API_HOST", "0.0.0.0")
    API_PORT: int = int(os.getenv("API_PORT", "9000"))
    PUBLIC_BASE_URL: str = os.getenv("PUBLIC_BASE_URL", "http://sp-18.raze.host:9000")

    ZOMBOID_ROOT: str = _norm(os.getenv("ZOMBOID_ROOT", "/home/container")) or "/home/container"
    LOGS_DIR: str = _norm(os.getenv("PZ_LOGS_DIR", "/home/container/.cache/Logs")) or "/home/container/.cache/Logs"
    LUA_DIR: str = _norm(os.getenv("PZ_LUA_DIR", "/home/container/.cache/Lua")) or "/home/container/.cache/Lua"
    SAVES_MP_DIR: str = _norm(os.getenv("PZ_SAVES_MP_DIR", "/home/container")) or "/home/container"
    SERVER_DIR: str = _norm(os.getenv("PZ_SERVER_DIR", "/home/container")) or "/home/container"

    SERVER_NAME: str = os.getenv("PZ_SERVER_NAME", "servertest")

    PLAYERS_ONLINE_FILE: str = _norm(
        os.getenv("PZ_PLAYERS_ONLINE_FILE", "/home/container/.cache/Lua/players_online")
    ) or "/home/container/.cache/Lua/players_online"

    START_SCRIPT: str | None = _norm(os.getenv("PZ_START_SCRIPT"))
    RESTART_SCRIPT: str | None = _norm(os.getenv("PZ_RESTART_SCRIPT"))

    DOOMTELEMETRY_QUEUE_FILE: str = _norm(
        os.getenv("DOOMTELEMETRY_QUEUE_FILE", "/home/container/.cache/Lua/doomtelemetry_queue.jsonl")
    ) or "/home/container/.cache/Lua/doomtelemetry_queue.jsonl"

    DOOMTELEMETRY_ACK_FILE: str = _norm(
        os.getenv("DOOMTELEMETRY_ACK_FILE", "/home/container/.cache/Lua/doomtelemetry_ack.json")
    ) or "/home/container/.cache/Lua/doomtelemetry_ack.json"

    DOOM_ACTIONS_QUEUE_FILE: str = _norm(
        os.getenv("DOOM_ACTIONS_QUEUE_FILE", "/home/container/.cache/Lua/doom_actions_queue.jsonl")
    ) or "/home/container/.cache/Lua/doom_actions_queue.jsonl"

    DOOM_LINK_RESULTS_QUEUE_FILE: str = _norm(
        os.getenv("DOOM_LINK_RESULTS_QUEUE_FILE", "/home/container/.cache/Lua/doom_link_results_queue.jsonl")
    ) or "/home/container/.cache/Lua/doom_link_results_queue.jsonl"

    PZ_RCON_HOST: str = os.getenv("PZ_RCON_HOST", "127.0.0.1")
    PZ_RCON_PORT: int = int(os.getenv("PZ_RCON_PORT", "27015"))
    PZ_RCON_PASSWORD: str = os.getenv("PZ_RCON_PASSWORD", "")


settings = Settings()
