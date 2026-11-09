@echo off
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
  echo Create the environment first: py -3.14 -m venv .venv
  exit /b 1
)
if not exist ".env.local" (
  echo Copy .env.local.example to .env.local and set DJANGO_SECRET_KEY first.
  exit /b 1
)
".venv\Scripts\python.exe" backend\manage.py runserver 8000
