#!/usr/bin/env bash
#
# migrate.sh - Integritätserhaltende Datenmigration mit 3-Phasen-Verifikation
#
# Verwendung:
#   bash migrate.sh /quelle /ziel [disk_label]
#
# Beispiel:
#   bash migrate.sh /run/media/user/ExternalDisk /mnt/nas/_IMPORT_RAW disk01_macbook
#
# Voraussetzungen:
#   - hashdeep (nix-shell -p hashdeep)
#   - rsync
#
set -euo pipefail

# === KONFIGURATION ===
SOURCE="${1:-}"
DEST="${2:-}"
DISK_LABEL="${3:-disk_$(date +%Y%m%d)}"
PROJECT_DIR="${MIGRATION_PROJECT:-$(dirname "$DEST")/_MIGRATION_PROJECT}"
TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log()  { echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $(date '+%H:%M:%S') $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%H:%M:%S') $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $*" >&2; }

usage() {
    cat << EOF
Verwendung: $(basename "$0") <quelle> <ziel> [disk_label]

Integritätserhaltende Datenmigration mit forensischer Verifikation.

Argumente:
  quelle      Quell-Verzeichnis (muss existieren)
  ziel        Ziel-Verzeichnis (wird erstellt)
  disk_label  Optionaler Name für Manifest/Logs (Default: disk_YYYYMMDD)

Hinweis:
  Dry-Run: rsync unterstützt `--dry-run` (manuell im Script ergänzen).

Beispiel:
  $(basename "$0") /run/media/user/USB /mnt/nas/_IMPORT_RAW/usb disk01_backup

Voraussetzungen:
  - hashdeep: nix-shell -p hashdeep
  - rsync: vorinstalliert

EOF
    exit 1
}

# === ARGUMENT-PRÜFUNG ===
[[ -z "$SOURCE" || -z "$DEST" ]] && usage

# === PRE-FLIGHT CHECKS ===
echo ""
echo "============================================================"
echo "  MIGRATION: $DISK_LABEL"
echo "  Gestartet: $(date)"
echo "============================================================"
echo ""

# Quelle prüfen
if [[ ! -d "$SOURCE" ]]; then
    err "Quelle nicht gefunden: $SOURCE"
    exit 1
fi

# Tools prüfen
if ! command -v hashdeep &>/dev/null; then
    err "hashdeep nicht gefunden!"
    err "Installation: nix-shell -p hashdeep"
    exit 1
fi

if ! command -v rsync &>/dev/null; then
    err "rsync nicht gefunden!"
    exit 1
fi

# Ziel-Mount prüfen (Best Effort)
if command -v mountpoint &>/dev/null; then
    if ! mountpoint -q "$(dirname "$DEST")"; then
        warn "Ziel-Mountpoint nicht erkannt: $(dirname "$DEST")"
    fi
fi

# Platz prüfen (Best Effort)
if command -v df &>/dev/null; then
    DEST_FREE=$(df -h "$(dirname "$DEST")" | awk 'NR==2 {print $4}')
    log "Ziel frei: $DEST_FREE"
fi

# Verzeichnisse erstellen
mkdir -p "$DEST"
mkdir -p "$PROJECT_DIR"/{manifests,metadata,logs,reports}

# Log-Datei
LOG="$PROJECT_DIR/logs/${TIMESTAMP}_${DISK_LABEL}_full.log"
exec > >(tee -a "$LOG") 2>&1

log "Quelle:     $SOURCE"
log "Ziel:       $DEST"
log "Label:      $DISK_LABEL"
log "Projekt:    $PROJECT_DIR"
log "Log:        $LOG"
echo ""

# SMB-Performance Hinweis (macOS)
if [[ -f /etc/nsmb.conf ]]; then
    if ! grep -Eq 'signing_required\s*=\s*no' /etc/nsmb.conf; then
        warn "SMB: signing_required=no fehlt in /etc/nsmb.conf (macOS Performance)"
    fi
    if ! grep -Eq 'dir_cache_off\s*=\s*yes' /etc/nsmb.conf; then
        warn "SMB: dir_cache_off=yes fehlt in /etc/nsmb.conf (macOS Performance)"
    fi
fi

# Quell-Statistik
SOURCE_SIZE=$(du -sh "$SOURCE" 2>/dev/null | cut -f1 || echo "unbekannt")
SOURCE_FILES=$(find "$SOURCE" -type f 2>/dev/null | wc -l || echo "unbekannt")
log "Quelle:     $SOURCE_SIZE, $SOURCE_FILES Dateien"
echo ""

# === PHASE 0: EXTENDED ATTRIBUTES DOKUMENTIEREN ===
log "Phase 0: Dokumentiere Extended Attributes..."
XATTR_FILE="$PROJECT_DIR/metadata/${DISK_LABEL}_xattrs.txt"

if command -v getfattr &>/dev/null; then
    getfattr -R -d -m - "$SOURCE" > "$XATTR_FILE" 2>/dev/null || true
    XATTR_COUNT=$(grep -c "^# file:" "$XATTR_FILE" 2>/dev/null || echo "0")
    log "xattrs dokumentiert (Linux/getfattr): $XATTR_COUNT Einträge"
elif command -v xattr &>/dev/null; then
    find "$SOURCE" -exec xattr -l {} \; 2>/dev/null > "$XATTR_FILE" || true
    XATTR_COUNT=$(grep -c "^\\S" "$XATTR_FILE" 2>/dev/null || echo "0")
    log "xattrs dokumentiert (macOS/xattr): $XATTR_COUNT Zeilen"
else
    warn "xattr/getfattr nicht verfügbar - überspringe xattr-Dokumentation"
    touch "$XATTR_FILE"
fi
echo ""

# === PHASE 1: QUELL-MANIFEST ===
log "Phase 1: Erstelle Quell-Manifest mit hashdeep (SHA256)..."
MANIFEST="$PROJECT_DIR/manifests/${DISK_LABEL}_source.sha256"

cd "$SOURCE"
if ! hashdeep -r -l -c sha256 . > "$MANIFEST" 2>&1; then
    warn "hashdeep hatte Warnungen (evtl. Berechtigungsprobleme)"
fi

FILE_COUNT=$(grep -c '^[0-9a-f]' "$MANIFEST" 2>/dev/null || echo "0")
ok "Manifest erstellt: $FILE_COUNT Dateien"
log "Manifest: $MANIFEST"
echo ""

# === PHASE 2: RSYNC KOPIE ===
log "Phase 2: Kopiere mit rsync --checksum..."
RSYNC_LOG="$PROJECT_DIR/logs/${TIMESTAMP}_${DISK_LABEL}_rsync.log"

rsync -avhP --checksum \
    --exclude='.DS_Store' \
    --exclude='._*' \
    --exclude='.Spotlight-*' \
    --exclude='.fseventsd' \
    --exclude='.Trashes' \
    --exclude='.TemporaryItems' \
    --exclude='.DocumentRevisions-V100' \
    --log-file="$RSYNC_LOG" \
    "$SOURCE/" "$DEST/"

DEST_SIZE=$(du -sh "$DEST" 2>/dev/null | cut -f1)
ok "rsync abgeschlossen: $DEST_SIZE kopiert"
log "rsync-Log: $RSYNC_LOG"
echo ""

# === PHASE 3: FORENSISCHE VERIFIKATION ===
log "Phase 3: Forensische Verifikation mit hashdeep..."
AUDIT_LOG="$PROJECT_DIR/logs/${TIMESTAMP}_${DISK_LABEL}_audit.log"

cd "$DEST"
hashdeep -r -l -k "$MANIFEST" -a . > "$AUDIT_LOG" 2>&1 || true

if grep -q "Audit passed" "$AUDIT_LOG"; then
    echo ""
    echo "============================================================"
    ok "  FORENSISCHE VERIFIKATION BESTANDEN"
    ok "  $FILE_COUNT Dateien sind identisch mit der Quelle"
    echo "============================================================"
    echo ""

    # In Summary-Log eintragen
    echo "$(date '+%Y-%m-%d %H:%M') - $DISK_LABEL - VERIFIED OK - $FILE_COUNT files - $SOURCE_SIZE" \
        >> "$PROJECT_DIR/logs/verification_summary.log"

    EXIT_CODE=0
else
    echo ""
    echo "============================================================"
    err "  VERIFIKATION FEHLGESCHLAGEN!"
    echo "============================================================"
    echo ""
    echo "Probleme gefunden:"
    grep -E "(No match|Moved|not found|Modified)" "$AUDIT_LOG" | head -20
    echo ""

    # Trotzdem in Summary-Log eintragen
    echo "$(date '+%Y-%m-%d %H:%M') - $DISK_LABEL - FAILED - siehe $AUDIT_LOG" \
        >> "$PROJECT_DIR/logs/verification_summary.log"

    EXIT_CODE=1
fi

# === ABSCHLUSS ===
echo ""
log "Zusammenfassung:"
log "  - Quelle:      $SOURCE"
log "  - Ziel:        $DEST"
log "  - Dateien:     $FILE_COUNT"
log "  - Grösse:      $DEST_SIZE"
log "  - Manifest:    $MANIFEST"
log "  - rsync-Log:   $RSYNC_LOG"
log "  - Audit-Log:   $AUDIT_LOG"
log "  - xattrs:      $XATTR_FILE"
echo ""

exit $EXIT_CODE
