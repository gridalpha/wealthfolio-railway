# wealthfolio-railway

Deployment wrapper that runs [Wealthfolio](https://github.com/wealthfolio/wealthfolio)
— a private, local-first personal finance and investment tracker — on
[Railway](https://railway.com).

It is a thin layer over the official `wealthfolio/wealthfolio` image. The image
itself is unmodified; `entrypoint.sh` only fills in the three things a Railway
variable cannot express, then drops back to the image's own unprivileged user.

## Why a wrapper is needed

| Gap | What the entrypoint does |
|---|---|
| `WF_AUTH_PASSWORD_HASH` is an Argon2id PHC string, and no Railway variable can hash | Derives it at boot from the plain `WF_AUTH_PASSWORD` you set |
| `WF_SECRET_KEY` must decode to exactly 32 bytes, which a random alphanumeric value does not | Folds any other value through SHA-256, deterministically, so the key is identical on every boot |
| A Railway volume mounts over `/data` as root, hiding the image's build-time chown | Re-applies `chown 1000:1000` before starting, then `su-exec`s to uid 1000 |

## Variables

| Variable | Required | Notes |
|---|---|---|
| `WF_AUTH_PASSWORD` | yes | The password you sign in with. Wealthfolio is single-user, so there is no username. |
| `WF_SECRET_KEY` | yes | Encrypts stored credentials and signs sessions. Any value works; keep it stable or stored secrets become unreadable. |
| `PORT` | no | Defaults to `8088`. |
| `WF_CORS_ALLOW_ORIGINS` | no | Defaults to `https://$RAILWAY_PUBLIC_DOMAIN`. Set it when you serve the app from a custom domain. |
| `WF_AUTH_PASSWORD_HASH` | no | Supply your own Argon2id PHC string instead of letting the entrypoint derive one. |
| `WF_COOKIE_SECURE` | no | Defaults to `always`, which is correct behind Railway's TLS edge. |
| `WF_MCP_ENABLED` | no | Defaults to `false`. Enabling it exposes an MCP endpoint for AI agents; it requires auth to be configured. |
| `WF_OIDC_*` | no | Optional SSO. See upstream's `.env.web.example`. |

## Storage

One volume at `/data`, holding the SQLite database, the encrypted secrets file and
any installed addons. Wealthfolio has no external database: storage is embedded
SQLite, and its background schedulers run in-process, so it runs as a single
instance.

## Licence

Wealthfolio is AGPL-3.0. This repository contains only packaging (a Dockerfile and
an entrypoint script) and claims no rights over the application itself.
