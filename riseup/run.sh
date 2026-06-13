#!/bin/sh

# Riseup VPN egress entrypoint.
#
# Brings up the Riseup OpenVPN tunnel (with random gateway selection), exposes
# it via tinyproxy bound to tun0, and rotates to a new random Riseup gateway on
# the ROTATING_DELAY watchdog schedule.

echo "Starting Riseup VPN egress service..."

sh /riseup/riseup.sh &
sh /riseup/tinyproxy.sh &
sh /riseup/watchdog.sh &

while :
do
    echo "Running.."
    sleep 180
done
