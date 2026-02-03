# Wissensbasis: Integritätserhaltende Datenmigration

> Konsolidiertes, validiertes Wissen aus Praxisprojekten und wissenschaftlicher Forschung

**Version:** 1.0.0
**Letzte Aktualisierung:** 2026-02-03
**Validiert gegen:** Wissenschaftliche Literatur, Industriestandards, Praxiserfahrung

---

## Inhaltsverzeichnis

1. [Wissenschaftliche Grundlagen](#1-wissenschaftliche-grundlagen)
2. [Tool-Ökosystem](#2-tool-ökosystem)
3. [Migrations-Workflow](#3-migrations-workflow)
4. [Prüfsummen & Verifikation](#4-prüfsummen--verifikation)
5. [macOS-Spezifika](#5-macos-spezifika)
6. [Netzwerk & SMB](#6-netzwerk--smb)
7. [Metadaten-Management](#7-metadaten-management)
8. [Deduplizierung](#8-deduplizierung)
9. [Fehlerbehandlung](#9-fehlerbehandlung)
10. [Best Practices Checklisten](#10-best-practices-checklisten)

---

## 1. Wissenschaftliche Grundlagen

### 1.1 Warum End-to-End-Verifikation essentiell ist

**Problem:** TCP-Checksums sind unzureichend für Datenintegrität.

| Studie | Ergebnis | Implikation |
|--------|----------|-------------|
| [Stone & Partridge 2000](https://dl.acm.org/doi/10.1145/347059.347561) | 1 von 16 Millionen TCP-Paketen hat unerkannten Fehler | Bei GB-Transfers: Mehrere korrupte Bytes wahrscheinlich |
| [ScienceDirect 2021](https://www.sciencedirect.com/science/article/abs/pii/S074373152100023X) | ~5% Fehlerrate bei schnellen Netzwerken | 10Gbit+ erhöht Fehlerwahrscheinlichkeit |
| [CERN 2007](https://cds.cern.ch/record/865788) | 0.5% Bit-Rot pro Jahr auf HDDs | Langzeitarchivierung braucht Redundanz |

**Konsequenz:** Jeder Transfer MUSS mit kryptographischen Prüfsummen verifiziert werden.

### 1.2 Hash-Algorithmen-Vergleich

| Algorithmus | Sicherheit | Geschwindigkeit | Empfehlung |
|-------------|------------|-----------------|------------|
| **MD5** | ❌ Gebrochen | Schnell | NICHT VERWENDEN |
| **SHA-1** | ❌ Gebrochen | Schnell | NICHT VERWENDEN |
| **SHA-256** | ✅ Sicher | Mittel | **Standard für Migration** |
| **SHA-512** | ✅ Sicher | Mittel | Overkill für Migration |
| **xxHash** | ⚠️ Nicht kryptographisch | Sehr schnell | Nur für Quick-Checks |
| **BLAKE3** | ✅ Sicher | Sehr schnell | Zukunftsoption |

**Quellen:**
- [NIST SP 800-131A Rev 2](https://csrc.nist.gov/publications/detail/sp/800-131a/rev-2/final)
- [NCEI Data Integrity Practices](https://ioos.github.io/ncei-archiving-cookbook/practices.html)

### 1.3 Archivierungsstandards

| Standard | Organisation | Anwendung |
|----------|--------------|-----------|
| **BagIt (RFC 8493)** | Library of Congress | Container für archivierte Daten mit Manifesten |
| **OAIS (ISO 14721)** | ISO/CCSDS | Referenzmodell für Langzeitarchivierung |
| **PREMIS** | Library of Congress | Preservation Metadata |

---

## 2. Tool-Ökosystem

### 2.1 Primäre Werkzeuge

#### hashdeep - Forensische Prüfsummen

**Installation:** `nix-shell -p hashdeep`

**Manifest erstellen:**
```bash
hashdeep -r -l -c sha256 /quelle > manifest.sha256
```

**Manifest verifizieren (Audit):**
```bash
hashdeep -r -l -k manifest.sha256 -a /ziel
# Output: "Audit passed" = ERFOLG
```

**Flags:**
| Flag | Bedeutung |
|------|-----------|
| `-r` | Rekursiv |
| `-l` | Relative Pfade im Manifest |
| `-c sha256` | SHA-256 verwenden |
| `-k manifest` | Gegen Manifest prüfen |
| `-a` | Audit-Modus (streng) |

#### rsync - Intelligentes Kopieren

**Standard-Aufruf:**
```bash
rsync -avhP --checksum \
  --exclude='.DS_Store' \
  --exclude='._*' \
  --log-file=rsync.log \
  /quelle/ /ziel/
```

**Flags:**
| Flag | Bedeutung |
|------|-----------|
| `-a` | Archiv-Modus (rekursiv, Berechtigungen, Symlinks) |
| `-v` | Verbose |
| `-h` | Human-readable Größen |
| `-P` | Progress + Partial (Resume) |
| `--checksum` | Block-Level Prüfsummen statt mtime |
| `--log-file` | Detailliertes Log |

#### fclones - Duplikat-Erkennung

**Installation:** `nix-shell -p fclones`

**Duplikate finden:**
```bash
fclones group /pfad --min 1M -o report.txt
fclones group /pfad --min 1M -f json > report.json
```

**Duplikate verlinken (Hard-Links):**
```bash
fclones link /pfad --min 1M  # Spart Speicher, behält alle "Kopien"
```

**Warum fclones?**
- 7x schneller als jdupes (Rust, parallelisiert)
- 100% byte-identisch Prüfung (keine False Positives)
- JSON-Output für Automatisierung

### 2.2 Sekundäre Werkzeuge

| Tool | Zweck | Installation |
|------|-------|--------------|
| **exiftool** | Metadaten-Extraktion (200+ Formate) | `nix-shell -p exiftool` |
| **getfattr** | Extended Attributes (Linux) | Vorinstalliert |
| **xattr** | Extended Attributes (macOS) | Vorinstalliert |
| **par2** | Fehlerkorrektur-Dateien | `nix-shell -p par2cmdline` |
| **rclone** | Multi-Cloud-Sync (4-10x schneller) | `nix-shell -p rclone` |

---

## 3. Migrations-Workflow

### 3.1 Fünf-Phasen-Modell

```
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 1: ROHDATEN-SICHERUNG                                    │
│  ───────────────────────────────────────────────────────────    │
│  1. Quelle mounten (ggf. mit sudo für APFS)                     │
│  2. hashdeep Quell-Manifest erstellen                           │
│  3. Extended Attributes dokumentieren                           │
│  4. rsync --checksum nach _IMPORT_RAW/                          │
│  5. hashdeep Audit-Verifikation                                 │
│  → Ergebnis: 1:1 Kopie mit forensischer Integritätsgarantie     │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 2: ANALYSE & DEDUPLIZIERUNG                              │
│  ───────────────────────────────────────────────────────────    │
│  1. fclones Duplikat-Analyse (cross-disk)                       │
│  2. Statistiken generieren (Dateitypen, Größen)                 │
│  3. Probleme identifizieren (korrupte Dateien, Konflikte)       │
│  4. Hard-Links für identische Dateien (optional)                │
│  → Ergebnis: Bereinigte Rohdaten, Duplikat-Report               │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 3: NORMALISIERUNG & METADATEN                            │
│  ───────────────────────────────────────────────────────────    │
│  1. Metadaten extrahieren (exiftool → CSV/JSON)                 │
│  2. Dateinamen standardisieren (SMB-kompatibel)                 │
│  3. Unicode normalisieren (NFD → NFC)                           │
│  4. Original-Namen in Sidecar/Metadaten dokumentieren           │
│  → Ergebnis: Normalisierte Dateien mit Metadaten                │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 4: STRUKTURIERUNG                                        │
│  ───────────────────────────────────────────────────────────    │
│  1. Kategorisierung nach Typ (Dokumente, Medien, Software)      │
│  2. Zeitbasierte Organisation (YYYY/MM für Medien)              │
│  3. Projekt-Gruppierung                                         │
│  → Ergebnis: Saubere, navigierbare Struktur                     │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 5: LANGZEITARCHIVIERUNG                                  │
│  ───────────────────────────────────────────────────────────    │
│  1. Archivformate (PDF/A, TIFF, DNG)                            │
│  2. BagIt-Container für kritische Daten                         │
│  3. PAR2 Fehlerkorrektur (5% Redundanz)                         │
│  4. Finales Manifest der Zielstruktur                           │
│  → Ergebnis: Langzeitarchiv nach ISO/OAIS Standards             │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Drei-Phasen-Verifikation (Detail)

```bash
# PHASE 1: Quell-Manifest (Source of Truth)
cd /quelle
hashdeep -r -l -c sha256 . > manifest_source.sha256

# PHASE 2: Transfer mit Block-Checksums
rsync -avhP --checksum /quelle/ /ziel/

# PHASE 3: Forensische Verifikation
cd /ziel
hashdeep -r -l -k manifest_source.sha256 -a .
# Erwarteter Output: "hashdeep: Audit passed"
```

---

## 4. Prüfsummen & Verifikation

### 4.1 hashdeep Manifest-Format

```
%%%% HASHDEEP-1.0
%%%% size,sha256,filename
## Invoked from: /source/path
## $ hashdeep -r -l -c sha256 .
2625,70e535f1a0feaa1404267f9f80b2a20ebc56371b7e34369c58214f266eca7917,./file.txt
```

### 4.2 Fehler-Interpretation

| hashdeep Output | Bedeutung | Aktion |
|-----------------|-----------|--------|
| `Audit passed` | Alle Dateien identisch | ✅ Erfolg |
| `No match` | Datei nicht im Manifest | Neue Datei oder Pfadproblem |
| `Moved` | Datei an anderer Position | Struktur geändert |
| `Modified` | Hash stimmt nicht | ❌ Korruption oder Änderung |
| `Input file not found` | Datei fehlt | ❌ Nicht kopiert |

### 4.3 Verifikations-Strategien

| Strategie | Methode | Geschwindigkeit | Sicherheit |
|-----------|---------|-----------------|------------|
| **Quick** | Dateizahl + Gesamtgröße | Sofort | ⚠️ Niedrig |
| **Sample** | 2% Zufalls-Stichprobe hashen | Schnell | ⚠️ Mittel |
| **Full** | Alle Dateien hashen | Langsam | ✅ Hoch |
| **Forensic** | hashdeep Audit-Modus | Langsam | ✅ Höchste |

**Empfehlung:** Immer `Full` oder `Forensic` für finale Verifikation.

### 4.4 Stichproben-Verifikation (Pragmatischer Zwischencheck)

**Ziel:** Schneller Qualitätsindikator zwischen zwei Voll-Audits.

```bash
# 2% Stichprobe gegen vorhandenes Manifest
bash scripts/verify.sh --sample 2 /pfad/zum/manifest.sha256 /ziel/_IMPORT_RAW/disk01
```

**Wichtig:** Stichproben ersetzen **keine** finale Forensik. Sie dienen nur als Zwischencheck.

**Grenzen/Risiken:**
- Ein positives Sample ist **keine** Vollgarantie für Integrität.
- Korrelationen (z.B. defekte Sektoren-Cluster) können unentdeckt bleiben.
- Verwende Sample-Checks nur als Zwischenstand, nicht als Abschluss.

---

## 5. macOS-Spezifika

### 5.1 APFS (Apple File System)

**Problem:** APFS via `apfs-fuse` hat UID-Mapping-Probleme.

```bash
# Typisches Symptom:
ls -la /run/media/user/volume/
# drwx------  1   99   99   # UID 99 = nobody = nicht lesbar!
```

**Lösungen:**

1. **sudo rsync (empfohlen auf Linux):**
```bash
sudo rsync -avhP --checksum \
  --chown=user:users \
  /apfs-mount/ /ziel/
```

2. **Berechtigungen auf Mac korrigieren:**
```bash
# Auf macOS ausführen:
sudo chown -R $(whoami):staff /Volumes/DEIN_VOLUME/
```

3. **Remount mit uid-Mapping (falls unterstützt):**
```bash
sudo apfs-fuse -o uid=1000,gid=100 /dev/sdX /mnt/apfs
```

### 5.2 Extended Attributes (xattrs)

**Was sind xattrs?**
- Finder-Tags und Farben
- Spotlight-Metadaten
- Quarantine-Flags (`com.apple.quarantine`)
- Resource Forks (veraltet)

**Problem:** SMB/CIFS unterstützt xattrs nicht nativ.

**Lösung - Dokumentation:**
```bash
# Linux:
getfattr -R -d -m - /quelle > xattrs_backup.txt

# macOS:
find /quelle -exec xattr -l {} \; 2>/dev/null > xattrs_backup.txt
```

### 5.3 macOS System-Exclusions

Folgende Dateien sollten **nicht** migriert werden:

```bash
rsync \
  --exclude='.DS_Store' \
  --exclude='._*' \
  --exclude='.Spotlight-*' \
  --exclude='.fseventsd' \
  --exclude='.Trashes' \
  --exclude='.TemporaryItems' \
  --exclude='.DocumentRevisions-V100' \
  ...
```

### 5.4 Time Machine Backups

**Problem:** Hard-Links zwischen Snapshots explodieren beim Kopieren.

```
Original: 100 GB mit 5 Snapshots
Kopie ohne Hard-Link-Erhalt: 500 GB!
```

**Lösungen:**

1. **Nur neuestes Snapshot:**
```bash
LATEST=$(ls -1t /Volumes/TM/Backups.backupdb/MacName/ | grep -v Latest | head -1)
rsync -avhP "/Volumes/TM/Backups.backupdb/MacName/$LATEST/" /ziel/
```

2. **Mit Hard-Links erhalten (nur ext4/btrfs):**
```bash
rsync -avhPH /quelle/ /ziel/  # -H = Hard-Links erhalten
```

### 5.5 Bundle-Strukturen schützen

macOS Bundles (`.app`, `.framework`, `.bundle`) dürfen intern **nicht** verändert werden:

```bash
# detox-safe.sh - Nur externe Namen sanitizen
PRUNE_PATTERNS=(
    "*.app"
    "*.framework"
    "*.bundle"
    "*.xcodeproj"
    "*.photoslibrary"
    "*.vmwarevm"
    "*.utm"
)
```

---

## 6. Netzwerk & SMB

### 6.1 SMB-Performance-Optimierung

| Problem | Symptom | Lösung |
|---------|---------|--------|
| SMB-Signing | 50-100 MB/s statt 600+ | `signing_required=no` (weniger sicher) |
| Viele kleine Dateien | 1 KB/s Overhead | Archive erstellen oder SSH-Tunnel |
| Directory Caching | Inkonsistente Ansichten | `dir_cache_off=yes` |

**macOS `/etc/nsmb.conf`:**
```ini
[default]
signing_required=no
dir_cache_off=yes
```

### 6.2 rsync über SSH (Alternative zu SMB)

```bash
rsync -avhP --checksum \
  -e "ssh -o Compression=no" \
  /lokale/quelle/ \
  user@nas:/ziel/
```

**Vorteile:**
- Kein SMB-Overhead
- Bessere Verschlüsselung
- Stabiler bei vielen kleinen Dateien

### 6.3 rclone für Höchstgeschwindigkeit

```bash
rclone copy /quelle smb://nas/share/ziel \
  --progress \
  --transfers 4 \
  --checkers 8 \
  --retries 3
```

**Benchmark:** 4-10x schneller als rsync bei großen Dateien.

---

## 7. Metadaten-Management

### 7.1 Drei-Schicht-Ansatz

| Schicht | Methode | Robustheit | Tool |
|---------|---------|------------|------|
| **1. PDF-Metadaten** | Eingebettet in Datei | ✅ Höchste | exiftool, pikepdf |
| **2. Finder-Tags** | macOS-spezifisch | ⚠️ Mittel | osxmetadata |
| **3. Extended Attrs** | Dateisystem-abhängig | ⚠️ Niedrig | xattr, getfattr |

### 7.2 Metadaten mit exiftool extrahieren

```bash
# Alle Metadaten als CSV
exiftool -csv -r /quelle > metadata.csv

# Nur PDF-Metadaten
exiftool -PDF:all -csv /quelle/*.pdf > pdf_metadata.csv

# Als JSON
exiftool -json -r /quelle > metadata.json
```

### 7.3 PDF-Metadaten setzen

```bash
# Titel und Autor setzen
exiftool -Title="Mein Dokument" -Author="Max Mustermann" datei.pdf

# Original-Dateiname in Description speichern
exiftool -Description="Original: $(basename "$file")" "$file"

# XMP/Dublin Core
exiftool -XMP-dc:Title="Titel" -XMP-dc:Creator="Autor" datei.pdf
```

### 7.4 Dateinamen-Standardisierung

**SMB-inkompatible Zeichen:**
```
< > : " / \ | ? *
Control Characters (0x00-0x1F)
Trailing Spaces/Dots
Reserved Names: CON, PRN, AUX, NUL, COM1-9, LPT1-9
```

**Unicode-Normalisierung:**
```bash
# macOS nutzt NFD, Linux NFC
# Konvertierung mit convmv:
convmv -f utf-8 -t utf-8 --nfc -r /pfad
```

---

## 8. Deduplizierung

### 8.1 Analyse ohne Änderungen

```bash
# Report erstellen
fclones group /import_raw --min 1M -o duplicates.txt

# JSON für Automatisierung
fclones group /import_raw --min 1M -f json > duplicates.json

# Statistik
fclones group /import_raw --min 1M | head -20
```

### 8.2 Sichere Deduplizierung mit Hard-Links

```bash
# Hard-Links erstellen (Speicher sparen, alle "Kopien" bleiben)
fclones link /import_raw --min 1M

# Dry-Run zuerst!
fclones link /import_raw --min 1M --dry-run
```

**Vorteile von Hard-Links:**
- Kein Datenverlust
- Dateien bleiben an Original-Pfaden
- Speicherplatz wird geteilt

### 8.3 Wann Duplikate entfernen?

**NIEMALS automatisch.** Nur nach:
1. Vollständiger Backup-Verifikation
2. Manueller Report-Prüfung
3. Expliziter Genehmigung

```bash
# NUR nach manueller Prüfung:
fclones remove /import_raw --min 1M --keep-newest
```

---

## 9. Fehlerbehandlung

### 9.1 Häufige Fehler und Lösungen

| Fehler | Ursache | Lösung |
|--------|---------|--------|
| `Permission denied` | APFS UID-Mapping | `sudo rsync` oder Mac-Berechtigungen |
| `Stale file handle` | NAS-Verbindung unterbrochen | Remount, rsync -P (Resume) |
| `Filename too long` | >255 Bytes | Dateinamen kürzen |
| `Invalid argument` | Sonderzeichen in Namen | Sanitizing |
| `No space left` | Ziel voll | Speicher freigeben, Kompression |

### 9.2 Robuste Script-Struktur

```bash
#!/usr/bin/env bash
set -euo pipefail  # Exit bei Fehler, undefined vars, Pipe-Fehler

# Logging
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
err() { echo "[ERROR] $*" | tee -a "$LOG" >&2; }

# Pre-Flight Checks
[[ -d "$SOURCE" ]] || { err "Quelle nicht gefunden"; exit 1; }
command -v hashdeep &>/dev/null || { err "hashdeep nicht installiert"; exit 1; }
mountpoint -q "$DEST_MOUNT" || { err "Ziel nicht gemountet"; exit 1; }

# Hauptlogik mit Error-Handling
if ! rsync -avhP "$SOURCE/" "$DEST/"; then
    err "rsync fehlgeschlagen"
    exit 1
fi

log "Erfolgreich abgeschlossen"
```

### 9.3 Resume bei Abbruch

rsync mit `-P` ermöglicht Resume:
```bash
# Erster Versuch (unterbrochen)
rsync -avhP /quelle/ /ziel/
# Ctrl+C oder Verbindungsabbruch

# Resume - gleiches Kommando
rsync -avhP /quelle/ /ziel/
# Setzt fort wo abgebrochen
```

---

## 10. Best Practices Checklisten

### 10.1 Vor der Migration

- [ ] Quell-Datenträger mounten und prüfen
- [ ] Ausreichend Speicher am Ziel? (`df -h`)
- [ ] NAS/Ziel erreichbar? (`mountpoint -q`)
- [ ] Benötigte Tools installiert? (hashdeep, rsync)
- [ ] tmux/screen für lange Operationen
- [ ] `systemd-inhibit` gegen Sleep/Shutdown

### 10.2 Während der Migration

- [ ] Logs in separatem Terminal beobachten
- [ ] Netzwerkverbindung stabil?
- [ ] Bei Abbruch: rsync -P ermöglicht Resume
- [ ] Keine anderen I/O-intensiven Operationen

### 10.3 Nach der Migration

- [ ] hashdeep Audit bestanden?
- [ ] Dateizahl Quelle = Ziel?
- [ ] Größe Quelle ≈ Ziel (±Exclusions)?
- [ ] Stichprobe: Einige Dateien manuell öffnen
- [ ] Manifest archivieren
- [ ] Log archivieren
- [ ] Eintrag in verification_summary.log

### 10.4 Sicherheitsregeln

**NIEMALS:**
- ❌ Dateien in `_IMPORT_RAW/` verändern
- ❌ Manifeste überschreiben
- ❌ Logs löschen
- ❌ Duplikate ohne Prüfung entfernen
- ❌ Migration ohne Verifikation als "fertig" betrachten

**IMMER:**
- ✅ Drei-Phasen-Verifikation durchführen
- ✅ Manifeste mit SHA-256 erstellen
- ✅ Extended Attributes dokumentieren
- ✅ Sensible Dateien kennzeichnen
- ✅ Vollständige Logs führen

---

## Anhang: Referenzen

### Wissenschaftliche Quellen
- [TCP Checksum Failures](https://dl.acm.org/doi/10.1145/347059.347561) - Stone & Partridge, 2000
- [Fast Network Integrity](https://www.sciencedirect.com/science/article/abs/pii/S074373152100023X) - 2021
- [CERN Bit-Rot Study](https://cds.cern.ch/record/865788) - 2007

### Standards
- [BagIt RFC 8493](https://tools.ietf.org/html/rfc8493) - Library of Congress
- [NIST SP 800-131A](https://csrc.nist.gov/publications/detail/sp/800-131a/rev-2/final) - Hash-Algorithmen
- [OAIS ISO 14721](https://www.iso.org/standard/57284.html) - Archivierung

### Tool-Dokumentation
- [hashdeep Manual](https://md5deep.sourceforge.net/)
- [fclones GitHub](https://github.com/pkolaczk/fclones)
- [rsync Manual](https://rsync.samba.org/documentation.html)
- [exiftool Documentation](https://exiftool.org/)
