@echo off
REM Starts the full stack: Postgres, Redis, Elasticsearch, backend API,
REM and the frontend SOC UI. Alembic migrations run automatically as part
REM of the backend container's start command (see backend/Dockerfile).

setlocal

if not exist ".env" (
    echo [start] ERROR: .env not found. Run setup.bat first.
    exit /b 1
)

echo [start] Starting containers in the background...
docker compose up -d
if %ERRORLEVEL% NEQ 0 (
    echo [start] ERROR: docker compose up failed. See output above.
    exit /b 1
)

echo [start] Waiting for the API to become healthy...
set /a tries=0
:waitloop
curl -s -o nul -w "%%{http_code}" http://localhost:8000/healthz > "%TEMP%\soc_health.txt" 2>nul
set /p code=<"%TEMP%\soc_health.txt"
if "%code%"=="200" (
    echo [start] Backend is up: http://localhost:8000/docs
    goto :done
)
set /a tries+=1
if %tries% GEQ 30 (
    echo [start] WARNING: backend did not report healthy after 30 attempts.
    echo [start] Check logs with: docker compose logs -f backend
    goto :done
)
timeout /t 2 >nul
goto :waitloop

:done
echo.
echo [start] Postgres:      localhost:5432
echo [start] Redis:         localhost:6379
echo [start] Elasticsearch: http://localhost:9200
echo [start] Backend API:   http://localhost:8000  (docs at /docs)
echo [start] SOC UI:        http://localhost:5173
echo.
echo [start] First time running? Load demo data and train the ML baseline with:
echo [start]   seed-demo-data.bat
echo.
endlocal
