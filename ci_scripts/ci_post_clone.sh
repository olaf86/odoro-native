#!/bin/sh
set -eu

CONFIGS_DIR="Configs"
LOCAL_CONFIG_PATH="${CONFIGS_DIR}/AvatarStorage.local.xcconfig"

mkdir -p "${CONFIGS_DIR}"

if [ -z "${ODORO_AVATAR_STORAGE_BASE_URL:-}" ]; then
  echo "ODORO_AVATAR_STORAGE_BASE_URL is not set; skipping AvatarStorage.local.xcconfig generation."
  exit 0
fi

ESCAPED_ODORO_AVATAR_STORAGE_BASE_URL=$(printf '%s' "${ODORO_AVATAR_STORAGE_BASE_URL}" | sed 's#://#:/$()/#')

cat > "${LOCAL_CONFIG_PATH}" <<EOF
ODORO_AVATAR_STORAGE_BASE_URL=${ESCAPED_ODORO_AVATAR_STORAGE_BASE_URL}
EOF

echo "Wrote ${LOCAL_CONFIG_PATH} for Xcode Cloud."
