#!/usr/bin/env bash
# Provisions the dedicated "CameraCtrl" WSL distro. Runs as root, called by CameraController-Setup.exe.
# Usage: provision.sh <project dir> <photo dir> <cn|default> [log dir]   (all paths are Linux paths)
set -euo pipefail

SRC="$1"
PHOTOS="$2"
MIRROR="${3:-default}"
LOGDIR="${4:-}"
APP=/opt/CameraController

if [ -n "$LOGDIR" ]; then
  mkdir -p "$LOGDIR"
  exec > >(tee -a "$LOGDIR/provision.log") 2>&1
fi

step() { echo; echo "==> [$(date '+%H:%M:%S')] $*"; }
export DEBIAN_FRONTEND=noninteractive

step "1/6 Package sources (mirror: $MIRROR)"
PIP_ARGS=()
if [ "$MIRROR" = "cn" ]; then
  if [ -f /etc/apt/sources.list ]; then
    sed -i -E 's#https?://(archive|security)\.ubuntu\.com/ubuntu/?#https://mirrors.tuna.tsinghua.edu.cn/ubuntu/#g' /etc/apt/sources.list
  fi
  PIP_ARGS=(-i https://pypi.tuna.tsinghua.edu.cn/simple)
fi

step "2/6 System packages (python3-venv, gphoto2, usbutils)"
apt_install() {
  apt-get update && apt-get install -y --no-install-recommends python3-venv gphoto2 usbutils ca-certificates tzdata
}
if ! apt_install; then
  if [ "$MIRROR" = "cn" ]; then
    echo "Mirror failed, falling back to the official Ubuntu archive"
    sed -i -E 's#https://mirrors\.tuna\.tsinghua\.edu\.cn/ubuntu/#http://archive.ubuntu.com/ubuntu/#g' /etc/apt/sources.list
    apt_install
  else
    exit 1
  fi
fi
# The original NFS upload helper (scripts/run_timelapse_file_transfer.sh) loops forever trying to
# mount the author's NFS server. It disables itself when inotifywait is missing, so keep it absent.
if command -v inotifywait >/dev/null 2>&1; then
  apt-get purge -y inotify-tools || true
fi

step "3/6 Copy application to $APP"
mkdir -p "$APP"
tar -C "$SRC" \
  --exclude='./windows/offline' --exclude='*.exe' --exclude='./.idea' --exclude='./.vscode' \
  --exclude='./imgs' --exclude='./.venv' --exclude='./Timelapses' --exclude='*/db.sqlite3' \
  --exclude='*/__pycache__' \
  -cf - . | tar -C "$APP" -xf -
find "$APP" -name '*.sh' -exec sed -i 's/\r$//' {} + -exec chmod +x {} +
chmod +x "$APP/src/infrastructure/django_framework/manage.py"

# Photos are written straight to the Windows folder (default timelapse dir is ./Timelapses)
mkdir -p "$PHOTOS"
if [ -d "$APP/Timelapses" ] && [ ! -L "$APP/Timelapses" ]; then
  cp -a "$APP/Timelapses/." "$PHOTOS/" && rm -rf "$APP/Timelapses"
fi
ln -sfn "$PHOTOS" "$APP/Timelapses"

step "4/6 Python environment"
PY="$APP/.venv/bin/python"
[ -x "$PY" ] || python3 -m venv "$APP/.venv"
pip_install() { "$PY" -m pip install --disable-pip-version-check --progress-bar off "$@"; }
if ! pip_install "${PIP_ARGS[@]}" -r "$APP/requirements.txt"; then
  echo "pip failed, retrying with the default PyPI index"
  pip_install -r "$APP/requirements.txt"
fi
# Same effect as the original "pip install -e ./src/": make src/ importable
SITE=$("$PY" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')
echo "$APP/src" > "$SITE/cameracontroller-src.pth"

"$PY" - <<'EOF' || true
import gphoto2 as gp
print("python-gphoto2", gp.__version__, "/ libgphoto2", gp.gp_library_version(gp.GP_VERSION_SHORT)[0])
abilities = gp.CameraAbilitiesList()
abilities.load()
try:
    abilities.lookup_model("Canon EOS 5D Mark II")
    print("Canon EOS 5D Mark II: supported by this libgphoto2")
except gp.GPhoto2Error:
    print("WARNING: Canon EOS 5D Mark II not found in the libgphoto2 camera list")
EOF

step "5/6 Database"
cd "$APP/src/infrastructure/django_framework"
FIRST=0
[ -f db.sqlite3 ] || FIRST=1
"$PY" manage.py migrate --noinput
if [ "$FIRST" = 1 ]; then
  "$PY" manage.py loaddata camera_config_fixtures || echo "Initial fixtures not loaded (ignored)"
fi
CC_FIRST_INSTALL="$FIRST" "$PY" manage.py shell -c "
import os
from django.contrib.auth import get_user_model
User = get_user_model()
if not User.objects.filter(username='Admin').exists():
    User.objects.create_superuser('Admin', 'admin@myproject.com', 'admin')
    print('Web login created: Admin / admin')
if os.environ.get('CC_FIRST_INSTALL') == '1':
    from camera_ctrl.models.app_settings_models import GeneralSettings
    s = GeneralSettings.get()
    s.nb_of_failures_to_reboot_after = 0       # default 2 would run 'sudo reboot' after 2 failed captures
    s.hard_reset_on_timelapse_error = False    # needs a Yepkit ykush3 USB board
    s.save()
    print('Safe defaults applied: no automatic reboot, no ykush hard reset')
"

step "6/6 WSL settings"
sed 's/\r$//' "$SRC/windows/linux/wsl.conf" > /etc/wsl.conf
date '+%Y-%m-%d %H:%M:%S' > "$APP/.provisioned"
echo
echo "Provisioning finished."
