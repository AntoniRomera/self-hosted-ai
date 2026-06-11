#!/usr/bin/env bash
#
# backup.sh - back up Open WebUI data (chat history + SQLite DB) to a tarball.
#
# Streams the contents of the named Docker volume into
# ./backups/openwebui-<timestamp>.tar.gz using an ephemeral alpine container,
# so it works even while the stack is running and needs no host-side tooling.
#
# Usage:
#   scripts/backup.sh              # back up Open WebUI data only
#   scripts/backup.sh --models     # also back up the Ollama models volume
#
# Restore with scripts/restore.sh.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "${SCRIPT_DIR}/lib.sh"

cd "${PROJECT_ROOT}"

INCLUDE_MODELS=0
for arg in "$@"; do
  case "${arg}" in
    --models) INCLUDE_MODELS=1 ;;
    -h | --help)
      grep -E '^#( |$)' "$0" | sed -E 's/^# ?//'
      exit 0
      ;;
    *) die "Unknown argument: ${arg} (try --help)" ;;
  esac
done

# Compose prefixes volumes with the project name ("name:" in docker-compose.yml).
PROJECT_NAME="self-hosted-ai"
BACKUP_DIR="${PROJECT_ROOT}/backups"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
mkdir -p "${BACKUP_DIR}"

# Back up a single named volume into a gzipped tar.
# $1 = volume name (without project prefix), $2 = output basename
backup_volume() {
  local short_name="$1"
  local out_base="$2"
  local volume="${PROJECT_NAME}_${short_name}"
  local outfile="${BACKUP_DIR}/${out_base}-${TIMESTAMP}.tar.gz"

  if ! docker volume inspect "${volume}" >/dev/null 2>&1; then
    die "Volume ${volume} not found. Has the stack been started at least once?"
  fi

  log_info "Backing up volume ${volume} -> ${outfile}"
  docker run --rm \
    -v "${volume}:/source:ro" \
    -v "${BACKUP_DIR}:/backup" \
    alpine:3.20 \
    tar czf "/backup/$(basename "${outfile}")" -C /source .

  log_info "Created $(du -h "${outfile}" | cut -f1) backup: ${outfile}"
}

backup_volume "openwebui-data" "openwebui"

if [ "${INCLUDE_MODELS}" -eq 1 ]; then
  log_warn "Backing up Ollama models too. This can be large (gigabytes)."
  backup_volume "ollama-data" "ollama"
fi

log_info "Done. Backups stored in ${BACKUP_DIR}/"
# shellcheck disable=SC2012  # listing our own timestamped backup files; ls -t is fine here
ls -1t "${BACKUP_DIR}" | head -n 5 || true
