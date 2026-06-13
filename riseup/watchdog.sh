#!/bin/sh

echo "Riseup watchdog is running, ROTATING_DELAY = $ROTATING_DELAY"

while :
do
    sleep "$ROTATING_DELAY"
    echo "Watchdog: killing the current connections..."
    killall -SIGINT openvpn
    killall -SIGINT tinyproxy

    sleep 2
    echo "Watchdog: re-selecting a random Riseup gateway and reconnecting..."
    sh /riseup/riseup.sh &
    sh /riseup/tinyproxy.sh &

    sleep 120

    # random jitter so multiple riseup containers don't rotate in lockstep
    sleep $((RANDOM % 20))
done
