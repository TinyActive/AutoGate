#!/bin/sh

# Riseup VPN egress for AutoGate.
#
# Riseup runs the open-source LEAP / Bitmask platform on top of OpenVPN. A
# public API (no account needed) hands out:
#   * the VPN CA certificate           -> https://black.riseup.net/ca.crt
#   * an anonymous client cert + key   -> https://api.black.riseup.net/3/cert
#   * the live gateway list            -> https://api.black.riseup.net/3/config/eip-service.json
#
# This script bootstraps those three pieces, then performs the REQUIRED step of
# *randomly selecting one server* from Riseup's advertised gateway list and
# builds a single-remote OpenVPN profile for it. OpenVPN brings up tun0 and the
# companion tinyproxy.sh exposes it as an HTTP proxy that HAProxy chains to as
# one more rotating egress path (same role as WARP / Psiphon / ProxyBroker2).

set -e

DATA_DIR="/riseup/data"
CA_CRT="$DATA_DIR/ca.crt"
CLIENT_PEM="$DATA_DIR/client.pem"
OVPN_CONF="$DATA_DIR/riseup.ovpn"
GATEWAYS_JSON="$DATA_DIR/eip-service.json"

CA_URL="${RISEUP_CA_URL:-https://black.riseup.net/ca.crt}"
CERT_URL="${RISEUP_CERT_URL:-https://api.black.riseup.net/3/cert}"
EIP_URL="${RISEUP_EIP_URL:-https://api.black.riseup.net/3/config/eip-service.json}"

# Optional filters (empty = no filter):
#   RISEUP_LOCATION  e.g. "Paris", "Amsterdam", "Seattle"
#   RISEUP_PROTO     "udp" or "tcp"  (default: udp)
LOCATION="${RISEUP_LOCATION:-}"
PROTO="${RISEUP_PROTO:-udp}"

mkdir -p "$DATA_DIR"

fetch() {
    # fetch <url> <dest> <description>
    curl -fsS --connect-timeout 15 --retry 3 --retry-delay 2 \
        -H "Accept: */*" "$1" -o "$2"
}

# 1) VPN CA cert (used inside the OpenVPN profile to verify the gateway).
#    Reuse a cached copy if the network is briefly unavailable.
if fetch "$CA_URL" "$CA_CRT.new" "CA"; then
    mv "$CA_CRT.new" "$CA_CRT"
elif [ ! -s "$CA_CRT" ]; then
    echo "ERROR: could not fetch Riseup CA cert and no cached copy exists."
    exit 1
fi

# 2) Anonymous client certificate + private key (single PEM blob, ~90d valid).
if fetch "$CERT_URL" "$CLIENT_PEM.new" "client cert"; then
    mv "$CLIENT_PEM.new" "$CLIENT_PEM"
elif [ ! -s "$CLIENT_PEM" ]; then
    echo "ERROR: could not fetch Riseup client cert and no cached copy exists."
    exit 1
fi

# 3) Live gateway list.
if fetch "$EIP_URL" "$GATEWAYS_JSON.new" "gateway list" \
    && jq -e '.gateways | length > 0' "$GATEWAYS_JSON.new" >/dev/null 2>&1; then
    mv "$GATEWAYS_JSON.new" "$GATEWAYS_JSON"
elif [ ! -s "$GATEWAYS_JSON" ]; then
    echo "ERROR: could not fetch Riseup gateway list and no cached copy exists."
    exit 1
else
    echo "WARN: gateway list refresh failed; using cached list."
fi

# --- REQUIRED STEP: random server selection from Riseup's list --------------
# Flatten every openvpn-capable (gateway, port, protocol) combination, honour
# the optional location/proto filters, then pick ONE at random with shuf.
candidates() {
    jq -r --arg loc "$LOCATION" --arg proto "$PROTO" '
        .gateways[]
        | . as $g
        | ($g.capabilities.transport[] | select(.type == "openvpn")) as $t
        | $t.protocols[] as $p
        | $t.ports[] as $port
        | select(($loc == "" or $g.location == $loc)
                 and ($proto == "" or $p == $proto))
        | "\($g.ip_address) \($port) \($p) \($g.host) \($g.location)"
    ' "$GATEWAYS_JSON"
}

SELECTED="$(candidates | shuf -n1)"

# Fall back to "any proto" if the requested proto/location combo matched nothing.
if [ -z "$SELECTED" ]; then
    echo "WARN: no gateway matched (location='$LOCATION' proto='$PROTO'); ignoring filters."
    PROTO=""
    LOCATION=""
    SELECTED="$(candidates | shuf -n1)"
fi

if [ -z "$SELECTED" ]; then
    echo "ERROR: no usable OpenVPN gateway found in Riseup list."
    exit 1
fi

REMOTE_IP="$(echo "$SELECTED" | awk '{print $1}')"
REMOTE_PORT="$(echo "$SELECTED" | awk '{print $2}')"
REMOTE_PROTO="$(echo "$SELECTED" | awk '{print $3}')"
REMOTE_HOST="$(echo "$SELECTED" | awk '{print $4}')"
REMOTE_LOC="$(echo "$SELECTED" | cut -d' ' -f5-)"

echo "Riseup: randomly selected gateway $REMOTE_HOST ($REMOTE_LOC) -> ${REMOTE_IP}:${REMOTE_PORT}/${REMOTE_PROTO}"

# --- Build the single-remote OpenVPN profile -------------------------------
# Cipher/auth/tls settings mirror Riseup's published openvpn_configuration.
{
    echo "client"
    echo "dev tun"
    echo "proto $REMOTE_PROTO"
    echo "remote $REMOTE_IP $REMOTE_PORT"
    echo "nobind"
    echo "remote-cert-tls server"
    echo "auth SHA512"
    echo "cipher AES-256-GCM"
    echo "data-ciphers AES-256-GCM"
    echo "tls-version-min 1.2"
    echo "persist-key"
    echo "persist-tun"
    echo "pull-filter ignore \"ping\""
    echo "pull-filter ignore \"ping-restart\""
    echo "pull-filter ignore \"keepalive\""
    echo "keepalive 10 30"
    echo "server-poll-timeout 10"
    echo "connect-retry 1 2"
    echo "connect-retry-max 1"
    echo "auth-nocache"
    echo "verb 3"
    echo "<ca>"
    cat "$CA_CRT"
    echo "</ca>"
    echo "<cert>"
    sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "$CLIENT_PEM"
    echo "</cert>"
    echo "<key>"
    sed -n '/BEGIN .*PRIVATE KEY/,/END .*PRIVATE KEY/p' "$CLIENT_PEM"
    echo "</key>"
} > "$OVPN_CONF"

echo "Riseup: starting OpenVPN..."
exec openvpn --config "$OVPN_CONF"
