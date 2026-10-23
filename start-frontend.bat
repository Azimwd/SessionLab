@echo off
cd /d "%~dp0frontend"
call npm run dev -- --port 5173 --strictPort
