import os
import socket
import platform
import time
from datetime import datetime
from config import settings


AGENT_STARTED_AT = time.time()


def get_agent_info() -> dict:
    return {
        "ok": True,
        "hostname": socket.gethostname(),
        "platform": platform.platform(),
        "python_version": platform.python_version(),
        "agent_uptime_seconds": int(time.time() - AGENT_STARTED_AT),
        "time": datetime.now().isoformat(),
    }


def get_server_status() -> dict:
    """
    Status simples por enquanto:
    - verifica se as pastas principais existem
    - depois a gente melhora com processo/RCON
    """
    checks = {
        "zomboid_root_exists": os.path.isdir(settings.ZOMBOID_ROOT),
        "logs_dir_exists": os.path.isdir(settings.LOGS_DIR),
        "lua_dir_exists": os.path.isdir(settings.LUA_DIR),
        "saves_mp_dir_exists": os.path.isdir(settings.SAVES_MP_DIR),
        "server_dir_exists": os.path.isdir(settings.SERVER_DIR),
        "players_online_file_exists": os.path.isfile(settings.PLAYERS_ONLINE_FILE),
    }

    # "online" aqui significa "estrutura encontrada"
    # depois a gente troca por detecção real do processo/servidor
    status = "online" if all(
        [checks["zomboid_root_exists"], checks["lua_dir_exists"], checks["server_dir_exists"]]
    ) else "degraded"

    return {
        "ok": True,
        "status": status,
        "checks": checks,
        "server_name": settings.SERVER_NAME,
        "time": datetime.now().isoformat(),
    }


def get_agent_uptime() -> dict:
    return {
        "ok": True,
        "uptime_seconds": int(time.time() - AGENT_STARTED_AT),
        "time": datetime.now().isoformat(),
    }


def get_sources_debug() -> dict:
    def safe_listdir(path: str, limit: int = 15):
        if not os.path.isdir(path):
            return []
        try:
            items = sorted(os.listdir(path))
            return items[:limit]
        except Exception:
            return []

    return {
        "ok": True,
        "paths": {
            "zomboid_root": settings.ZOMBOID_ROOT,
            "logs_dir": settings.LOGS_DIR,
            "lua_dir": settings.LUA_DIR,
            "saves_mp_dir": settings.SAVES_MP_DIR,
            "server_dir": settings.SERVER_DIR,
            "players_online_file": settings.PLAYERS_ONLINE_FILE,
            "start_script": settings.START_SCRIPT,
            "restart_script": settings.RESTART_SCRIPT,
        },
        "exists": {
            "zomboid_root": os.path.isdir(settings.ZOMBOID_ROOT),
            "logs_dir": os.path.isdir(settings.LOGS_DIR),
            "lua_dir": os.path.isdir(settings.LUA_DIR),
            "saves_mp_dir": os.path.isdir(settings.SAVES_MP_DIR),
            "server_dir": os.path.isdir(settings.SERVER_DIR),
            "players_online_file": os.path.isfile(settings.PLAYERS_ONLINE_FILE),
            "start_script": bool(settings.START_SCRIPT and os.path.isfile(settings.START_SCRIPT)),
            "restart_script": bool(settings.RESTART_SCRIPT and os.path.isfile(settings.RESTART_SCRIPT)),
        },
        "samples": {
            "logs_dir": safe_listdir(settings.LOGS_DIR),
            "lua_dir": safe_listdir(settings.LUA_DIR),
            "saves_mp_dir": safe_listdir(settings.SAVES_MP_DIR),
            "server_dir": safe_listdir(settings.SERVER_DIR),
        },
        "time": datetime.now().isoformat(),
    }
