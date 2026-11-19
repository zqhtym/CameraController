#!/usr/bin/env bash
# Starts the web app inside the "CameraCtrl" WSL distro (as root). Called by CameraController-Start.exe.
# Usage: start-server.sh [time zone hint from Windows, e.g. Asia/Shanghai]
APP=/opt/CameraController
TZ_HINT="${1:-UTC}"

valid_tz() { [ -n "$1" ] && [ -f "/usr/share/zoneinfo/$1" ]; }

# Use the Windows time zone so schedules are entered/executed in local time.
TZ_NAME="UTC"
if valid_tz "$TZ_HINT"; then
  TZ_NAME="$TZ_HINT"
fi
case "$TZ_NAME" in
  UTC|Etc/*)
    # Hint is only an offset; prefer a real zone if WSL already mirrored one into /etc/localtime
    LINK=$(readlink -f /etc/localtime 2>/dev/null || true)
    case "$LINK" in
      */zoneinfo/*)
        CAND="${LINK#*/zoneinfo/}"
        case "$CAND" in
          UTC|Etc/*|posix/*|right/*) ;;
          *) valid_tz "$CAND" && TZ_NAME="$CAND" ;;
        esac ;;
    esac ;;
esac
export TZ="$TZ_NAME"
export DJANGO_TIME_ZONE="$TZ_NAME"

cd "$APP" || { echo "[server] $APP not found - run the setup again"; exit 1; }
set -a
. ./scripts/appsettings.sh
set +a
PORT="${PORT:-5000}"

echo "[server] time zone : $TZ_NAME (now $(date '+%Y-%m-%d %H:%M:%S'))"
echo "[server] cameras   :"
CAMS=$(lsusb 2>/dev/null | grep -i ' 04a9:')
if [ -n "$CAMS" ]; then
  echo "$CAMS" | sed 's/^/             /'
else
  echo "             (no Canon camera visible in Linux)"
fi
echo "[server] starting on port $PORT ..."
exec "$APP/.venv/bin/python" src/infrastructure/django_framework/manage.py runserver "0.0.0.0:$PORT" --noreload
