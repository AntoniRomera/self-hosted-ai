#!/usr/bin/env bash
#
# preload-models.sh - pull every model listed in OLLAMA_MODELS into Ollama.
#
# Waits for the ollama container to be healthy, then runs `ollama pull` for
# each comma-separated model. Idempotent: already-present models are skipped
# quickly by Ollama itself.
#
# Usage:
#   scripts/preload-models.sh                 # uses OLLAMA_MODELS from .env
#   OLLAMA_MODELS="llama3.2:3b" scripts/preload-models.sh   # override
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "${SCRIPT_DIR}/lib.sh"

cd "${PROJECT_ROOT}"

read -r -a COMPOSE <<<"$(detect_compose)"

# Resolve model list: explicit env var wins, otherwise read it from .env.
MODELS_RAW="${OLLAMA_MODELS:-$(env_value OLLAMA_MODELS)}"
[ -n "${MODELS_RAW}" ] || die "OLLAMA_MODELS is empty. Set it in .env."

# --- Wait until the ollama service reports healthy ---------------------------
wait_for_ollama() {
  local retries=40
  local delay=3
  log_info "Waiting for the ollama container to become healthy..."
  for ((i = 1; i <= retries; i++)); do
    if "${COMPOSE[@]}" exec -T ollama ollama --version >/dev/null 2>&1; then
      log_info "Ollama is ready."
      return 0
    fi
    sleep "${delay}"
  done
  die "Ollama did not become ready after $((retries * delay))s. Is the stack up? (make up)"
}

wait_for_ollama

# --- Pull each model ---------------------------------------------------------
# Split on commas, trim surrounding whitespace per entry.
IFS=',' read -r -a MODELS <<<"${MODELS_RAW}"

failures=0
for raw in "${MODELS[@]}"; do
  model="$(printf '%s' "${raw}" | xargs)" # trim
  [ -n "${model}" ] || continue
  log_info "Pulling model: ${model}"
  if "${COMPOSE[@]}" exec -T ollama ollama pull "${model}"; then
    log_info "OK: ${model}"
  else
    log_err "Failed to pull: ${model}"
    failures=$((failures + 1))
  fi
done

if [ "${failures}" -gt 0 ]; then
  die "${failures} model(s) failed to pull."
fi

log_info "All models present. Available models:"
"${COMPOSE[@]}" exec -T ollama ollama list || true
