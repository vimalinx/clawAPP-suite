#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
One-click deploy for Vimalinx Server + OpenClaw plugin.

Run as root:
  sudo bash scripts/deploy-server-oneclick.sh

Options:
  --repo <url>                     Git repository URL
  --repo-ref <ref>                 Git branch/tag/commit to checkout
  --install-dir <path>             Install directory (default: /opt/vimalinx-suite-core)
  --data-dir <path>                Data directory (default: /var/lib/vimalinx)
  --users-file <path>              Users file path (default: <data-dir>/users.json)
  --machines-file <path>           Machine pool file path (default: <data-dir>/machines.json)
  --port <port>                    Server port (default: 8788)
  --bind-host <host>               Bind host (default: 0.0.0.0)
  --inbound-mode <poll|webhook>    Server inbound mode (default: poll)
  --allow-registration <bool>      Allow registration (default: true)
  --invite-codes <csv>             Invite code list (comma-separated)
  --server-token <token>           Protect /send with global token
  --hmac-secret <secret>           Enable request signing secret
  --require-signature <bool>       Force signature validation
  --service-name <name>            Systemd service name (default: vimalinx-server)
  --env-file <path>                Environment file path (default: /etc/vimalinx-server.env)

OpenClaw integration options:
  --with-openclaw                  Enable OpenClaw integration on this machine
  --target-user <user>             OpenClaw owner user (default: sudo caller or root)
  --openclaw-base-url <url>        Channel baseUrl (default: http://127.0.0.1:<port>)
  --openclaw-config <path>         OpenClaw config path (default: ~/.openclaw/openclaw.json)
  --openclaw-user-id <id>          Channel userId
  --openclaw-token <token>         Channel token
  --openclaw-inbound-mode <mode>   Channel inbound mode (default: poll)
  --mode-account-map <pairs>       Mode route map, e.g. quick=default,code=code,deep=deep
  --skip-openclaw                  Skip plugin install and config update (default: true)
  --skip-plugin-install            Skip plugin install (still updates config)
  --skip-gateway-restart           Skip gateway restart/status probe
  --install-openclaw <bool>        Install openclaw if missing (default: true)

Examples:
  sudo bash scripts/deploy-server-oneclick.sh

  sudo VIMALINX_MODE_ACCOUNT_MAP="quick=default,code=code,deep=deep" \
    bash scripts/deploy-server-oneclick.sh --with-openclaw
EOF
}

is_true() {
  case "${1,,}" in
    1|y|yes|true|on) return 0 ;;
    *) return 1 ;;
  esac
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this script as root." >&2
    exit 1
  fi
}

detect_target_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    echo "${SUDO_USER}"
    return
  fi
  local login_user
  login_user="$(logname 2>/dev/null || true)"
  if [[ -n "${login_user}" && "${login_user}" != "root" ]]; then
    echo "${login_user}"
    return
  fi
  echo "root"
}

run_as_target() {
  local user="$1"
  local home_dir="$2"
  shift 2
  if [[ "${user}" == "root" ]]; then
    env HOME="${home_dir}" "$@"
  else
    sudo -u "${user}" -H env HOME="${home_dir}" "$@"
  fi
}

ensure_base_deps() {
  apt-get update -y
  apt-get install -y curl git ca-certificates rsync python3 openssl
}

ensure_node22() {
  if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
    return
  fi

  local node_major
  node_major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
  if [[ -z "${node_major}" || "${node_major}" -lt 22 ]]; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
  fi
}

parse_mode() {
  local value="$1"
  if [[ "${value}" != "poll" && "${value}" != "webhook" ]]; then
    echo "Invalid mode: ${value}. Expected poll or webhook." >&2
    exit 1
  fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

GIT_REPO="${VIMALINX_REPO:-https://github.com/vimalinx/vimalinx-suite-core}"
REPO_REF="${VIMALINX_REPO_REF:-}"
INSTALL_DIR="${VIMALINX_INSTALL_DIR:-/opt/vimalinx-suite-core}"
DATA_DIR="${VIMALINX_DATA_DIR:-/var/lib/vimalinx}"
USERS_FILE="${VIMALINX_USERS_FILE:-${DATA_DIR}/users.json}"
MACHINES_FILE="${VIMALINX_MACHINES_FILE:-${DATA_DIR}/machines.json}"
PORT="${VIMALINX_PORT:-8788}"
BIND_HOST="${VIMALINX_BIND_HOST:-0.0.0.0}"
INBOUND_MODE="${VIMALINX_INBOUND_MODE:-poll}"
ALLOW_REGISTRATION="${VIMALINX_ALLOW_REGISTRATION:-true}"
INVITE_CODES="${VIMALINX_INVITE_CODES:-}"
SERVER_TOKEN="${VIMALINX_SERVER_TOKEN:-}"
HMAC_SECRET="${VIMALINX_HMAC_SECRET:-}"
REQUIRE_SIGNATURE="${VIMALINX_REQUIRE_SIGNATURE:-}"
SERVICE_NAME="${VIMALINX_SERVICE_NAME:-vimalinx-server}"
ENV_FILE="${VIMALINX_ENV_FILE:-/etc/vimalinx-server.env}"

TARGET_USER="${VIMALINX_TARGET_USER:-}"
OPENCLAW_BASE_URL="${VIMALINX_OPENCLAW_BASE_URL:-}"
OPENCLAW_BASE_URL_EXPLICIT=false
if [[ -n "${OPENCLAW_BASE_URL}" ]]; then
  OPENCLAW_BASE_URL_EXPLICIT=true
fi
OPENCLAW_CONFIG="${VIMALINX_OPENCLAW_CONFIG:-}"
OPENCLAW_USER_ID="${VIMALINX_OPENCLAW_USER_ID:-}"
OPENCLAW_TOKEN="${VIMALINX_OPENCLAW_TOKEN:-}"
OPENCLAW_INBOUND_MODE="${VIMALINX_OPENCLAW_INBOUND_MODE:-poll}"
MODE_ACCOUNT_MAP="${VIMALINX_MODE_ACCOUNT_MAP:-quick=default,code=default,deep=default}"
SKIP_OPENCLAW="${VIMALINX_SKIP_OPENCLAW:-true}"
SKIP_PLUGIN_INSTALL="${VIMALINX_SKIP_PLUGIN_INSTALL:-false}"
SKIP_GATEWAY_RESTART="${VIMALINX_SKIP_GATEWAY_RESTART:-false}"
INSTALL_OPENCLAW="${VIMALINX_INSTALL_OPENCLAW:-true}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) GIT_REPO="${2:-}"; shift 2 ;;
    --repo-ref) REPO_REF="${2:-}"; shift 2 ;;
    --install-dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --data-dir) DATA_DIR="${2:-}"; shift 2 ;;
    --users-file) USERS_FILE="${2:-}"; shift 2 ;;
    --machines-file) MACHINES_FILE="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --bind-host) BIND_HOST="${2:-}"; shift 2 ;;
    --inbound-mode) INBOUND_MODE="${2:-}"; shift 2 ;;
    --allow-registration) ALLOW_REGISTRATION="${2:-}"; shift 2 ;;
    --invite-codes) INVITE_CODES="${2:-}"; shift 2 ;;
    --server-token) SERVER_TOKEN="${2:-}"; shift 2 ;;
    --hmac-secret) HMAC_SECRET="${2:-}"; shift 2 ;;
    --require-signature) REQUIRE_SIGNATURE="${2:-}"; shift 2 ;;
    --service-name) SERVICE_NAME="${2:-}"; shift 2 ;;
    --env-file) ENV_FILE="${2:-}"; shift 2 ;;
    --target-user) TARGET_USER="${2:-}"; shift 2 ;;
    --openclaw-base-url) OPENCLAW_BASE_URL="${2:-}"; OPENCLAW_BASE_URL_EXPLICIT=true; shift 2 ;;
    --openclaw-config) OPENCLAW_CONFIG="${2:-}"; shift 2 ;;
    --openclaw-user-id) OPENCLAW_USER_ID="${2:-}"; shift 2 ;;
    --openclaw-token) OPENCLAW_TOKEN="${2:-}"; shift 2 ;;
    --openclaw-inbound-mode) OPENCLAW_INBOUND_MODE="${2:-}"; shift 2 ;;
    --mode-account-map) MODE_ACCOUNT_MAP="${2:-}"; shift 2 ;;
    --with-openclaw) SKIP_OPENCLAW=false; shift 1 ;;
    --skip-openclaw) SKIP_OPENCLAW=true; shift 1 ;;
    --skip-plugin-install) SKIP_PLUGIN_INSTALL=true; shift 1 ;;
    --skip-gateway-restart) SKIP_GATEWAY_RESTART=true; shift 1 ;;
    --install-openclaw) INSTALL_OPENCLAW="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

need_root

parse_mode "${INBOUND_MODE}"
parse_mode "${OPENCLAW_INBOUND_MODE}"

if [[ -z "${TARGET_USER}" ]]; then
  TARGET_USER="$(detect_target_user)"
fi

if ! id -u "${TARGET_USER}" >/dev/null 2>&1; then
  echo "Target user not found: ${TARGET_USER}" >&2
  exit 1
fi

TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
if [[ -z "${TARGET_HOME}" ]]; then
  echo "Could not resolve home directory for user: ${TARGET_USER}" >&2
  exit 1
fi

if [[ "${OPENCLAW_BASE_URL_EXPLICIT}" != "true" ]]; then
  OPENCLAW_BASE_URL="http://127.0.0.1:${PORT}"
fi

if [[ -z "${OPENCLAW_CONFIG}" ]]; then
  OPENCLAW_CONFIG="${TARGET_HOME}/.openclaw/openclaw.json"
fi
OPENCLAW_EXT_DIR="${VIMALINX_OPENCLAW_EXT_DIR:-${TARGET_HOME}/.openclaw/extensions/vimalinx}"

ensure_base_deps
ensure_node22

if [[ -d "${INSTALL_DIR}/.git" ]]; then
  git -C "${INSTALL_DIR}" fetch --all --tags --prune
  if [[ -n "${REPO_REF}" ]]; then
    git -C "${INSTALL_DIR}" checkout "${REPO_REF}"
  else
    git -C "${INSTALL_DIR}" pull --ff-only
  fi
else
  git clone "${GIT_REPO}" "${INSTALL_DIR}"
  if [[ -n "${REPO_REF}" ]]; then
    git -C "${INSTALL_DIR}" checkout "${REPO_REF}"
  fi
fi

mkdir -p "${DATA_DIR}"
if [[ ! -f "${USERS_FILE}" ]]; then
  cp "${INSTALL_DIR}/server/users.example.json" "${USERS_FILE}"
fi
chmod 600 "${USERS_FILE}"

cat >"${ENV_FILE}" <<EOF
TEST_SERVER_PORT=${PORT}
TEST_BIND_HOST=${BIND_HOST}
TEST_USERS_FILE=${USERS_FILE}
TEST_USERS_WRITE_FILE=${USERS_FILE}
TEST_MACHINES_FILE=${MACHINES_FILE}
TEST_ALLOW_REGISTRATION=${ALLOW_REGISTRATION}
TEST_INVITE_CODES=${INVITE_CODES}
TEST_INBOUND_MODE=${INBOUND_MODE}
TEST_SERVER_TOKEN=${SERVER_TOKEN}
TEST_HMAC_SECRET=${HMAC_SECRET}
TEST_REQUIRE_SIGNATURE=${REQUIRE_SIGNATURE}
EOF
chmod 600 "${ENV_FILE}"

NODE_BIN="$(command -v node)"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

cat >"${SERVICE_FILE}" <<EOF
[Unit]
Description=Vimalinx Server
After=network.target

[Service]
Type=simple
EnvironmentFile=${ENV_FILE}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${NODE_BIN} ${INSTALL_DIR}/server/server.mjs
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}"
systemctl is-active --quiet "${SERVICE_NAME}"

OPENCLAW_BIN="$(command -v openclaw || true)"
if [[ -z "${OPENCLAW_BIN}" ]] && is_true "${INSTALL_OPENCLAW}"; then
  npm install -g openclaw@latest
  OPENCLAW_BIN="$(command -v openclaw || true)"
fi

if is_true "${SKIP_OPENCLAW}"; then
  echo "Skip OpenClaw integration on server machine (default behavior)."
elif [[ -z "${OPENCLAW_BIN}" ]]; then
  echo "openclaw not found; server deployed, but plugin/config was skipped." >&2
else
  if ! is_true "${SKIP_PLUGIN_INSTALL}"; then
    mkdir -p "$(dirname "${OPENCLAW_EXT_DIR}")"
    rsync -a --delete --exclude "node_modules" "${INSTALL_DIR}/plugin/" "${OPENCLAW_EXT_DIR}/"
    chown -R "${TARGET_USER}:${TARGET_USER}" "${OPENCLAW_EXT_DIR}"

    run_as_target "${TARGET_USER}" "${TARGET_HOME}" npm --prefix "${OPENCLAW_EXT_DIR}" install --omit=dev
    run_as_target "${TARGET_USER}" "${TARGET_HOME}" "${OPENCLAW_BIN}" plugins install "${OPENCLAW_EXT_DIR}" >/dev/null 2>&1 || true
    run_as_target "${TARGET_USER}" "${TARGET_HOME}" "${OPENCLAW_BIN}" plugins enable vimalinx >/dev/null 2>&1 || true
  fi

  run_as_target "${TARGET_USER}" "${TARGET_HOME}" python3 - "${OPENCLAW_CONFIG}" "${OPENCLAW_BASE_URL}" "${OPENCLAW_USER_ID}" "${OPENCLAW_TOKEN}" "${OPENCLAW_INBOUND_MODE}" "${MODE_ACCOUNT_MAP}" <<'PY'
import json
import os
import re
import sys

config_path, base_url, user_id, token, inbound_mode, raw_mode_map = sys.argv[1:7]

mode_key_pattern = re.compile(r"^[a-z0-9_-]{1,32}$")
account_pattern = re.compile(r"^[a-z0-9_-]{1,64}$")

def parse_mode_map(raw: str):
  out = {}
  for chunk in raw.split(","):
    item = chunk.strip()
    if not item or "=" not in item:
      continue
    key, value = item.split("=", 1)
    mode = key.strip().lower()
    account = value.strip().lower()
    if not mode_key_pattern.match(mode):
      continue
    if not account_pattern.match(account):
      continue
    out[mode] = account
  return out

cfg = {}
if os.path.exists(config_path):
  with open(config_path, "r", encoding="utf-8") as f:
    try:
      cfg = json.load(f)
    except json.JSONDecodeError:
      cfg = {}

channels = cfg.get("channels")
if not isinstance(channels, dict):
  channels = {}

vimalinx = channels.get("vimalinx")
if not isinstance(vimalinx, dict):
  vimalinx = {}

vimalinx["enabled"] = True
vimalinx["baseUrl"] = base_url.rstrip("/")
vimalinx["inboundMode"] = inbound_mode
if user_id:
  vimalinx["userId"] = user_id
if token:
  vimalinx["token"] = token

vimalinx.setdefault("dmPolicy", "open")
vimalinx.setdefault("allowFrom", ["*"])

mode_map = parse_mode_map(raw_mode_map)
if mode_map:
  vimalinx["modeAccountMap"] = mode_map

channels["vimalinx"] = vimalinx
cfg["channels"] = channels

plugins = cfg.get("plugins")
if not isinstance(plugins, dict):
  plugins = {}

entries = plugins.get("entries")
if not isinstance(entries, dict):
  entries = {}
entry = entries.get("vimalinx")
if not isinstance(entry, dict):
  entry = {}
entry["enabled"] = True
entries["vimalinx"] = entry
plugins["entries"] = entries
cfg["plugins"] = plugins

config_dir = os.path.dirname(config_path)
if config_dir:
  os.makedirs(config_dir, exist_ok=True)
with open(config_path, "w", encoding="utf-8") as f:
  json.dump(cfg, f, indent=2, ensure_ascii=True)
  f.write("\n")

print("OpenClaw config updated:", config_path)
PY

  if ! is_true "${SKIP_GATEWAY_RESTART}"; then
    run_as_target "${TARGET_USER}" "${TARGET_HOME}" "${OPENCLAW_BIN}" gateway stop >/dev/null 2>&1 || true
    run_as_target "${TARGET_USER}" "${TARGET_HOME}" "${OPENCLAW_BIN}" gateway start >/dev/null 2>&1 || true
    run_as_target "${TARGET_USER}" "${TARGET_HOME}" "${OPENCLAW_BIN}" channels status --probe || true
  fi
fi

echo
echo "Done."
echo "- Service: ${SERVICE_NAME}"
echo "- Env file: ${ENV_FILE}"
echo "- Users file: ${USERS_FILE}"
echo "- Machines file: ${MACHINES_FILE}"
echo "- Server URL: http://<your-server-ip>:${PORT}"
if is_true "${SKIP_OPENCLAW}"; then
  echo "- Next (on your local OpenClaw machine):"
  echo "  git clone ${GIT_REPO}"
  echo "  cd vimalinx-suite-core"
  echo "  # First create contributor token in http://<server-ip>:${PORT}/admin"
  echo "  bash scripts/deploy-openclaw-node.sh --server-url http://<server-ip>:${PORT} --token <contributor-token>"
elif [[ -z "${OPENCLAW_USER_ID}" || -z "${OPENCLAW_TOKEN}" ]]; then
  echo "- OpenClaw user/token not provided. Set channels.vimalinx.userId/token later if needed."
fi
