@echo off
cd /d %~dp0

python --version >nul 2>&1
if errorlevel 1 (
    echo [ERRO] Python nao encontrado. Instale Python 3.11+ e marque "Add Python to PATH".
    pause
    exit /b 1
)

if not exist .venv (
    echo [INFO] Criando ambiente virtual...
    python -m venv .venv
)

call .venv\Scripts\activate

echo [INFO] Instalando dependencias...
python -m pip install --upgrade pip
pip install -r requirements.txt

echo [OK] Instalacao concluida.
pause