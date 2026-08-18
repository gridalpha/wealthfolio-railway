# Wealthfolio on Railway.
#
# A thin wrapper over the official image. Upstream ships a complete container; the
# three gaps below are Railway-shaped and are all closed at boot by entrypoint.sh:
#
#   1. WF_AUTH_PASSWORD_HASH is an Argon2id PHC string. No Railway variable can
#      hash, so the entrypoint derives it from a plain password.
#   2. WF_SECRET_KEY must decode to exactly 32 bytes. A random alphanumeric value
#      is valid base64 of the wrong length and panics the server, so anything that
#      is not already a 32-byte key is folded through SHA-256.
#   3. A Railway volume mounts over /data owned by root, hiding the image's
#      build-time chown, while the server runs as uid 1000.
#
# Upstream: https://github.com/wealthfolio/wealthfolio (AGPL-3.0)
FROM wealthfolio/wealthfolio:latest

# Root only so the entrypoint can chown the volume; it drops back to uid 1000
# before exec'ing the server, so the app never runs privileged.
USER root

# argon2  — derives the password hash
# openssl — normalises the secret key and generates the salt
# su-exec — drops privileges without an intermediate shell
# tini    — PID 1 that forwards SIGTERM, which the server does not handle itself
RUN apk add --no-cache argon2 openssl su-exec tini

# WF_STATIC_DIR defaults to the relative path "dist"; pin it absolutely so the
# frontend is found regardless of the working directory.
ENV WF_STATIC_DIR=/app/dist

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8088
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
