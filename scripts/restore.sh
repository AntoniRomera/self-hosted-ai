#!/usr/bin/env bash
#
# restore.sh - restore an Open WebUI (or Ollama) backup tarball into its volume.
#
# WARNING: this REPLACES the current contents of the target volume.
# Stop the stack first so nothing writes while restoring.
#
# Usage:
#   scripts/restore.sh backups/openwebui-20260101-120000.tar.gz
#   scripts/restore.sh --volume ollama-data backups/ollama-....tar.gz
#
# Default target volume is openwebui-data.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "${SCRIPT_DIR}/lib.sh"

cd "${PROJECT_ROOT}"

PROJECT_NAME="self-hosted-ai"
SHORT_VOLUME="openwebui-data"
ARCHIVE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --volume)
      shift
      SHORT_VOLUME="${1:?--volume needs a value}"
      ;;
    -h | --help)
      grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
      exit 0
      ;;
    -*) die "Unknown option: $1 (try --help)" ;;
    *) ARCHIVE="$1" ;;
  esac
  shift
done

[ -n "${ARCHIVE}" ] || die "No backup archive given. Usage: scripts/restore.sh <archive.tar.gz>"
[ -f "${ARCHIVE}" ] || die "Archive not found: ${ARCHIVE}"

# Resolve to an absolute path so it survives the container mount.
ARCHIVE_ABS="$(cd "$(dirname "${ARCHIVE}")" && pwd)/$(basename "${ARCHIVE}")"
VOLUME="${PROJECT_NAME}_${SHORT_VOLUME}"

log_warn "About to OVERWRITE volume ${VOLUME} with ${ARCHIVE_ABS}"
printf 'Type "yes" to continue: '
read -r confirm
[ "${confirm}" = "yes" ] || die "Aborted."

# Create the volume if it does not exist yet (fresh host).
docker volume create "${VOLUME}" >/dev/null

log_info "Restoring into ${VOLUME}..."
docker run --rm \
  -v "${VOLUME}:/target" \
  -v "${ARCHIVE_ABS}:/backup/archive.tar.gz:ro" \
  alpine:3.20 \
  sh -c 'rm -rf /target/* /target/..?* /target/.[!.]* 2>/dev/null; tar xzf /backup/archive.tar.gz -C /target'

log_info "Restore complete. Start the stack with: make up"
