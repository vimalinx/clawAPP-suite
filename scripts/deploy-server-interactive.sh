#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Interactive server installer.

Usage:
  bash scripts/deploy-server-interactive.sh

This wizard collects options and then runs:
  scripts/deploy-server-oneclick.sh
EOF
}

ask_with_default() {
  local prompt="$1"
  local default_value="$2"
  local answer=""
  read -r -p "${prompt} [${default_value}]: " answer
  if [[ -z "${answer}" ]]; then
    printf '%s\n' "${default_value}"
  else
    printf '%s\n' "${answer}"
  fi
}

ask_optional() {
  local prompt="$1"
  local answer=""
  read -r -p "${prompt}: " answer
  printf '%s\n' "${answer}"
}

ask_secret_optional() {
  local prompt="$1"
  local answer=""
  read -r -s -p "${prompt}: " answer
  printf '\n'
  printf '%s\n' "${answer}"
}

ask_yes_no() {
  local prompt="$1"
  local default_choice="$2"
  local raw_default="${default_choice,,}"
  local answer=""
  while true; do
    read -r -p "${prompt} [${default_choice}]: " answer
    answer="${answer:-${default_choice}}"
    answer="${answer,,}"
    case "${answer}" in
      y|yes) printf 'true\n'; return ;;
      n|no) printf 'false\n'; return ;;
      *)
        if [[ "${raw_default}" == "y" || "${raw_default}" == "yes" ]]; then
          printf 'Please answer y or n.\n'
        else
          printf 'Please answer y or n.\n'
        fi
        ;;
    esac
  done
}

run_as_root_if_needed() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy-server-oneclick.sh"

if [[ ! -f "${DEPLOY_SCRIPT}" ]]; then
  echo "Missing script: ${DEPLOY_SCRIPT}" >&2
  exit 1
fi

DEFAULT_REPO_URL="${VIMALINX_REPO:-https://github.com/vimalinx/ClawNet.git}"
DEFAULT_REPO_REF="${VIMALINX_REPO_REF:-main}"
DEFAULT_INSTALL_DIR="${VIMALINX_INSTALL_DIR:-/opt/vimalinx-suite-core}"
DEFAULT_DATA_DIR="${VIMALINX_DATA_DIR:-/var/lib/vimalinx}"
DEFAULT_PORT="${VIMALINX_PORT:-18788}"
DEFAULT_BIND_HOST="${VIMALINX_BIND_HOST:-0.0.0.0}"
DEFAULT_SERVICE_NAME="${VIMALINX_SERVICE_NAME:-vimalinx-server}"
DEFAULT_ALLOW_REGISTRATION="${VIMALINX_ALLOW_REGISTRATION:-true}"

echo
echo "== VimaClawNet Server Interactive Installer =="
echo

REPO_URL="$(ask_with_default "Repository URL" "${DEFAULT_REPO_URL}")"
REPO_REF="$(ask_with_default "Repository ref (branch/tag/commit)" "${DEFAULT_REPO_REF}")"
INSTALL_DIR="$(ask_with_default "Install directory" "${DEFAULT_INSTALL_DIR}")"
DATA_DIR="$(ask_with_default "Data directory" "${DEFAULT_DATA_DIR}")"
PORT="$(ask_with_default "Server port" "${DEFAULT_PORT}")"
BIND_HOST="$(ask_with_default "Bind host" "${DEFAULT_BIND_HOST}")"
SERVICE_NAME="$(ask_with_default "Systemd service name" "${DEFAULT_SERVICE_NAME}")"
ALLOW_REGISTRATION="$(ask_with_default "Allow app registration (true/false)" "${DEFAULT_ALLOW_REGISTRATION}")"
INVITE_CODES="$(ask_optional "Invite codes CSV (optional)")"

GENERATE_TOKEN="$(ask_yes_no "Generate admin token now" "Y")"
SERVER_TOKEN=""
if [[ "${GENERATE_TOKEN}" == "true" ]]; then
  SERVER_TOKEN="$(openssl rand -hex 24)"
  echo "Generated admin token. Keep it safe."
else
  SERVER_TOKEN="$(ask_secret_optional "Admin token (optional, empty disables admin APIs)")"
fi

ENABLE_HMAC="$(ask_yes_no "Enable HMAC request signature" "N")"
HMAC_SECRET=""
REQUIRE_SIGNATURE=""
if [[ "${ENABLE_HMAC}" == "true" ]]; then
  HMAC_SECRET="$(ask_secret_optional "HMAC secret")"
  REQUIRE_SIGNATURE="true"
fi

WITH_OPENCLAW="$(ask_yes_no "Install OpenClaw integration on this server machine" "N")"
TARGET_USER=""
OPENCLAW_BASE_URL=""
OPENCLAW_USER_ID=""
OPENCLAW_TOKEN=""
MODE_ACCOUNT_MAP=""
if [[ "${WITH_OPENCLAW}" == "true" ]]; then
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    DEFAULT_TARGET_USER="${SUDO_USER}"
  else
    DEFAULT_TARGET_USER="$(id -un)"
  fi
  TARGET_USER="$(ask_with_default "OpenClaw target user" "${DEFAULT_TARGET_USER}")"
  OPENCLAW_BASE_URL="$(ask_with_default "OpenClaw base URL" "http://127.0.0.1:${PORT}")"
  OPENCLAW_USER_ID="$(ask_optional "OpenClaw userId (optional)")"
  OPENCLAW_TOKEN="$(ask_secret_optional "OpenClaw token (optional)")"
  MODE_ACCOUNT_MAP="$(ask_with_default "modeAccountMap" "quick=default,code=default,deep=default")"
fi

echo
echo "Install summary"
echo "- Repo: ${REPO_URL}"
echo "- Ref: ${REPO_REF}"
echo "- Install dir: ${INSTALL_DIR}"
echo "- Data dir: ${DATA_DIR}"
echo "- Port: ${PORT}"
echo "- Bind host: ${BIND_HOST}"
echo "- Service: ${SERVICE_NAME}"
echo "- Allow registration: ${ALLOW_REGISTRATION}"
if [[ -n "${INVITE_CODES}" ]]; then
  echo "- Invite codes: ${INVITE_CODES}"
fi
if [[ -n "${SERVER_TOKEN}" ]]; then
  echo "- Admin token: [set]"
else
  echo "- Admin token: [empty]"
fi
if [[ "${WITH_OPENCLAW}" == "true" ]]; then
  echo "- OpenClaw on server machine: enabled"
else
  echo "- OpenClaw on server machine: disabled"
fi

PROCEED="$(ask_yes_no "Run deployment now" "Y")"
if [[ "${PROCEED}" != "true" ]]; then
  echo "Cancelled."
  exit 0
fi

cmd=(
  bash
  "${DEPLOY_SCRIPT}"
  --repo "${REPO_URL}"
  --install-dir "${INSTALL_DIR}"
  --data-dir "${DATA_DIR}"
  --port "${PORT}"
  --bind-host "${BIND_HOST}"
  --service-name "${SERVICE_NAME}"
  --allow-registration "${ALLOW_REGISTRATION}"
)

if [[ -n "${REPO_REF}" ]]; then
  cmd+=(--repo-ref "${REPO_REF}")
fi
if [[ -n "${INVITE_CODES}" ]]; then
  cmd+=(--invite-codes "${INVITE_CODES}")
fi
if [[ -n "${SERVER_TOKEN}" ]]; then
  cmd+=(--server-token "${SERVER_TOKEN}")
fi
if [[ -n "${HMAC_SECRET}" ]]; then
  cmd+=(--hmac-secret "${HMAC_SECRET}")
fi
if [[ -n "${REQUIRE_SIGNATURE}" ]]; then
  cmd+=(--require-signature "${REQUIRE_SIGNATURE}")
fi

if [[ "${WITH_OPENCLAW}" == "true" ]]; then
  cmd+=(--with-openclaw --target-user "${TARGET_USER}" --openclaw-base-url "${OPENCLAW_BASE_URL}")
  if [[ -n "${OPENCLAW_USER_ID}" ]]; then
    cmd+=(--openclaw-user-id "${OPENCLAW_USER_ID}")
  fi
  if [[ -n "${OPENCLAW_TOKEN}" ]]; then
    cmd+=(--openclaw-token "${OPENCLAW_TOKEN}")
  fi
  if [[ -n "${MODE_ACCOUNT_MAP}" ]]; then
    cmd+=(--mode-account-map "${MODE_ACCOUNT_MAP}")
  fi
fi

run_as_root_if_needed "${cmd[@]}"

echo
echo "Interactive server deployment finished."
echo "Admin console: http://<server-ip>:${PORT}/admin"
if [[ -n "${SERVER_TOKEN}" ]]; then
  echo "Admin token: ${SERVER_TOKEN}"
fi
