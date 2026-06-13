#!/bin/sh

echo "Running Tinyproxy HTTP proxy server (Riseup egress)."

get_addr() {
    ip -4 addr show dev "$1" 2>/dev/null \
        | grep -oE 'inet [0-9.]+' \
        | head -n1 \
        | cut -d ' ' -f 2
}

# Wait until tun0 not only exists but actually has an IPv4 address assigned.
# OpenVPN creates the tun0 link slightly before it assigns the address, so
# checking only for the link causes a race where the address is still empty.
until [ -n "$(get_addr tun0)" ]; do
    echo 'Tunnel not found (or no address yet), sleep...'
    sleep 2
done

addr_eth=${LISTEN_ON:-$(get_addr eth0)}
addr_tun=$(get_addr tun0)

# Bind outgoing traffic to the VPN interface address. Without a valid address
# tinyproxy fails with "Syntax error" on the Bind line, so guard against empty.
if [ -z "$addr_tun" ]; then
    echo "ERROR: could not determine tun0 address, aborting tinyproxy start"
    exit 1
fi

if [ -n "$addr_eth" ]; then
    sed -i -e "/^Listen/c Listen $addr_eth" /riseup/tinyproxy.conf
else
    echo "WARNING: could not determine eth0 address, listening on all interfaces"
    sed -i -e "/^Listen/d" /riseup/tinyproxy.conf
fi

sed -i -e "/^Bind/c Bind $addr_tun" /riseup/tinyproxy.conf

echo "Found tun0 interface ($addr_tun). Starting tinyproxy"

tinyproxy -c "/riseup/tinyproxy.conf"
