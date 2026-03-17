#!/bin/sh
set -eu

: "${PROXY_SERVER:?PROXY_SERVER environment variable is required}"
: "${PROXY_PORT:?PROXY_PORT environment variable is required}"
PROXY_TYPE="${PROXY_TYPE:-http}"

case "$PROXY_TYPE" in
    http)   GOST_SCHEME="http" ;;
    socks4) GOST_SCHEME="socks4" ;;
    socks5) GOST_SCHEME="socks5" ;;
    *)
        echo "ERROR: Unsupported PROXY_TYPE: $PROXY_TYPE (supported: http, socks4, socks5)" >&2
        exit 1
        ;;
esac

# Redirect outbound IPv4 TCP through gost
iptables -t nat -N PROXY_REDIRECT 2>/dev/null || true
iptables -t nat -F PROXY_REDIRECT

iptables -t nat -A PROXY_REDIRECT -d 0.0.0.0/8      -j RETURN
iptables -t nat -A PROXY_REDIRECT -d 127.0.0.0/8    -j RETURN
iptables -t nat -A PROXY_REDIRECT -d 10.0.0.0/8     -j RETURN
iptables -t nat -A PROXY_REDIRECT -d 172.16.0.0/12  -j RETURN
iptables -t nat -A PROXY_REDIRECT -d 192.168.0.0/16 -j RETURN
iptables -t nat -A PROXY_REDIRECT -d 169.254.0.0/16 -j RETURN
iptables -t nat -A PROXY_REDIRECT -d 224.0.0.0/4    -j RETURN
iptables -t nat -A PROXY_REDIRECT -d 240.0.0.0/4    -j RETURN
iptables -t nat -A PROXY_REDIRECT -p tcp            -j REDIRECT --to-ports 12345
iptables -t nat -A OUTPUT         -p tcp            -j PROXY_REDIRECT

# Redirect outbound IPv6 TCP through gost (requires Docker IPv6 networking)
ip6tables -t nat -N PROXY_REDIRECT 2>/dev/null || true
if ip6tables -t nat -F PROXY_REDIRECT 2>/dev/null; then
    ip6tables -t nat -A PROXY_REDIRECT -d ::1/128       -j RETURN
    ip6tables -t nat -A PROXY_REDIRECT -d fc00::/7      -j RETURN
    ip6tables -t nat -A PROXY_REDIRECT -d fe80::/10     -j RETURN
    ip6tables -t nat -A PROXY_REDIRECT -d ff00::/8      -j RETURN
    ip6tables -t nat -A PROXY_REDIRECT -p tcp           -j REDIRECT --to-ports 12345
    ip6tables -t nat -A OUTPUT         -p tcp           -j PROXY_REDIRECT
fi

cleanup() {
    iptables  -t nat -D OUTPUT -p tcp -j PROXY_REDIRECT 2>/dev/null || true
    iptables  -t nat -F PROXY_REDIRECT 2>/dev/null || true
    iptables  -t nat -X PROXY_REDIRECT 2>/dev/null || true
    ip6tables -t nat -D OUTPUT -p tcp -j PROXY_REDIRECT 2>/dev/null || true
    ip6tables -t nat -F PROXY_REDIRECT 2>/dev/null || true
    ip6tables -t nat -X PROXY_REDIRECT 2>/dev/null || true
}
trap cleanup EXIT
trap 'kill $GOST_PID $WATCHDOG_PID 2>/dev/null' TERM INT

gost -L "red://:12345" -F "${GOST_SCHEME}://${PROXY_SERVER}:${PROXY_PORT}" &
GOST_PID=$!

# Watchdog: exit when the app container's network interface disappears.
# Docker removes the veth pair (eth0) from the shared namespace as soon as the
# app container stops, so this is a reliable signal that the app is gone.
(
    while [ -d /sys/class/net/eth0 ]; do sleep 2; done
    echo "proxy-sidecar: eth0 gone (app container stopped), exiting"
    kill $GOST_PID 2>/dev/null
) &
WATCHDOG_PID=$!

wait $GOST_PID
