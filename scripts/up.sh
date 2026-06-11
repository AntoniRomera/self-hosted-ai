#!/usr/bin/env bash
#
# up.sh - bring the stack up and preload models.
#
# Validates that .env exists and required secrets are set, starts the stack in
# the background, waits for health, then pulls the configured models.
#
# Usage:
#   scripts/up.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "${SCRIPT_DIR}/lib.sh"

cd "${PROJECT_ROOT}"

read -r -a COMPOSE <<<"$(detect_compose)"

# --- Pre-flight checks -------------------------------------------------------
[ -f "${PROJECT_ROOT}/.env" ] || die "Missing .env. Run: cp .env.example .env  (then edit it)."

check_secret() {
  local key="$1"
  local placeholder="$2"
  local value
  value="$(env_value "${key}")"
  if [ -z "${value}" ]; then
    die "${key} is not set in .env."
  fi
  if [ -n "${placeholder}" ] && [ "${value}" = "${placeholder}" ]; then
    die "${key} still holds the example placeholder. Set a real value in .env."
  fi
}

check_secret "TS_AUTHKEY" "tskey-auth-REPLACE-ME"
check_secret "WEBUI_SECRET_KEY" "change-me-generate-with-openssl-rand-hex-32"

# --- Bring the stack up ------------------------------------------------------
log_info "Starting the stack..."
"${COMPOSE[@]}" up -d

# --- Preload models ----------------------------------------------------------
log_info "Preloading models..."
"${SCRIPT_DIR}/preload-models.sh"

# --- Report tailnet URL ------------------------------------------------------
TS_HOSTNAME="$(env_value TS_HOSTNAME)"
log_info "Stack is up."
log_info "Reach Open WebUI on your tailnet at: https://${TS_HOSTNAME:-self-hosted-ai}.<your-tailnet>.ts.net"
log_info "Check status with: make logs"
