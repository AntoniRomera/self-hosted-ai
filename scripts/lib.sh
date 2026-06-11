#!/usr/bin/env bash
# Shared helpers for the Self-Hosted AI Stack scripts.
# Source this file; do not execute it directly.
#
#   source "$(dirname "$0")/lib.sh"

# --- Resolve project root (parent of this scripts/ directory) ---------------
# shellcheck disable=SC2155
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2155
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- Pretty logging ---------------------------------------------------------
_log() {
  # $1 = level, rest = message
  local level="$1"
  shift
  printf '%s [%s] %s\n' "$(date '+%H:%M:%S')" "${level}" "$*" >&2
}

log_info() { _log "INFO" "$@"; }
log_warn() { _log "WARN" "$@"; }
log_err() { _log "ERROR" "$@"; }

die() {
  log_err "$@"
  exit 1
}

# --- Detect the Compose binary ("docker compose" vs legacy "docker-compose") -
# Echoes the command to stdout; callers capture it into an array.
detect_compose() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  else
    die "Neither 'docker compose' nor 'docker-compose' is available. Install Docker Compose."
  fi
}

# Populated by callers via: read -r -a COMPOSE <<< "$(detect_compose)"
# then used as: "${COMPOSE[@]}" up -d

# --- Load .env into the environment -----------------------------------------
# Exports every KEY=VALUE pair found in PROJECT_ROOT/.env.
load_env() {
  local env_file="${PROJECT_ROOT}/.env"
  if [ ! -f "${env_file}" ]; then
    die "Missing ${env_file}. Run: cp .env.example .env  (then edit it)."
  fi
  # set -a exports all variables defined while sourcing the file.
  set -a
  # shellcheck disable=SC1090
  . "${env_file}"
  set +a
}

# --- Read a single value from .env without exporting everything -------------
# Usage: value="$(env_value OLLAMA_MODELS)"
env_value() {
  local key="$1"
  local env_file="${PROJECT_ROOT}/.env"
  [ -f "${env_file}" ] || die "Missing ${env_file}."
  # Grab the last definition, strip key=, surrounding quotes and inline noise.
  grep -E "^[[:space:]]*${key}=" "${env_file}" \
    | tail -n1 \
    | sed -E "s/^[[:space:]]*${key}=//; s/^\"(.*)\"$/\1/; s/^'(.*)'$/\1/"
}
