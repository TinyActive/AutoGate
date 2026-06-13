#!/bin/sh

echo "FreeConnect watchdog is running, ROTATING_DELAY = $ROTATING_DELAY"

while :
do
    sleep "$ROTATING_DELAY"
    echo "Watchdog: killing the current gost connection..."
    killall -SIGINT gost

    sleep 2
    echo "Watchdog: re-selecting a random FreeConnect upstream and reconnecting..."
    sh /freeconnect/freeconnect.sh &

    # random jitter so multiple freeconnect containers don't rotate in lockstep
    sleep $((RANDOM % 20))
done
