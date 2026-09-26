@echo off
REM Seeds synthetic demo data (admin user, benign baseline events, a few
REM suspicious events, and demo IOCs) into the running backend container,
REM then trains the ML anomaly baseline on it. Run this AFTER start.bat.
REM
REM All seeded data is synthetic/fabricated for demo purposes — see
REM backend/scripts/seed_demo_data.py for exactly what it creates.

setlocal

echo [seed] Checking that the backend container is running...
docker compose ps backend | findstr /C:"Up" >nul
if %ERRORLEVEL% NEQ 0 (
    echo [seed] ERROR: backend container is not running. Run start.bat first.
    exit /b 1
)

echo [seed] Seeding demo data (admin user, synthetic events, demo IOCs)...
docker compose exec -T backend python -m scripts.seed_demo_data
if %ERRORLEVEL% NEQ 0 (
    echo [seed] ERROR: seeding failed. See output above.
    exit /b 1
)

echo [seed] Logging in as admin to obtain a token for training...
curl -s -X POST http://localhost:8000/api/auth/login ^
    -H "Content-Type: application/json" ^
    -d "{\"username\":\"admin\",\"password\":\"ChangeMe123!\"}" > "%TEMP%\soc_login.json"

for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "(Get-Content '%TEMP%\soc_login.json' | ConvertFrom-Json).access_token"`) do set TOKEN=%%A

if "%TOKEN%"=="" (
    echo [seed] WARNING: could not obtain admin token automatically.
    echo [seed] Log in manually at http://localhost:5173 and call POST /api/ml/train yourself.
    goto :done
)

echo [seed] Training ML anomaly baseline on seeded events...
curl -s -X POST "http://localhost:8000/api/ml/train?limit=5000" -H "Authorization: Bearer %TOKEN%"
echo.

:done
echo.
echo [seed] Done. Log in at http://localhost:5173 with:
echo [seed]   username: admin
echo [seed]   password: ChangeMe123!
echo [seed] CHANGE THIS PASSWORD before using this instance for anything real.
endlocal
