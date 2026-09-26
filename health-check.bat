@echo off
echo [health-check] Checking container status...
docker compose ps

echo.
echo [health-check] Backend liveness (/healthz):
curl -s http://localhost:8000/healthz
echo.

echo.
echo [health-check] Backend readiness (/readyz, includes DB check):
curl -s http://localhost:8000/readyz
echo.

echo.
echo [health-check] Postgres:
docker compose exec -T postgres pg_isready -U soc_app 2>nul || echo   Postgres not reachable

echo.
echo [health-check] Redis:
docker compose exec -T redis redis-cli ping 2>nul || echo   Redis not reachable

echo.
echo [health-check] Elasticsearch:
curl -s http://localhost:9200/_cluster/health
echo.

echo.
echo [health-check] Frontend (SOC UI):
curl -s -o nul -w "  HTTP %%{http_code}\n" http://localhost:5173/
