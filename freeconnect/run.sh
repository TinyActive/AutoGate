#!/bin/sh

# FreeConnect HTTPS-proxy egress entrypoint.
#
# Brings up gost chained to a random upstream FreeConnect HTTPS proxy, exposes
# it locally as a plain HTTP proxy on :8080, and rotates to a new random
# upstream on the ROTATING_DELAY watchdog schedule.

echo "Starting FreeConnect HTTPS-proxy egress service..."

sh /freeconnect/freeconnect.sh &
sh /freeconnect/watchdog.sh &

while :
do
    echo "Running.."
    sleep 180
done
