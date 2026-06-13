#!/bin/sh

# Healthcheck: prove real egress by issuing a request THROUGH the local
# tinyproxy (bound to tun0), not just a port check. Reports unhealthy until the
# Riseup tunnel is established and actually carrying traffic.

PORT="${HTTP_PORT:-8080}"
URL="${HEALTHCHECK_URL:-https://www.google.com/generate_204}"

get_addr() {
    ip -4 addr show dev "$1" 2>/dev/null \
        | grep -oE 'inet [0-9.]+' \
        | head -n1 \
        | cut -d ' ' -f 2
}

# tinyproxy Listens on the eth0 (custom_network) address, so target that.
PROXY_HOST="${LISTEN_ON:-$(get_addr eth0)}"
PROXY_HOST="${PROXY_HOST:-127.0.0.1}"

curl -fsS --max-time 10 -x "http://${PROXY_HOST}:${PORT}" "$URL" -o /dev/null
