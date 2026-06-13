#!/bin/sh

# Psiphon ConsoleClient entrypoint.
#
# Establishes a Psiphon tunnel and exposes a local HTTP/SOCKS proxy that the
# HAProxy frontend can chain to as one more rotating egress path.
#
# Config strategy (fully automated, self-healing):
#   * /psiphon/psiphon.config is the bundled, read-only "standard" config.
#   * The runtime config is ALWAYS rebuilt from a validated source on every
#     start, so a manually edited / corrupted runtime file auto-reverts to the
#     standard config.
#   * If CONFIG_URL is set, a fresh config is downloaded and validated; on any
#     failure (network, bad JSON, missing keys) we fall back to the bundled
#     standard config. With CONFIG_REFRESH_INTERVAL>0 the config is re-checked
#     periodically and Psiphon is restarted when it changes.

set -e

TEMPLATE="/psiphon/psiphon.config"        # bundled standard config (fallback)
RUNTIME="/psiphon/data/psiphon.config"    # config actually passed to Psiphon
DATA_DIR="/psiphon/data"

mkdir -p "$DATA_DIR"

# Build the runtime config from the best valid source available, then force
# our container-specific paths/ports/region overrides on top of it.
build_config() {
    src="$TEMPLATE"

    if [ -n "$CONFIG_URL" ]; then
        if curl -fsS --max-time 20 "$CONFIG_URL" -o /tmp/fetched.config \
            && jq -e '.PropagationChannelId and .SponsorId and .RemoteServerListSignaturePublicKey' \
                  /tmp/fetched.config >/dev/null 2>&1; then
            echo "Using fetched config from CONFIG_URL."
            src="/tmp/fetched.config"
        else
            echo "WARN: CONFIG_URL unreachable or invalid; reverting to bundled standard config."
        fi
    fi

    # Validate whatever source we landed on; if even that is broken, hard-fall
    # back to the bundled template so Psiphon always gets valid JSON.
    if ! jq -e . "$src" >/dev/null 2>&1; then
        echo "WARN: source config is invalid JSON; using bundled standard config."
        src="$TEMPLATE"
    fi

    jq \
        --arg http   "${HTTP_PORT:-8080}" \
        --arg socks  "${SOCKS_PORT:-1080}" \
        --arg egress "${EGRESS_REGION:-}" \
        --arg device "${DEVICE_REGION:-}" \
        '.DataRootDirectory   = "/psiphon/data"
         | .ListenInterface   = "any"
         | .LocalHttpProxyPort  = ($http  | tonumber)
         | .LocalSocksProxyPort = ($socks | tonumber)
         | .EgressRegion      = $egress
         | .DeviceRegion      = $device' \
        "$src" > "$RUNTIME"
}

build_config

echo "Starting Psiphon ConsoleClient..."
/usr/local/bin/psiphon -config "$RUNTIME" &
PSIPHON_PID=$!

# Optional background auto-update: re-fetch on an interval and restart Psiphon
# (container restart policy brings us back up) only when the config changed.
# Launched after PSIPHON_PID is set so the subshell inherits the correct PID.
if [ -n "$CONFIG_URL" ] && [ "${CONFIG_REFRESH_INTERVAL:-0}" -gt 0 ] 2>/dev/null; then
    (
        while sleep "$CONFIG_REFRESH_INTERVAL"; do
            old_hash="$(md5sum < "$RUNTIME")"
            build_config
            new_hash="$(md5sum < "$RUNTIME")"
            if [ "$old_hash" != "$new_hash" ]; then
                echo "Psiphon config changed upstream; restarting to apply."
                kill "$PSIPHON_PID" 2>/dev/null || true
                break
            fi
        done
    ) &
fi

wait "$PSIPHON_PID"
