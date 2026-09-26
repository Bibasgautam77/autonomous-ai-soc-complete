@echo off
REM Stops all containers but preserves data volumes (Postgres/ES data survives).

echo [stop] Stopping containers...
docker compose stop
if %ERRORLEVEL% NEQ 0 (
    echo [stop] ERROR: docker compose stop failed. See output above.
    exit /b 1
)
echo [stop] Stopped. Data volumes were preserved. Use `docker compose down -v` manually to wipe data.
