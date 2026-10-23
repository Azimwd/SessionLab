#!/bin/sh
set -eu
# Dual-stack bind lets the frontend reach Django through Railway private DNS.
exec gunicorn config.wsgi:application --bind "[::]:${PORT:-8000}" --workers 3 --worker-class gthread --threads 16 --timeout 60 --access-logfile -
