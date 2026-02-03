#!/usr/bin/env bash
#
# verify.sh - Forensische Verifikation gegen ein hashdeep-Manifest
#
# Verwendung:
#   bash verify.sh [--sample <percent>] /pfad/zu/manifest.sha256 /pfad/zum/ziel [disk_label]
#
set -euo pipefail

SAMPLE_PERCENT=""
MANIFEST=""
DEST=""
PROJECT_DIR=""
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
Verwendung: $(basename "$0") [--sample <percent>] <manifest.sha256> <ziel> [disk_label]

Argumente:
  manifest.sha256   hashdeep-Manifest (mit -l erzeugt)
  ziel              Zielverzeichnis, das geprüft wird
  disk_label        Optionaler Name für Logs (Default: audit_YYYYMMDD)

Hinweis:
  Dry-Run: hashdeep hat keinen Dry-Run; nutze stattdessen --sample.
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sample)
            SAMPLE_PERCENT="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            break
            ;;
    esac
done

MANIFEST="${1:-}"
DEST="${2:-}"
DISK_LABEL="${3:-audit_$(date +%Y%m%d)}"

PROJECT_DIR="${MIGRATION_PROJECT:-$(dirname "$DEST")/_MIGRATION_PROJECT}"

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
SAMPLE_MANIFEST=""
trap 'rm -f "$AUDIT_LOG" "$SAMPLE_MANIFEST"' EXIT

MANIFEST_TO_USE="$MANIFEST"

if [[ -n "$SAMPLE_PERCENT" ]]; then
    if ! [[ "$SAMPLE_PERCENT" =~ ^[0-9]+$ ]] || (( SAMPLE_PERCENT < 1 || SAMPLE_PERCENT > 100 )); then
        err "Ungültiger --sample Wert: $SAMPLE_PERCENT (erlaubt: 1-100)"
        exit 1
    fi

    TOTAL_COUNT=$(grep -c '^[0-9]' "$MANIFEST" 2>/dev/null || echo "0")
    if (( TOTAL_COUNT == 0 )); then
        err "Manifest enthält keine prüfbaren Einträge."
        exit 1
    fi

    SAMPLE_COUNT=$(( TOTAL_COUNT * SAMPLE_PERCENT / 100 ))
    if (( SAMPLE_COUNT < 1 )); then
        SAMPLE_COUNT=1
    fi

    SAMPLE_MANIFEST="$(mktemp -t hashdeep_manifest.XXXXXX)"
    grep -E '^(%%%%|##)' "$MANIFEST" > "$SAMPLE_MANIFEST" || true

    if command -v shuf &>/dev/null; then
        grep '^[0-9]' "$MANIFEST" | shuf -n "$SAMPLE_COUNT" >> "$SAMPLE_MANIFEST"
    else
        grep '^[0-9]' "$MANIFEST" | awk -v n="$SAMPLE_COUNT" '
            { lines[NR]=$0 }
            END {
                srand();
                for (i=1; i<=n && NR>0; i++) {
                    r = 1 + int(rand() * NR);
                    print lines[r];
                    lines[r] = lines[NR];
                    NR--;
                }
            }
        ' >> "$SAMPLE_MANIFEST"
    fi

    MANIFEST_TO_USE="$SAMPLE_MANIFEST"
    log "Stichprobe: $SAMPLE_PERCENT% ($SAMPLE_COUNT von $TOTAL_COUNT)"
fi

cd "$DEST"
hashdeep -r -l -k "$MANIFEST_TO_USE" -a . | tee "$AUDIT_LOG" "$AUDIT_LOG_FILE" >/dev/null || true

if grep -q "Audit passed" "$AUDIT_LOG"; then
    if [[ -n "$SAMPLE_PERCENT" ]]; then
        ok "Stichprobe bestanden"
    else
        ok "Forensische Verifikation bestanden"
    fi
    exit 0
fi

if [[ -n "$SAMPLE_PERCENT" ]]; then
    err "Stichprobe fehlgeschlagen"
else
    err "Verifikation fehlgeschlagen"
fi
grep -E "(No match|Moved|not found|Modified)" "$AUDIT_LOG" || true
exit 1
