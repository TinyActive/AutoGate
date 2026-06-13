#!/bin/sh

# FreeConnect egress connector.
#
# The freeconnect.link endpoints are HTTPS proxies: the client must speak HTTP
# CONNECT *over TLS* to the proxy, addressing it by its domain name (the TLS
# certificate is issued for that domain) with HTTP Basic auth. That is exactly
# what `curl -x https://user:pass@host:PORT` does.
#
# HAProxy backends in this stack are plain HTTP proxies, and HAProxy itself
# cannot originate an upstream "HTTPS proxy + CONNECT + auth" chain. So we put a
# local adapter in front: gost listens as a plain HTTP proxy on :8080 (which
# HAProxy chains to like any other backend) and forwards everything to the
# selected upstream HTTPS proxy over TLS. A random upstream is picked from the
# CSV on every (re)start, and the watchdog rotates it on ROTATING_DELAY.

CSV="${FREECONNECT_CSV:-/data/freeconnect.csv}"
UPSTREAM_PORT="${FREECONNECT_PORT:-9251}"
LISTEN_PORT="${HTTP_PORT:-8080}"
FILTER="${FREECONNECT_FILTER:-}"
# Credentials are identical across every server in the list, so they can be set
# once via env. When FREECONNECT_USER / FREECONNECT_PASS are empty, fall back to
# the per-row values parsed from the CSV.
ENV_USER="${FREECONNECT_USER:-}"
ENV_PASS="${FREECONNECT_PASS:-}"

if [ ! -f "$CSV" ]; then
    echo "ERROR: FreeConnect proxy list not found at $CSV"
    exit 1
fi

# Drop the header line + any blank lines and strip CR (the CSV is CRLF).
rows=$(tail -n +2 "$CSV" | tr -d '\r' | grep -v '^[[:space:]]*$')

# Optional: keep only hosts whose domain matches FREECONNECT_FILTER (e.g. "us0",
# "nl", "de"). If nothing matches, fall back to the full list.
if [ -n "$FILTER" ]; then
    filtered=$(echo "$rows" | grep -i "$FILTER")
    if [ -n "$filtered" ]; then
        rows="$filtered"
    else
        echo "WARN: no FreeConnect host matched FREECONNECT_FILTER='$FILTER'; using full list."
    fi
fi

line=$(echo "$rows" | shuf -n 1)
host=$(echo "$line" | cut -d, -f1)
user=$(echo "$line" | cut -d, -f2)
pass=$(echo "$line" | cut -d, -f3)

# Env-provided credentials override the per-row CSV values when set.
[ -n "$ENV_USER" ] && user="$ENV_USER"
[ -n "$ENV_PASS" ] && pass="$ENV_PASS"

if [ -z "$host" ] || [ -z "$user" ] || [ -z "$pass" ]; then
    echo "ERROR: could not resolve a usable proxy entry (host/user/pass) from $CSV / env"
    exit 1
fi

UPSTREAM="https://${user}:${pass}@${host}:${UPSTREAM_PORT}"

echo "FreeConnect: selected upstream https://${user}:***@${host}:${UPSTREAM_PORT}"
echo "FreeConnect: local HTTP proxy on :${LISTEN_PORT} -> upstream HTTPS proxy (TLS)"

# `exec` so gost becomes this script's process; the watchdog rotates by sending
# it SIGINT (killall gost) and re-running this script.
exec gost -L "http://:${LISTEN_PORT}" -F "${UPSTREAM}"
