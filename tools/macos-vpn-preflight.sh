#!/bin/sh

# Read-only guard for router/Xray diagnosis on macOS.
# It intentionally fails in --strict mode when another VPN/tunnel may own the
# target path. This prevents router evidence from being mistaken for the
# application's real path.

set -u

target_ip=""
strict=0

usage() {
    cat <<'EOF'
Usage: tools/macos-vpn-preflight.sh [--target-ip IPv4] [--strict]

Read-only snapshot of desktop VPN candidates, active utun interfaces, and the
system route to an optional target address. --strict exits 2 when a competing
VPN/tunnel or non-en0 target route is detected.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --target-ip)
            [ "$#" -ge 2 ] || { echo "ERROR: --target-ip needs an IPv4 address" >&2; exit 2; }
            target_ip=$2
            shift 2
            ;;
        --strict)
            strict=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ -n "$target_ip" ]; then
    case "$target_ip" in
        *[!0-9.]*|'')
            echo "ERROR: target must be an IPv4 address: $target_ip" >&2
            exit 2
            ;;
    esac
fi

echo "=== macOS VPN preflight (read-only) ==="
printf 'target: %s\n' "${target_ip:-not specified}"

wifi_ip=$(ipconfig getifaddr en0 2>&1 || true)
printf 'en0 IPv4: %s\n' "${wifi_ip:-unavailable}"

echo "--- configured VPN services ---"
connected_services=$(scutil --nc list 2>/dev/null | sed -n '/(Connected)/p' || true)
if [ -n "$connected_services" ]; then
    printf '%s\n' "$connected_services"
else
    echo "none reported by scutil"
fi

echo "--- VPN-like processes (candidates, not proof alone) ---"
processes=$(ps axww -o pid=,command= 2>/dev/null \
    | grep -Ei 'cisco|anyconnect|secure client|amnezia|happ|blanc|wireguard|tailscale|continent|континент|ztn|батя|batya|btya|tun2socks|vpnagentd|cscotun' \
    | grep -v '[m]acos-vpn-preflight.sh' \
    | grep -v '[g]rep -Ei' \
    | grep -vE '/bin/(zsh|bash|sh) -c|[p]s (axww|aux)|[r]g -i' || true)
if [ -n "$processes" ]; then
    printf '%s\n' "$processes"
else
    echo "none found"
fi

echo "--- active tunnel interfaces ---"
active_tunnels=""
for iface in $(ifconfig -l 2>/dev/null | tr ' ' '\n' | grep -E '^(utun|ppp|tun)' || true); do
    if ifconfig "$iface" 2>/dev/null | grep -qE '^[[:space:]]+inet '; then
        active_tunnels="$active_tunnels $iface"
        printf '%s\n' "$iface"
        ifconfig "$iface" 2>/dev/null | sed -n '1,8p'
    fi
done
if [ -z "$active_tunnels" ]; then
    echo "none with an IPv4 address"
fi

echo "--- local gateway route ---"
route -n get 192.168.1.1 2>&1 | sed -n '1,12p'

route_iface=""
if [ -n "$target_ip" ]; then
    echo "--- target route ---"
    target_route=$(route -n get "$target_ip" 2>&1 || true)
    printf '%s\n' "$target_route" | sed -n '1,16p'
    route_iface=$(printf '%s\n' "$target_route" | awk '$1 == "interface:" { print $2; exit }')
fi

echo "--- result ---"
problem=0
if [ -n "$connected_services" ]; then
    echo "STOP: scutil reports a connected VPN service."
    problem=1
fi
if [ -n "$active_tunnels" ]; then
    echo "STOP: an IPv4 tunnel interface is active:$(printf '%s\n' "$active_tunnels")"
    problem=1
fi
if [ -n "$processes" ]; then
    echo "WARN: VPN-like processes are present; confirm their user-visible state."
    problem=1
fi
if [ -n "$target_ip" ] && [ "$route_iface" != "en0" ]; then
    echo "STOP: target route is not en0: ${route_iface:-unresolved}"
    problem=1
fi

if [ "$problem" -eq 0 ]; then
    echo "PASS: no competing desktop VPN evidence was found for this check."
elif [ "$strict" -eq 1 ]; then
    echo "STOP: do not change or blame the router until the desktop VPN state is resolved."
    exit 2
else
    echo "WARN: non-strict mode; router diagnosis may be misleading."
fi

exit 0
