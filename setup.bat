@echo off
REM ============================================================
REM  Autonomous AI-SOC Platform - Windows setup script
REM  Prereqs: Docker Desktop (with Compose v2), or Python 3.11+
REM           if you prefer running the backend outside Docker.
REM ============================================================

setlocal

if not exist ".env" (
    echo [setup] .env not found - copying from .env.example
    copy .env.example .env >nul
    echo [setup] IMPORTANT: edit .env and set a real SECRET_KEY and DB password
    echo [setup]            before running in anything other than local dev.
) else (
    echo [setup] .env already exists - leaving it as-is.
)

where docker >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [setup] ERROR: Docker was not found on PATH. Install Docker Desktop:
    echo [setup]   https://www.docker.com/products/docker-desktop/
    exit /b 1
)

echo [setup] Building images (this can take a few minutes the first time)...
docker compose build
if %ERRORLEVEL% NEQ 0 (
    echo [setup] ERROR: docker compose build failed. See output above.
    exit /b 1
)

echo [setup] Done. Run start.bat to launch the stack.
endlocal
