@echo off
title CampusShare Launcher

echo Starting CampusShare Backend...
cd /d "%~dp0BACKEND"
start "CampusShare Backend" ".\build\Release\campusshare_backend.exe"

echo Starting CampusShare Frontend...
cd /d "%~dp0FRONTEND"
start "CampusShare Frontend" python -m http.server 5500

timeout /t 2 /nobreak >nul
echo Opening Browser...
start http://localhost:5500

echo.
echo ========================================
echo CampusShare is running!
echo Frontend: http://localhost:5500
echo Backend:  http://localhost:18080
echo ========================================
echo.
pause
