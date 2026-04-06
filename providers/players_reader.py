import csv
import os
from datetime import datetime
from config import settings


def _parse_csv_like(path: str) -> list[dict]:
    """
    Tenta ler arquivos tipo CSV/TSV de forma tolerante.
    Se não der pra inferir cabeçalho, retorna linhas cruas.
    """
    if not os.path.isfile(path):
        return []

    rows: list[dict] = []
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            raw = f.read().strip()

        if not raw:
            return []

        # Heurística simples de delimitador
        delimiter = "," if raw.count(",") >= raw.count(";") else ";"

        lines = raw.splitlines()
        if not lines:
            return []

        # tenta DictReader primeiro
        with open(path, "r", encoding="utf-8", errors="ignore", newline="") as f:
            reader = csv.DictReader(f, delimiter=delimiter)
            if reader.fieldnames:
                for row in reader:
                    rows.append({k: (v or "").strip() for k, v in row.items()})
                return rows

        # fallback: linhas cruas
        for idx, line in enumerate(lines, start=1):
            rows.append({"line": idx, "raw": line})

        return rows

    except Exception as e:
        return [{"error": str(e)}]


def get_players_online() -> dict:
    """
    Lê o arquivo players_online da pasta Lua (que você mostrou).
    Se não conseguir parsear, retorna conteúdo cru.
    """
    path = settings.PLAYERS_ONLINE_FILE

    if not os.path.isfile(path):
        return {
            "ok": False,
            "status": "not_found",
            "message": "Arquivo players_online não encontrado.",
            "path": path,
            "time": datetime.now().isoformat(),
        }

    rows = _parse_csv_like(path)

    # Contagem simples
    count = 0
    if rows:
        # se veio erro
        if "error" in rows[0]:
            count = 0
        else:
            count = len(rows)

    return {
        "ok": True,
        "status": "ok",
        "path": path,
        "count": count,
        "players": rows[:50],  # limita retorno
        "time": datetime.now().isoformat(),
    }
