#!/bin/bash
# ============================================================================
# WireGuard Site-to-Site Multi-Tunnel Management
# ============================================================================
# Umisteni:  /root/wg-s2s/wg-s2s.sh
# Ucel:      Sprava vice WG S2S tunelu na UniFi Cloud Gateway
# Pouziti:   /root/wg-s2s/wg-s2s.sh <command> [options]
#
# Prikazy:
#   new <name> --endpoint --remote-pubkey --tunnel-ip --remote-subnets [--psk|--psk-gen]
#   start <name|all>
#   stop <name|all>
#   restart <name|all>
#   status [name|all]
#   delete <name>
#   list
#
# Proc rucni WG misto UniFi GUI:
#   - UniFi WG Client pridava masquerade (NAT) na tunel traffic
#   - Rucni setup = zadny NAT, originalni source IP prochazi
#
# David Nemecek | NC | 2026
# ============================================================================

set -euo pipefail

# ============================================================================
# KONFIGURACE
# ============================================================================

WG_BASE_DIR="/root/wg-s2s"
WG_TUNNELS_DIR="${WG_BASE_DIR}/tunnels"
WG_KEYS_DIR="${WG_BASE_DIR}/keys"
LOG_TAG="wg-s2s"

# ============================================================================
# POMOCNE FUNKCE
# ============================================================================

log_info() {
    logger -t "${LOG_TAG}" -p user.info "$1"
    echo "[INFO] $1"
}

log_error() {
    logger -t "${LOG_TAG}" -p user.err "$1"
    echo "[ERROR] $1" >&2
}

log_success() {
    echo "[OK] $1"
}

die() {
    log_error "$1"
    exit 1
}

ensure_dirs() {
    mkdir -p "${WG_TUNNELS_DIR}"
    mkdir -p "${WG_KEYS_DIR}"
    chmod 700 "${WG_KEYS_DIR}"
}

check_wg() {
    if ! command -v wg &>/dev/null; then
        die "wireguard-tools not installed"
    fi
    if ! modprobe wireguard 2>/dev/null; then
        die "WireGuard kernel module not available"
    fi
}

get_interface_name() {
    local name="$1"
    echo "${name}"
}

get_config_path() {
    local name="$1"
    echo "${WG_TUNNELS_DIR}/${name}.conf"
}

get_private_key_path() {
    local name="$1"
    echo "${WG_KEYS_DIR}/${name}.key"
}

get_public_key_path() {
    local name="$1"
    echo "${WG_KEYS_DIR}/${name}.pub"
}

get_psk_path() {
    local name="$1"
    echo "${WG_KEYS_DIR}/${name}.psk"
}

tunnel_exists() {
    local name="$1"
    [[ -f "$(get_config_path "$name")" ]]
}

tunnel_is_running() {
    local name="$1"
    local iface
    iface=$(get_interface_name "$name")
    ip link show "$iface" &>/dev/null
}

list_tunnels() {
    local tunnels=()
    if [[ -d "${WG_TUNNELS_DIR}" ]]; then
        for conf in "${WG_TUNNELS_DIR}"/*.conf; do
            [[ -f "$conf" ]] || continue
            tunnels+=("$(basename "$conf" .conf)")
        done
    fi
    echo "${tunnels[@]}"
}

# ============================================================================
# PRIKAZ: new
# ============================================================================

cmd_new() {
    local name=""
    local endpoint=""
    local remote_pubkey=""
    local tunnel_ip=""
    local remote_subnets=""
    local psk=""
    local psk_gen=false
    local no_start=false
    local no_enable=false

    # Parsovani parametru
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --endpoint)
                endpoint="$2"
                shift 2
                ;;
            --remote-pubkey)
                remote_pubkey="$2"
                shift 2
                ;;
            --tunnel-ip)
                tunnel_ip="$2"
                shift 2
                ;;
            --remote-subnets)
                remote_subnets="$2"
                shift 2
                ;;
            --psk)
                psk="$2"
                shift 2
                ;;
            --psk-gen)
                psk_gen=true
                shift
                ;;
            --no-start)
                no_start=true
                shift
                ;;
            --no-enable)
                no_enable=true
                shift
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$1"
                else
                    die "Unexpected argument: $1"
                fi
                shift
                ;;
        esac
    done

    # Validace
    [[ -z "$name" ]] && die "Usage: $0 new <name> --endpoint <ip:port> --remote-pubkey <key> --tunnel-ip <ip/mask> --remote-subnets <subnets> [--psk <key>|--psk-gen]"
    [[ -z "$endpoint" ]] && die "Missing --endpoint"
    [[ -z "$remote_pubkey" ]] && die "Missing --remote-pubkey"
    [[ -z "$tunnel_ip" ]] && die "Missing --tunnel-ip"
    [[ -z "$remote_subnets" ]] && die "Missing --remote-subnets"

    # Kontrola ze tunel neexistuje
    if tunnel_exists "$name"; then
        die "Tunnel '$name' already exists. Use 'delete' first."
    fi

    ensure_dirs
    check_wg

    log_info "Creating tunnel: $name"

    # Generovani klicu
    local private_key_path
    private_key_path=$(get_private_key_path "$name")
    local public_key_path
    public_key_path=$(get_public_key_path "$name")

    wg genkey | tee "$private_key_path" | wg pubkey > "$public_key_path"
    chmod 600 "$private_key_path"

    local private_key
    private_key=$(cat "$private_key_path")
    local public_key
    public_key=$(cat "$public_key_path")

    log_info "Generated keypair for $name"

    # PSK
    local psk_path
    psk_path=$(get_psk_path "$name")
    local psk_line=""

    if [[ "$psk_gen" == true ]]; then
        wg genpsk > "$psk_path"
        chmod 600 "$psk_path"
        psk=$(cat "$psk_path")
        log_info "Generated PSK for $name"
    elif [[ -n "$psk" ]]; then
        echo "$psk" > "$psk_path"
        chmod 600 "$psk_path"
        log_info "Stored PSK for $name"
    fi

    if [[ -n "$psk" ]]; then
        psk_line="PresharedKey = ${psk}"
    fi

    # Extrahuj remote tunnel IP z tunnel_ip pro AllowedIPs
    # Predpokladame /29 nebo /30, remote je .1 pokud my jsme .4 atd
    local tunnel_net
    tunnel_net=$(echo "$tunnel_ip" | cut -d'/' -f1 | sed 's/\.[0-9]*$/\.0/')
    local tunnel_mask
    tunnel_mask=$(echo "$tunnel_ip" | cut -d'/' -f2)

    # Vytvoreni configu
    local config_path
    config_path=$(get_config_path "$name")

    cat > "$config_path" << EOF
# WireGuard S2S Tunnel: ${name}
# Vytvoreno: $(date '+%Y-%m-%d %H:%M:%S')
# David Nemecek | NC | 2026

[Interface]
PrivateKey = ${private_key}
Address = ${tunnel_ip}

[Peer]
PublicKey = ${remote_pubkey}
${psk_line}
Endpoint = ${endpoint}
AllowedIPs = ${remote_subnets}
PersistentKeepalive = 25
EOF

    chmod 600 "$config_path"
    log_success "Config created: $config_path"

    # Vypis info pro pfSense
    echo ""
    echo "========================================"
    echo "TUNNEL: $name"
    echo "========================================"
    echo ""
    echo "Pro nastaveni na pfSense (peer):"
    echo "  Public Key:  $public_key"
    if [[ -n "$psk" ]]; then
        echo "  PSK:         $psk"
    fi
    echo "  Allowed IPs: ${tunnel_ip%/*}/32, <UCG_LAN_SUBNET>"
    echo ""
    echo "========================================"

    # Start tunelu
    if [[ "$no_start" != true ]]; then
        cmd_start "$name"
    fi

    # Enable systemd
    if [[ "$no_enable" != true ]]; then
        if [[ -f "/etc/systemd/system/wg-s2s@.service" ]]; then
            systemctl enable "wg-s2s@${name}.service" 2>/dev/null || true
            log_success "Systemd enabled: wg-s2s@${name}"
        fi
    fi
}

# ============================================================================
# PRIKAZ: start
# ============================================================================

cmd_start() {
    local name="$1"

    if [[ "$name" == "all" ]]; then
        for t in $(list_tunnels); do
            cmd_start "$t"
        done
        return
    fi

    if ! tunnel_exists "$name"; then
        die "Tunnel '$name' does not exist"
    fi

    local iface
    iface=$(get_interface_name "$name")

    if tunnel_is_running "$name"; then
        log_info "Tunnel '$name' is already running"
        return 0
    fi

    check_wg

    local config_path
    config_path=$(get_config_path "$name")

    log_info "Starting tunnel: $name"
    wg-quick up "$config_path"
    log_success "Tunnel '$name' started (interface: $iface)"
}

# ============================================================================
# PRIKAZ: stop
# ============================================================================

cmd_stop() {
    local name="$1"

    if [[ "$name" == "all" ]]; then
        for t in $(list_tunnels); do
            cmd_stop "$t"
        done
        return
    fi

    if ! tunnel_exists "$name"; then
        die "Tunnel '$name' does not exist"
    fi

    if ! tunnel_is_running "$name"; then
        log_info "Tunnel '$name' is not running"
        return 0
    fi

    local config_path
    config_path=$(get_config_path "$name")

    log_info "Stopping tunnel: $name"
    wg-quick down "$config_path"
    log_success "Tunnel '$name' stopped"
}

# ============================================================================
# PRIKAZ: restart
# ============================================================================

cmd_restart() {
    local name="$1"

    if [[ "$name" == "all" ]]; then
        for t in $(list_tunnels); do
            cmd_restart "$t"
        done
        return
    fi

    cmd_stop "$name"
    sleep 1
    cmd_start "$name"
}

# ============================================================================
# PRIKAZ: status
# ============================================================================

cmd_status() {
    local name="${1:-all}"

    if [[ "$name" == "all" ]]; then
        local tunnels
        tunnels=$(list_tunnels)

        if [[ -z "$tunnels" ]]; then
            echo "No tunnels configured"
            return
        fi

        echo ""
        printf "%-15s %-10s %-20s %-15s\n" "TUNNEL" "STATUS" "ENDPOINT" "HANDSHAKE"
        echo "----------------------------------------------------------------------"

        for t in $tunnels; do
            local status="DOWN"
            local endpoint="-"
            local handshake="-"
            local iface
            iface=$(get_interface_name "$t")

            if tunnel_is_running "$t"; then
                status="UP"
                endpoint=$(wg show "$iface" endpoints 2>/dev/null | awk '{print $2}' | head -1)
                local hs
                hs=$(wg show "$iface" latest-handshakes 2>/dev/null | awk '{print $2}' | head -1)
                if [[ -n "$hs" && "$hs" != "0" ]]; then
                    local now
                    now=$(date +%s)
                    local diff=$((now - hs))
                    handshake="${diff}s ago"
                fi
            fi

            printf "%-15s %-10s %-20s %-15s\n" "$t" "$status" "$endpoint" "$handshake"
        done
        echo ""
        return
    fi

    if ! tunnel_exists "$name"; then
        die "Tunnel '$name' does not exist"
    fi

    local iface
    iface=$(get_interface_name "$name")

    echo ""
    echo "=== Tunnel: $name ==="
    echo ""

    if ! tunnel_is_running "$name"; then
        echo "Status: DOWN"
        return
    fi

    echo "Status: UP"
    echo ""
    echo "=== Interface ==="
    ip addr show "$iface"
    echo ""
    echo "=== WireGuard ==="
    wg show "$iface"
    echo ""
    echo "=== Routes ==="
    ip route show dev "$iface" 2>/dev/null || echo "No routes"
    echo ""
}

# ============================================================================
# PRIKAZ: delete
# ============================================================================

cmd_delete() {
    local name="$1"

    [[ -z "$name" ]] && die "Usage: $0 delete <name>"
    [[ "$name" == "all" ]] && die "Cannot delete 'all'. Delete tunnels individually."

    if ! tunnel_exists "$name"; then
        die "Tunnel '$name' does not exist"
    fi

    # Stop pokud bezi
    if tunnel_is_running "$name"; then
        cmd_stop "$name"
    fi

    # Disable systemd
    systemctl disable "wg-s2s@${name}.service" 2>/dev/null || true

    # Smaz soubory
    rm -f "$(get_config_path "$name")"
    rm -f "$(get_private_key_path "$name")"
    rm -f "$(get_public_key_path "$name")"
    rm -f "$(get_psk_path "$name")"

    log_success "Tunnel '$name' deleted"
}

# ============================================================================
# PRIKAZ: list
# ============================================================================

cmd_list() {
    local tunnels
    tunnels=$(list_tunnels)

    if [[ -z "$tunnels" ]]; then
        echo "No tunnels configured"
        return
    fi

    echo "Configured tunnels:"
    for t in $tunnels; do
        local status="DOWN"
        tunnel_is_running "$t" && status="UP"
        echo "  - $t ($status)"
    done
}

# ============================================================================
# HELP
# ============================================================================

show_help() {
    cat << 'EOF'
WireGuard S2S Multi-Tunnel Management

Usage: wg-s2s.sh <command> [options]

Commands:
  new <name>      Create new tunnel
                  --endpoint <ip:port>       Remote WG endpoint
                  --remote-pubkey <key>      Remote peer public key
                  --tunnel-ip <ip/mask>      Local tunnel IP (e.g. 172.16.220.4/29)
                  --remote-subnets <nets>    Remote subnets (e.g. "192.168.220.0/24")
                  --psk <key>                Pre-shared key (optional)
                  --psk-gen                  Generate PSK automatically
                  --no-start                 Don't start tunnel after creation
                  --no-enable                Don't enable systemd autostart

  start <name|all>    Start tunnel(s)
  stop <name|all>     Stop tunnel(s)
  restart <name|all>  Restart tunnel(s)
  status [name|all]   Show tunnel status (default: all)
  delete <name>       Delete tunnel
  list                List all tunnels

Examples:
  wg-s2s.sh new brandys \
    --endpoint 203.0.113.10:51820 \
    --remote-pubkey "<REMOTE_PUBLIC_KEY>" \
    --tunnel-ip 172.16.220.4/29 \
    --remote-subnets "192.168.220.0/24" \
    --psk-gen

  wg-s2s.sh status
  wg-s2s.sh restart brandys

EOF
}

# ============================================================================
# MAIN
# ============================================================================

ensure_dirs

case "${1:-}" in
    new)
        shift
        cmd_new "$@"
        ;;
    start)
        shift
        cmd_start "${1:-all}"
        ;;
    stop)
        shift
        cmd_stop "${1:-all}"
        ;;
    restart)
        shift
        cmd_restart "${1:-all}"
        ;;
    status)
        shift
        cmd_status "${1:-all}"
        ;;
    delete)
        shift
        cmd_delete "${1:-}"
        ;;
    list)
        cmd_list
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
