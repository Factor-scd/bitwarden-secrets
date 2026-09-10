#!/usr/bin/env bash
# install.sh — Install bw-secrets to ~/.local/bin
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/bw-secrets"
DEST="${HOME}/.local/bin/bw-secrets"

mkdir -p "${HOME}/.local/bin"
install -m 700 "${SRC}" "${DEST}"
echo "Installed bw-secrets → ${DEST}"

# Ensure ~/.local/bin is on PATH
case ":${PATH}:" in
  *":${HOME}/.local/bin:"*) ;;
  *) echo "NOTE: add ${HOME}/.local/bin to your PATH" ;;
esac

# Optional: create config dir with template
CONFIG_DIR="${HOME}/.config/bw"
if [[ ! -f "${CONFIG_DIR}/config.env" ]]; then
  mkdir -p "${CONFIG_DIR}"
  cat > "${CONFIG_DIR}/config.env" <<'EOF'
# bw-secrets configuration (chmod 600)
# BW_SERVER and BW_ORG_ID are required — set them to your vault.
# BW_SERVER=https://vault.example.com
# BW_ORG_ID=<your-org-id>
# BW_MASTER_PW_FILE=${HOME}/.config/bw/master_pw
EOF
  chmod 600 "${CONFIG_DIR}/config.env"
  echo "Created config template → ${CONFIG_DIR}/config.env"
fi

echo "Done. Set BW_SERVER and BW_ORG_ID in ${CONFIG_DIR}/config.env, then test with: bw-secrets status"
