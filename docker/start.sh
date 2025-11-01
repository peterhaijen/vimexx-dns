#!/bin/sh

# Respond to SIGTERM to avoid a SIGKILL later
cleanup() {
    echo "Caught SIGTERM, shutting down cleanly..."
    kill $pid
    wait "$pid"
    exit 0
}

trap cleanup TERM

# Run the perl script every few minutes

while true; do
  /root/vimexx-dns -verbose -t 5m -ddns $VIMEXX_DNS_DOMAIN &
  pid=$!
  wait "$pid"

  sleep ${VIMEXX_SLEEP:-30} &
  pid=$!
  wait "$pid"
done
