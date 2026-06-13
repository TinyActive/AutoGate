#!/bin/sh

# Healthcheck: prove real egress by issuing a request THROUGH the local gost
# HTTP proxy (which tunnels to the upstream FreeConnect HTTPS proxy), not just a
# port check. Reports unhealthy until the upstream proxy is actually reachable
# and carrying traffic.

PORT="${HTTP_PORT:-8080}"
URL="${HEALTHCHECK_URL:-https://ifconfig.io/ip}"

curl -fsS --max-time 10 -x "http://127.0.0.1:${PORT}" "$URL" -o /dev/null
