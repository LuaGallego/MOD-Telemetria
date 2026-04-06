@echo off
cd /d %~dp0

if not exist .venv (
    echo [ERRO] Ambiente virtual nao encontrado. Rode install_agent.bat primeiro.
    pause
    exit /b 1
)

call .venv\Scripts\activate

echo [INFO] Iniciando PZ Server Agent na porta 8000...
uvicorn main:app --host 0.0.0.0 --port 8000

pause