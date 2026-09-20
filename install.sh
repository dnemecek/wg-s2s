#!/bin/bash
# ============================================================================
# WireGuard S2S - Instalace
# ============================================================================
# Pouziti: ./install.sh
#
# David Nemecek | NC | 2026
# ============================================================================

set -euo pipefail

echo "=== WireGuard S2S Installation ==="
echo ""

# Kontrola root
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Run as root"
    exit 1
fi

# Kontrola WireGuard
echo "[CHECK] WireGuard module..."
if ! modprobe wireguard 2>/dev/null; then
    echo "[ERROR] WireGuard kernel module not available"
    exit 1
fi
echo "[OK] WireGuard module loaded"

echo "[CHECK] WireGuard tools..."
if ! command -v wg &>/dev/null; then
    echo "[ERROR] wireguard-tools not installed"
    exit 1
fi
echo "[OK] wireguard-tools installed ($(wg --version))"

# Vytvoreni adresaru
echo ""
echo "[INSTALL] Creating directories..."
mkdir -p /root/wg-s2s/tunnels
mkdir -p /root/wg-s2s/keys
chmod 700 /root/wg-s2s/keys
echo "[OK] /root/wg-s2s/"

# Kopirovani skriptu
echo "[INSTALL] Installing wg-s2s.sh..."
cp wg-s2s.sh /root/wg-s2s/wg-s2s.sh
chmod 700 /root/wg-s2s/wg-s2s.sh
ln -sf /root/wg-s2s/wg-s2s.sh /usr/local/bin/wg-s2s
echo "[OK] /root/wg-s2s/wg-s2s.sh"
echo "[OK] /usr/local/bin/wg-s2s (symlink)"

# Systemd template
echo "[INSTALL] Installing systemd template..."
cp wg-s2s@.service /etc/systemd/system/wg-s2s@.service
systemctl daemon-reload
echo "[OK] /etc/systemd/system/wg-s2s@.service"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Usage:"
echo "  wg-s2s new <n> --endpoint <ip:port> --remote-pubkey <key> \\"
echo "               --tunnel-ip <ip/mask> --remote-subnets <subnets> --psk-gen"
echo ""
echo "  wg-s2s status"
echo "  wg-s2s start <name|all>"
echo "  wg-s2s stop <name|all>"
echo ""
echo "Example:"
echo "  wg-s2s new brandys \\"
echo "    --endpoint 203.0.113.10:51820 \\"
echo "    --remote-pubkey \"<REMOTE_PUBLIC_KEY>\" \\"
echo "    --tunnel-ip 172.16.220.4/29 \\"
echo "    --remote-subnets \"192.168.220.0/24\" \\"
echo "    --psk-gen"
echo ""
