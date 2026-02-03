#!/usr/bin/env bash
#
# verify.sh - Forensische Verifikation gegen ein hashdeep-Manifest
#
# Verwendung:
#   bash verify.sh /pfad/zu/manifest.sha256 /pfad/zum/ziel
#
set -euo pipefail

MANIFEST="${1:-}"
DEST="${2:-}"
PROJECT_DIR="${MIGRATION_PROJECT:-$(dirname "$DEST")/_MIGRATION_PROJECT}"
TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') $*"; }
ok() { echo -e "${GREEN}[OK]${NC} $(date '+%H:%M:%S') $*"; }
err() { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $*" >&2; }

usage() {
    cat << EOF
Verwendung: $(basename "$0") <manifest.sha256> <ziel> [disk_label]

Argumente:
  manifest.sha256   hashdeep-Manifest (mit -l erzeugt)
  ziel              Zielverzeichnis, das geprüft wird
  disk_label        Optionaler Name für Logs (Default: audit_YYYYMMDD)
EOF
    exit 1
}

DISK_LABEL="${3:-audit_$(date +%Y%m%d)}"

[[ -z "$MANIFEST" || -z "$DEST" ]] && usage
[[ -f "$MANIFEST" ]] || { err "Manifest nicht gefunden: $MANIFEST"; exit 1; }
[[ -d "$DEST" ]] || { err "Ziel nicht gefunden: $DEST"; exit 1; }

if ! command -v hashdeep &>/dev/null; then
    err "hashdeep nicht gefunden!"
    err "Installation: nix-shell -p hashdeep"
    exit 1
fi

mkdir -p "$PROJECT_DIR"/logs
AUDIT_LOG_FILE="$PROJECT_DIR/logs/${TIMESTAMP}_${DISK_LABEL}_audit.log"

log "Manifest: $MANIFEST"
log "Ziel:     $DEST"
log "Audit:    $AUDIT_LOG_FILE"

AUDIT_LOG="$(mktemp -t hashdeep_audit.XXXXXX)"
trap 'rm -f "$AUDIT_LOG"' EXIT

cd "$DEST"
hashdeep -r -l -k "$MANIFEST" -a . | tee "$AUDIT_LOG" "$AUDIT_LOG_FILE" >/dev/null || true

if grep -q "Audit passed" "$AUDIT_LOG"; then
    ok "Forensische Verifikation bestanden"
    exit 0
fi

err "Verifikation fehlgeschlagen"
grep -E "(No match|Moved|not found|Modified)" "$AUDIT_LOG" || true
exit 1
