# Vimalinx Suite

English | [中文](README.md)

Vimalinx Suite is the full stack for the Vimalinx Server channel:
- Server: `server`
- Plugin: `plugin`
- Android app (Vimagram): `app`

## Quickstart (local)

Prereqs: Node 22+ and the CLI.

```bash
npm install -g clawdbot@latest
```

Start the Vimalinx Server:

```bash
export TEST_SERVER_PORT=8788
export TEST_USERS_FILE=/path/to/vimalinx-users.json
export TEST_ALLOW_REGISTRATION=true

node server/server.mjs
```

Start the Gateway:

```bash
clawdbot gateway --port 18789 --verbose
```

Install + configure the plugin (one-liner after clone):

```bash
./install.sh
```

The script prompts for Server URL + token and writes the config (no onboard needed).
By default it runs: doctor --fix, gateway stop/start, channels status --probe (with a short wait).
Skip with: VIMALINX_SKIP_DOCTOR_FIX=1 / VIMALINX_SKIP_GATEWAY_START=1 / VIMALINX_SKIP_STATUS=1.
To overwrite an existing install: `VIMALINX_FORCE_OVERWRITE=1 ./install.sh`.

## Android app (Vimagram)

```bash
cd app
./gradlew :app:installDebug
```

Then log in to the server, generate a host token in **Account**, and paste it in the
plugin onboarding flow.

## Docs

- Server: `server/README.md`
- Plugin: `plugin/README.md`
- Android app: `app/README.md`
