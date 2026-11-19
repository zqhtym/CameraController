PORT=5000

#MOUNT_REMOTE_NODE - Required secret (host:dir)
MOUNT_POINT='/mnt/eco_its_cern_nfs'

TIMELAPSE_DIR='./Timelapses'
TIMELAPSE_DEST='Timelapse/Software/Timelapses'

# Secrets do NOT belong in this file. Put them in scripts/appsettings.local.sh (git-ignored), e.g.:
#   EMAIL_HOST='smtp.gmail.com'
#   EMAIL_PORT=587
#   EMAIL_HOST_USER='you@gmail.com'
#   EMAIL_HOST_PASSWORD='your-app-password'
#   DEFAULT_FROM_EMAIL='you@gmail.com'
#   DJANGO_SECRET_KEY='...'   # optional: otherwise generated once into django_framework/secret_key.txt

# For local settings
LOCAL_SETTINGS="./scripts/appsettings.local.sh"
if test -f "$LOCAL_SETTINGS"; then
    . "$LOCAL_SETTINGS";
fi
