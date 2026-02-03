# Tool-Referenz

> Vollständige Dokumentation aller Werkzeuge für Datenmigration und -verwaltung

---

## Übersicht

| Tool | Kategorie | Zweck | Installation (NixOS) |
|------|-----------|-------|----------------------|
| **hashdeep** | Verifikation | Forensische SHA256-Manifeste | `nix-shell -p hashdeep` |
| **rsync** | Transfer | Intelligentes Kopieren mit Checksums | Vorinstalliert |
| **fclones** | Analyse | Duplikat-Erkennung (Rust, schnell) | `nix-shell -p fclones` |
| **rclone** | Transfer | Multi-Cloud/SMB-Sync (schnell) | `nix-shell -p rclone` |
| **exiftool** | Metadaten | Extraktion und Modifikation | `nix-shell -p exiftool` |
| **par2** | Archivierung | Fehlerkorrektur-Redundanz | `nix-shell -p par2cmdline` |

---

## hashdeep

### Zweck
Forensische Prüfsummen-Erstellung und -Verifikation nach Industriestandard.

### Installation
```bash
nix-shell -p hashdeep
# Oder permanent in configuration.nix
```

### Grundlegende Verwendung

**Manifest erstellen:**
```bash
cd /pfad/zur/quelle
hashdeep -r -l -c sha256 . > manifest.sha256
```

**Manifest verifizieren (Audit):**
```bash
cd /pfad/zum/ziel
hashdeep -r -l -k /pfad/zu/manifest.sha256 -a .
```

### Alle Flags

| Flag | Lang | Bedeutung |
|------|------|-----------|
| `-r` | `--recursive` | Rekursiv in Unterverzeichnisse |
| `-l` | - | Relative Pfade im Manifest |
| `-c <alg>` | - | Hash-Algorithmus (md5, sha1, sha256, tiger, whirlpool) |
| `-k <file>` | - | Manifest-Datei für Vergleich |
| `-a` | `--audit` | Audit-Modus (streng, meldet alle Abweichungen) |
| `-m` | `--match` | Match-Modus (nur bekannte Dateien anzeigen) |
| `-x` | `--exclude` | Negative Match (nur unbekannte Dateien) |
| `-e` | - | Fortschrittsanzeige |
| `-b` | `--basename` | Nur Dateinamen vergleichen (nicht Pfade) |

### Beispiele

```bash
# Mehrere Hash-Algorithmen gleichzeitig
hashdeep -r -c md5,sha256 /quelle > manifest_multi.txt

# Mit Fortschrittsanzeige
hashdeep -r -l -c sha256 -e /grosse/quelle > manifest.sha256

# Nur unbekannte Dateien finden (neue seit Manifest)
hashdeep -r -l -k manifest.sha256 -x /ziel

# Nur bekannte Dateien (zum Verifizieren dass alle da sind)
hashdeep -r -l -k manifest.sha256 -m /ziel
```

### Output-Format

```
%%%% HASHDEEP-1.0
%%%% size,sha256,filename
## Invoked from: /source/path
## $ hashdeep -r -l -c sha256 .
2625,70e535f1a0feaa1404267f9f80b2a20ebc56371b7e34369c58214f266eca7917,./file.txt
```

---

## rsync

### Zweck
Effizientes, inkrementelles Kopieren mit Delta-Algorithmus.

### Basis-Kommando

```bash
rsync -avhP --checksum /quelle/ /ziel/
```

### Wichtige Flags

| Flag | Bedeutung |
|------|-----------|
| `-a` | Archiv: rekursiv, Links, Berechtigungen, Zeiten, Gruppen, Owner, Devices |
| `-v` | Verbose (mehr Ausgabe) |
| `-h` | Human-readable Größen |
| `-P` | `--partial --progress` (Resume + Fortschritt) |
| `--checksum` | Block-Level Prüfsummen statt nur mtime/size |
| `--delete` | Dateien im Ziel löschen die nicht in Quelle (VORSICHT!) |
| `--dry-run` | Simulation ohne Änderungen |
| `--exclude` | Pattern ausschließen |
| `--log-file` | Detailliertes Log schreiben |
| `-H` | Hard-Links erhalten |
| `-X` | Extended Attributes erhalten (Linux) |
| `-E` | Extended Attributes erhalten (macOS) |
| `--chown` | Ownership ändern |
| `--chmod` | Permissions ändern |

### Typische Migrationsszenarien

**Standard-Migration:**
```bash
rsync -avhP --checksum \
  --exclude='.DS_Store' \
  --exclude='._*' \
  --exclude='.Spotlight-*' \
  --log-file=/tmp/rsync.log \
  /quelle/ /ziel/
```

**Mit Ownership-Anpassung (als root):**
```bash
sudo rsync -avhP --checksum \
  --chown=user:group \
  --chmod=D755,F644 \
  /quelle/ /ziel/
```

**Über SSH:**
```bash
rsync -avhP --checksum \
  -e "ssh -o Compression=no" \
  /quelle/ user@server:/ziel/
```

**Nur bestimmte Dateitypen:**
```bash
rsync -avhP --include='*.pdf' --include='*/' --exclude='*' /quelle/ /ziel/
```

### Trailing Slash Semantik

```bash
rsync /quelle /ziel    # Erstellt /ziel/quelle/...
rsync /quelle/ /ziel/  # Kopiert Inhalt nach /ziel/...
```

**Regel:** Bei Migration immer `/quelle/` und `/ziel/` mit Trailing Slash.

---

## fclones

### Zweck
Schnellste Duplikat-Erkennung (Rust, parallelisiert, 7x schneller als jdupes).

### Installation
```bash
nix-shell -p fclones
```

### Grundlegende Verwendung

**Duplikate finden (nur Report):**
```bash
fclones group /pfad --min 1M -o duplicates.txt
```

**JSON-Output:**
```bash
fclones group /pfad --min 1M -f json > duplicates.json
```

### Alle Befehle

| Befehl | Zweck |
|--------|-------|
| `group` | Duplikat-Gruppen finden und anzeigen |
| `link` | Duplikate durch Hard-Links ersetzen (spart Speicher) |
| `dedupe` | Reflinks erstellen (nur btrfs/XFS mit reflink) |
| `remove` | Duplikate löschen (VORSICHT!) |
| `move` | Duplikate in anderen Ordner verschieben |

### Wichtige Flags

| Flag | Bedeutung |
|------|-----------|
| `--min <size>` | Minimum-Dateigröße (z.B. `1M`, `100K`) |
| `--max <size>` | Maximum-Dateigröße |
| `-o <file>` | Output-Datei |
| `-f <format>` | Format: `default`, `json`, `csv` |
| `--dry-run` | Simulation ohne Änderungen |
| `--threads <n>` | Anzahl Threads (Default: Auto) |
| `--name <pattern>` | Nur Dateien mit Pattern |
| `--exclude <pattern>` | Dateien ausschließen |
| `--follow-links` | Symlinks folgen |

### Beispiele

```bash
# Cross-Disk-Analyse (mehrere Pfade)
fclones group /disk1 /disk2 /disk3 --min 1M -o all_duplicates.txt

# Nur Bilder
fclones group /fotos --name '*.jpg' --name '*.png' -o image_dupes.txt

# Hard-Links erstellen (Dry-Run zuerst!)
fclones link /pfad --min 1M --dry-run
fclones link /pfad --min 1M  # Wenn OK

# Duplikate entfernen, neueste behalten
fclones remove /pfad --min 1M --keep newest --dry-run
```

### Output-Format (Default)

```
# Group 1: 3 files, 15.2 MB each
/path/to/file1.zip
/path/to/copy/file1.zip
/backup/file1.zip

# Group 2: 2 files, 8.1 MB each
/documents/report.pdf
/archive/report.pdf
```

---

## rclone

### Zweck
Universeller Sync-Client für Cloud-Dienste und lokale Dateisysteme. 4-10x schneller als rsync für große Dateien.

### Installation
```bash
nix-shell -p rclone
```

### Konfiguration

```bash
# Interaktive Konfiguration
rclone config

# Oder direkt für SMB/CIFS
rclone config create nas smb host=192.168.1.100 user=username pass=password
```

### Grundlegende Verwendung

**Lokaler Transfer:**
```bash
rclone copy /quelle /ziel --progress
```

**Zu SMB-Share:**
```bash
rclone copy /quelle nas:/share/ziel --progress
```

### Wichtige Flags

| Flag | Bedeutung |
|------|-----------|
| `--progress` / `-P` | Fortschrittsanzeige |
| `--transfers <n>` | Parallele Transfers (Default: 4) |
| `--checkers <n>` | Parallele Hash-Prüfungen (Default: 8) |
| `--checksum` | Hash-basierter Vergleich |
| `--dry-run` | Simulation |
| `--retries <n>` | Wiederholungsversuche |
| `--low-level-retries <n>` | Low-Level Retries |
| `--ignore-errors` | Bei Fehlern weitermachen |
| `--stats 1s` | Statistik alle 1 Sekunde |

### Befehle

| Befehl | Zweck |
|--------|-------|
| `copy` | Dateien kopieren (nicht im Ziel löschen) |
| `sync` | Synchronisieren (löscht im Ziel!) |
| `move` | Verschieben |
| `check` | Vergleichen ohne Kopieren |
| `ls` | Dateien auflisten |
| `lsf` | Dateien auflisten (Format) |
| `size` | Gesamtgröße |

### Performance-Tuning

```bash
rclone copy /quelle /ziel \
  --progress \
  --transfers 8 \
  --checkers 16 \
  --buffer-size 64M \
  --multi-thread-streams 4
```

---

## exiftool

### Zweck
Metadaten-Extraktion und -Modifikation für 200+ Dateiformate.

### Installation
```bash
nix-shell -p exiftool
```

### Metadaten lesen

```bash
# Alle Metadaten einer Datei
exiftool datei.pdf

# Bestimmte Felder
exiftool -Title -Author -CreateDate datei.pdf

# Rekursiv als CSV
exiftool -csv -r /ordner > metadata.csv

# Als JSON
exiftool -json -r /ordner > metadata.json
```

### Metadaten schreiben

```bash
# PDF-Metadaten setzen
exiftool -Title="Mein Titel" -Author="Max Mustermann" datei.pdf

# Original-Dateiname in Description speichern
exiftool -Description="Original: alter_name.pdf" datei.pdf

# XMP/Dublin Core
exiftool -XMP-dc:Title="Titel" -XMP-dc:Creator="Autor" datei.pdf

# Erstellungsdatum setzen
exiftool -CreateDate="2024:01:15 10:30:00" datei.pdf
```

### Batch-Operationen

```bash
# Alle PDFs im Ordner
exiftool -Author="Firma GmbH" *.pdf

# Rekursiv
exiftool -r -Author="Firma GmbH" /ordner/

# Dateiname aus Metadaten
exiftool '-FileName<CreateDate' -d '%Y%m%d_%H%M%S%%-c.%%e' *.jpg
```

### Wichtige Flags

| Flag | Bedeutung |
|------|-----------|
| `-r` | Rekursiv |
| `-csv` | CSV-Output |
| `-json` | JSON-Output |
| `-overwrite_original` | Kein Backup erstellen |
| `-d <format>` | Datumsformat |
| `-ext <ext>` | Nur bestimmte Extensions |

---

## par2

### Zweck
Parity Archive Volume Set - Fehlerkorrektur-Dateien für Bit-Rot-Schutz.

### Installation
```bash
nix-shell -p par2cmdline
```

### Verwendung

**Recovery-Dateien erstellen (5% Redundanz):**
```bash
par2 create -r5 archiv.par2 /pfad/zu/dateien/*
```

**Integrität prüfen:**
```bash
par2 verify archiv.par2
```

**Reparieren:**
```bash
par2 repair archiv.par2
```

### Flags

| Flag | Bedeutung |
|------|-----------|
| `-r<n>` | Redundanz in Prozent (z.B. `-r5` = 5%) |
| `-n<n>` | Anzahl Recovery-Blöcke |
| `-u` | Uniform Recovery-Block-Größe |
| `-B<path>` | Basis-Pfad für Dateien |

### Empfehlung

```bash
# Für kritische Archive: 10% Redundanz
par2 create -r10 wichtige_daten.par2 /archiv/*

# Für normale Daten: 5%
par2 create -r5 backup.par2 /backup/*
```

---

## Kombinierte Workflows

### Komplette Migration mit Verifikation

```bash
#!/usr/bin/env bash
set -euo pipefail

SOURCE="/quelle"
DEST="/ziel"
MANIFEST="manifest.sha256"

# 1. Quell-Manifest
cd "$SOURCE"
hashdeep -r -l -c sha256 . > "/tmp/$MANIFEST"

# 2. Transfer
rsync -avhP --checksum "$SOURCE/" "$DEST/"

# 3. Verifikation
cd "$DEST"
hashdeep -r -l -k "/tmp/$MANIFEST" -a .
echo "Audit bestanden!"
```

### Verifikation als eigener Schritt (verify.sh)

```bash
# Audit-only gegen vorhandenes Manifest
bash scripts/verify.sh /pfad/zum/manifest.sha256 /ziel/_IMPORT_RAW/disk01
```

**Hinweis:** Das Script erwartet ein Manifest, das mit `hashdeep -l` erzeugt wurde.

### Duplikat-Analyse und Bereinigung

```bash
#!/usr/bin/env bash
IMPORT="/import_raw"

# 1. Analyse
fclones group "$IMPORT" --min 1M -f json > duplicates.json
fclones group "$IMPORT" --min 1M -o duplicates_readable.txt

# 2. Statistik
echo "Gefundene Duplikat-Gruppen:"
jq 'length' duplicates.json

# 3. Hard-Links (nach manueller Prüfung)
# fclones link "$IMPORT" --min 1M
```

### Metadaten-Export vor Migration

```bash
#!/usr/bin/env bash
SOURCE="/quelle"
METADATA_DIR="/metadata"

mkdir -p "$METADATA_DIR"

# Alle Metadaten als CSV
exiftool -csv -r "$SOURCE" > "$METADATA_DIR/all_metadata.csv"

# Extended Attributes
getfattr -R -d -m - "$SOURCE" > "$METADATA_DIR/xattrs.txt" 2>/dev/null || true

echo "Metadaten exportiert nach $METADATA_DIR"
```
