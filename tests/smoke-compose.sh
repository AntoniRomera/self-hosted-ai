#!/usr/bin/env bash
#
# smoke-compose.sh - smoke checks for the Self-Hosted AI Stack.
#
# These are real, meaningful checks that catch the kinds of regressions that
# matter for this project without needing to actually start any containers:
#
#   1. docker-compose.yml renders (`docker compose config`) with dummy secrets.
#   2. All four services (ollama, open-webui, tailscale, caddy) are defined.
#   3. No host ports are published in the default (non-tls) config.
#   4. The optional local-only override DOES publish a loopback port.
#   5. The Caddy reverse proxy only appears under the `tls` profile.
#   6. Every image is pinned to an explicit tag (no `:latest` / untagged).
#   7. Required secrets (WEBUI_SECRET_KEY, TS_AUTHKEY) are enforced - the config
#      fails when they are missing.
#   8. tailscale/serve.json is valid JSON and proxies to open-webui:8080.
#   9. .env.example contains no obviously-real secrets.
#
# Usage:
#   tests/smoke-compose.sh
#
# Requires: docker (compose v2) and jq. Skips compose-dependent checks with a
# clear message if docker is unavailable, so it is still useful in minimal envs.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

# --- Tiny test harness ------------------------------------------------------
PASS=0
FAIL=0
SKIP=0

green() { printf '\033[32m%s\033[0m' "$1"; }
red() { printf '\033[31m%s\033[0m' "$1"; }
yellow() { printf '\033[33m%s\033[0m' "$1"; }

ok() {
  PASS=$((PASS + 1))
  printf '  [%s] %s\n' "$(green PASS)" "$1"
}
no() {
  FAIL=$((FAIL + 1))
  printf '  [%s] %s\n' "$(red FAIL)" "$1"
}
skip() {
  SKIP=$((SKIP + 1))
  printf '  [%s] %s\n' "$(yellow SKIP)" "$1"
}

# assert_contains "haystack" "needle" "description"
assert_contains() {
  if printf '%s' "$1" | grep -qF -- "$2"; then
    ok "$3"
  else
    no "$3 (expected to find: $2)"
  fi
}

# assert_not_contains "haystack" "needle" "description"
assert_not_contains() {
  if printf '%s' "$1" | grep -qF -- "$2"; then
    no "$3 (unexpectedly found: $2)"
  else
    ok "$3"
  fi
}

# Dummy values so `docker compose config` resolves required ${VAR:?...} vars.
export WEBUI_SECRET_KEY="dummy-secret-for-tests"
export TS_AUTHKEY="dummy-authkey-for-tests"
export CADDY_DOMAIN="ai.test.example"

HAVE_DOCKER=0
if docker compose version >/dev/null 2>&1; then
  HAVE_DOCKER=1
fi

# ---------------------------------------------------------------------------
echo "== Compose config (default profile) =="
if [ "${HAVE_DOCKER}" -eq 1 ]; then
  if DEFAULT_CONFIG="$(docker compose config 2>/dev/null)"; then
    ok "docker compose config renders without error"

    for svc in "ollama:" "open-webui:" "tailscale:"; do
      assert_contains "${DEFAULT_CONFIG}" "${svc}" "service ${svc%:} is defined"
    done

    # Caddy is profile-gated, so it must NOT appear in the default render.
    assert_not_contains "${DEFAULT_CONFIG}" "container_name: caddy" \
      "caddy is NOT started by default (tls profile only)"

    # Security invariant: nothing is published to the host by default.
    assert_not_contains "${DEFAULT_CONFIG}" "published:" \
      "no host ports are published in the default config"

    # Reproducibility invariant: no floating tags.
    assert_not_contains "${DEFAULT_CONFIG}" ":latest" \
      "no image uses the :latest tag"

    # Ollama base URL wiring is correct.
    assert_contains "${DEFAULT_CONFIG}" "http://ollama:11434" \
      "open-webui points at the ollama service"
  else
    no "docker compose config failed to render"
  fi
else
  skip "docker compose unavailable - skipping default-config checks"
fi

# ---------------------------------------------------------------------------
echo "== Compose config (tls profile) =="
if [ "${HAVE_DOCKER}" -eq 1 ]; then
  if TLS_CONFIG="$(docker compose --profile tls config 2>/dev/null)"; then
    ok "docker compose --profile tls renders without error"
    assert_contains "${TLS_CONFIG}" "container_name: caddy" \
      "caddy IS started under the tls profile"
    assert_contains "${TLS_CONFIG}" "published: \"443\"" \
      "caddy publishes port 443 under the tls profile"
  else
    no "docker compose --profile tls failed to render"
  fi
else
  skip "docker compose unavailable - skipping tls-profile checks"
fi

# ---------------------------------------------------------------------------
echo "== Local-only override =="
if [ "${HAVE_DOCKER}" -eq 1 ]; then
  TMP_OVERRIDE="docker-compose.override.yml"
  CLEANUP_OVERRIDE=0
  if [ ! -f "${TMP_OVERRIDE}" ]; then
    cp docker-compose.override.yml.example "${TMP_OVERRIDE}"
    CLEANUP_OVERRIDE=1
  fi
  if OVERRIDE_CONFIG="$(docker compose config 2>/dev/null)"; then
    assert_contains "${OVERRIDE_CONFIG}" "127.0.0.1" \
      "override binds Open WebUI to loopback only"
    assert_contains "${OVERRIDE_CONFIG}" "target: 8080" \
      "override maps to the Open WebUI container port 8080"
  else
    no "docker compose config with override failed to render"
  fi
  if [ "${CLEANUP_OVERRIDE}" -eq 1 ]; then
    rm -f "${TMP_OVERRIDE}"
  fi
else
  skip "docker compose unavailable - skipping override checks"
fi

# ---------------------------------------------------------------------------
echo "== Required secrets are enforced =="
if [ "${HAVE_DOCKER}" -eq 1 ]; then
  # Unset WEBUI_SECRET_KEY in a subshell; the ${VAR:?} guard must fail the render.
  if (unset WEBUI_SECRET_KEY; docker compose config >/dev/null 2>&1); then
    no "missing WEBUI_SECRET_KEY should fail the render but did not"
  else
    ok "missing WEBUI_SECRET_KEY fails the render (guard works)"
  fi
  if (unset TS_AUTHKEY; docker compose config >/dev/null 2>&1); then
    no "missing TS_AUTHKEY should fail the render but did not"
  else
    ok "missing TS_AUTHKEY fails the render (guard works)"
  fi
else
  skip "docker compose unavailable - skipping secret-guard checks"
fi

# ---------------------------------------------------------------------------
echo "== Static file checks (no docker required) =="

# Every image: line in the compose file must carry an explicit tag.
UNTAGGED="$(
  grep -E '^\s*image:' docker-compose.yml \
    | grep -vE ':-[A-Za-z0-9./_-]+:[A-Za-z0-9._-]+' || true
)"
if [ -z "${UNTAGGED}" ]; then
  ok "all images in docker-compose.yml are pinned to a tag"
else
  no "found image lines without a pinned tag: ${UNTAGGED}"
fi

# tailscale/serve.json must be valid JSON proxying to open-webui:8080.
if command -v jq >/dev/null 2>&1; then
  if jq -e . tailscale/serve.json >/dev/null 2>&1; then
    ok "tailscale/serve.json is valid JSON"
    PROXY="$(jq -r '.Web[].Handlers["/"].Proxy' tailscale/serve.json 2>/dev/null || true)"
    assert_contains "${PROXY}" "http://open-webui:8080" \
      "serve.json proxies / to open-webui:8080"
  else
    no "tailscale/serve.json is NOT valid JSON"
  fi
else
  skip "jq unavailable - skipping serve.json checks"
fi

# .env.example must exist and contain only placeholders, never real secrets.
if [ -f .env.example ]; then
  ok ".env.example exists"
  ENV_EXAMPLE="$(cat .env.example)"
  assert_contains "${ENV_EXAMPLE}" "WEBUI_SECRET_KEY=" ".env.example documents WEBUI_SECRET_KEY"
  assert_contains "${ENV_EXAMPLE}" "TS_AUTHKEY=" ".env.example documents TS_AUTHKEY"
  # A real Tailscale key looks like tskey-auth-<keyID>-<secret>; the placeholder
  # must clearly be a placeholder, not a real key.
  if grep -E 'TS_AUTHKEY="tskey-auth-[A-Za-z0-9]{10,}-[A-Za-z0-9]{20,}"' .env.example >/dev/null 2>&1; then
    no ".env.example appears to contain a REAL Tailscale auth key"
  else
    ok ".env.example TS_AUTHKEY is a placeholder, not a real key"
  fi
else
  no ".env.example is missing"
fi

# The real .env must never be committed; ensure it is gitignored.
if grep -qE '^\.env$' .gitignore; then
  ok ".env is gitignored"
else
  no ".env is NOT gitignored (secret-leak risk)"
fi

# ---------------------------------------------------------------------------
echo
printf 'Results: %s passed, %s failed, %s skipped\n' \
  "$(green "${PASS}")" "$([ "${FAIL}" -eq 0 ] && green 0 || red "${FAIL}")" \
  "$(yellow "${SKIP}")"

[ "${FAIL}" -eq 0 ] || exit 1
