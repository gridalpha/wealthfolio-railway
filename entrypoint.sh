#!/bin/sh
# Wealthfolio entrypoint for Railway. Fills in the values Railway variables cannot
# express, then hands the container back to the image's own unprivileged user.
set -eu

log() { echo "[wf-entrypoint] $*"; }
die() { echo "[wf-entrypoint] FATAL: $*" >&2; exit 1; }

DATA_DIR=/data

# A Railway volume mounts over /data as root and hides the chown the image did at
# build time. The server runs as uid 1000, so re-apply it on every boot.
mkdir -p "$DATA_DIR"
chown -R 1000:1000 "$DATA_DIR"

: "${PORT:=8088}"
: "${WF_LISTEN_ADDR:=0.0.0.0:${PORT}}"
: "${WF_DB_PATH:=${DATA_DIR}/wealthfolio.db}"
: "${WF_STATIC_DIR:=/app/dist}"
# Railway always terminates TLS at its edge, so the session cookie is always
# eligible for Secure. "auto" would also work (the edge sends X-Forwarded-Proto)
# but depends on a header the platform health probe does not send.
: "${WF_COOKIE_SECURE:=always}"

# The server refuses to start with WF_CORS_ALLOW_ORIGINS="*" while auth is on, so
# name the deployment's own origin. Railway injects RAILWAY_PUBLIC_DOMAIN itself,
# which keeps this out of the template's variable list entirely.
if [ -z "${WF_CORS_ALLOW_ORIGINS:-}" ]; then
  if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
    WF_CORS_ALLOW_ORIGINS="https://${RAILWAY_PUBLIC_DOMAIN}"
  else
    WF_CORS_ALLOW_ORIGINS="http://localhost:${PORT}"
  fi
fi
log "cors origin ${WF_CORS_ALLOW_ORIGINS}"

# ---------------------------------------------------------------- secret key --
# decode_secret_key() accepts base64 that decodes to exactly 32 bytes, or a
# 32-character string that is *not* valid base64. A random alphanumeric value —
# which is what ${{secret(N)}} produces — is valid base64 of the wrong length, so
# the server would panic on "JWT secret must decode to exactly 32 bytes". Fold
# anything that is not already a 32-byte key through SHA-256: deterministic, so
# every boot derives the identical key and nothing encrypted at rest is orphaned.
[ -n "${WF_SECRET_KEY:-}" ] || die "WF_SECRET_KEY is not set."
key_len=$(printf '%s' "$WF_SECRET_KEY" | openssl base64 -d -A 2>/dev/null | wc -c | tr -d ' ')
if [ "$key_len" = "32" ]; then
  log "secret key used as supplied (already 32 bytes)"
else
  WF_SECRET_KEY=$(printf '%s' "$WF_SECRET_KEY" | openssl dgst -sha256 -binary | openssl base64 -A)
  log "secret key normalised to 32 bytes via SHA-256"
fi

# -------------------------------------------------------------- password hash --
# Login verifies against an Argon2id PHC string. ${{secret(N)}} emits random bytes
# and cannot hash, so a template deployer could never produce one by hand.
if [ -n "${WF_AUTH_PASSWORD_HASH:-}" ]; then
  log "auth: using the supplied WF_AUTH_PASSWORD_HASH"
elif [ -n "${WF_AUTH_PASSWORD:-}" ]; then
  salt=$(openssl rand -hex 8)
  WF_AUTH_PASSWORD_HASH=$(printf '%s' "$WF_AUTH_PASSWORD" | argon2 "$salt" -id -t 3 -m 16 -p 1 -e)
  case "$WF_AUTH_PASSWORD_HASH" in
    '$argon2id$'*) log "auth: derived an Argon2id hash from WF_AUTH_PASSWORD" ;;
    *) die "argon2 did not return a PHC string" ;;
  esac
else
  die "set WF_AUTH_PASSWORD to the password you want to log in with (or supply WF_AUTH_PASSWORD_HASH yourself)."
fi
# The server never reads the plaintext; do not leave it in its environment.
unset WF_AUTH_PASSWORD

export WF_LISTEN_ADDR WF_DB_PATH WF_STATIC_DIR WF_COOKIE_SECURE \
       WF_CORS_ALLOW_ORIGINS WF_SECRET_KEY WF_AUTH_PASSWORD_HASH

log "starting wealthfolio-server on ${WF_LISTEN_ADDR} (db ${WF_DB_PATH})"
exec su-exec 1000:1000 /usr/local/bin/wealthfolio-server
