#!/bin/bash
# ============================================================================
# WireGuard S2S - Deploy na UniFi Cloud Gateway
# ============================================================================
# Pouziti:  ./deploy.sh [user@]<host> [--no-install]
#           ./deploy.sh 192.168.1.1            (user = root)
#           ./deploy.sh admin@ucg.lan
#
# Co dela: nakopiruje wg-s2s.sh, wg-s2s@.service a install.sh do /root na UCG
#          a spusti tam install.sh (idempotentni - prepise skript + unit,
#          existujici tunely v /root/wg-s2s/tunnels nesaha).
#
# David Nemecek | NC | 2026
# ============================================================================

set -euo pipefail

TARGET="${1:-}"
NO_INSTALL=false
[[ "${2:-}" == "--no-install" ]] && NO_INSTALL=true
FILES=(wg-s2s.sh wg-s2s@.service install.sh)

[[ -z "$TARGET" ]] && { echo "Usage: $0 [user@]<host> [--no-install]" >&2; exit 1; }
[[ "$TARGET" == *@* ]] || TARGET="root@${TARGET}"
USER_="${TARGET%%@*}"
HOST="${TARGET#*@}"

cd "$(dirname "$0")"
for f in "${FILES[@]}"; do
    [[ -f "$f" ]] || { echo "[ERROR] Missing $f" >&2; exit 1; }
done
bash -n wg-s2s.sh install.sh

echo "[DEPLOY] Copying files to ${USER_}@${HOST}:/root/"
scp -q "${FILES[@]}" "${USER_}@${HOST}:/root/"

if [[ "$NO_INSTALL" == true ]]; then
    echo "[OK] Files copied, install skipped (--no-install)"
    exit 0
fi

echo "[DEPLOY] Running install.sh on ${HOST}"
ssh "${USER_}@${HOST}" 'cd /root && chmod 700 install.sh && ./install.sh'

echo "[DEPLOY] Configured tunnels:"
ssh "${USER_}@${HOST}" '/root/wg-s2s/wg-s2s.sh list'
echo "[OK] Deploy complete. Restart tunnels manually if wg-s2s.sh changed: wg-s2s restart all"
