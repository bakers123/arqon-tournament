@echo off
setlocal
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js 18+ is required. Install it from https://nodejs.org/
  pause
  exit /b 1
)
if not exist "node_modules\ws" (
  echo Installing ARQON Broadcast Bridge dependencies...
  call npm install
  if errorlevel 1 pause & exit /b 1
)
echo.
echo Starting ARQON Broadcast Bridge...
echo OBS Browser Source: http://127.0.0.1:3001/broadcast/
echo Keep this window open during the match.
echo.
call npm start
pause
