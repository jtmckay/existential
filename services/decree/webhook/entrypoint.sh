#!/bin/sh
set -e
chown node:node /inbox
exec su-exec node node /app/server.js
