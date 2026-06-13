#!/bin/sh

# Healthcheck: verify the Psiphon tunnel is actually carrying traffic by making
# a request THROUGH the local HTTP proxy. A simple port check would pass as soon
# as Psiphon starts listening (before a tunnel is established), so we test real
# egress instead. Exits non-zero (unhealthy) until the tunnel is usable.

PORT="${HTTP_PORT:-8080}"
URL="${HEALTHCHECK_URL:-https://www.google.com/generate_204}"

curl -fsS --max-time 10 -x "http://127.0.0.1:${PORT}" "$URL" -o /dev/null
