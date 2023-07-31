#!/bin/bash

TY_SMOKE_HOSTNAME="$1"
OLD_VERSION="$2"

NEW_VERSION="$(curl --silent "https://$TY_MAIN_HOSTNAME/-/build-info?$TY_METRICS_API_KEY" \
              | sed -nr 's/^docker tag: ([a-z0-9.-]+)$/\1/p')"


if [ -z "$OLD_VERSION" ]; then
  # Skip.
elif [ "$NEW_VERSION" > "$OLD_VERSION" ]; then
  echo "New version is newer than old version, fine:  $NEW_VERSION > $OLD_VERSION"
else
  echo "New version is *not* newer than old version, error:  $NEW_VERSION not > $OLD_VERSION"
  exit 1
fi


PING_RESP="$(curl --silent "https://$TY_MAIN_HOSTNAME/-/ping-cache-db")"
PING_RESP_LOWER="${PING_RESP,,}"  # converts to lowercase
GOOD_RESP="pong pong pong, from Play, Redis and Postgres. Found system user: true"
GOOD_RESP_LOWER="${GOOD_RESP,,}"  # converts to lowercase
if [ "$PING_RESP_LOWER" = "$GOOD_RESP_LOWER" ]; then
  echo "Could ping the app server, database and cache, fine."
else
  echo "Bad response when pinging the server, $TY_SMOKE_HOSTNAME:"
  echo "$PING_RESP"
  exit 1
fi


