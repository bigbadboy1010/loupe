#!/bin/sh
set -eu

: "${TURN_SECRET:?TURN_SECRET is required and must match loupe-signaling TURN_SECRET}"
: "${TURN_REALM:=loupe.local}"
: "${TURN_PORT:=3478}"
: "${TURN_MIN_PORT:=49152}"
: "${TURN_MAX_PORT:=65535}"

set -- \
  --listening-port="$TURN_PORT" \
  --fingerprint \
  --use-auth-secret \
  --static-auth-secret="$TURN_SECRET" \
  --realm="$TURN_REALM" \
  --min-port="$TURN_MIN_PORT" \
  --max-port="$TURN_MAX_PORT" \
  --no-cli \
  --no-tlsv1 \
  --no-tlsv1_1 \
  --no-multicast-peers \
  --denied-peer-ip=10.0.0.0-10.255.255.255 \
  --denied-peer-ip=172.16.0.0-172.31.255.255 \
  --denied-peer-ip=192.168.0.0-192.168.255.255 \
  --denied-peer-ip=127.0.0.0-127.255.255.255 \
  --log-file=stdout \
  --verbose

if [ -n "${TURN_EXTERNAL_IP:-}" ]; then
  set -- "$@" --external-ip="$TURN_EXTERNAL_IP"
fi

exec turnserver "$@"
