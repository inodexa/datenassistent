# Datenassistent

> Wissenschaftlich fundiertes Framework für integritätserhaltende Datenmigration und -verwaltung

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Python-3.13+-green.svg)](https://python.org)

## Überblick

Datenassistent konsolidiert Best Practices, wissenschaftliche Erkenntnisse und praxiserprobte Werkzeuge für:

- **Integritätserhaltende Migration** von Datenträgern (macOS/Linux → NAS)
- **Forensische Verifikation** mit kryptographischen Prüfsummen
- **Intelligente Deduplizierung** ohne Datenverlust
- **Metadaten-Preservierung** (Extended Attributes, PDF-Metadaten, Tags)
- **Cross-Platform-Kompatibilität** (APFS, HFS+, ext4, NTFS, SMB/CIFS)

## Wissenschaftliche Grundlage

| Erkenntnis | Quelle | Konsequenz |
|------------|--------|------------|
| TCP-Checksums versagen bei ~5% aller Transfers | [ScienceDirect 2021](https://www.sciencedirect.com/science/article/abs/pii/S074373152100023X) | End-to-End SHA256-Verifikation obligatorisch |
| SHA-1/MD5 gelten als unsicher | [NIST SP 800-131A](https://csrc.nist.gov/publications/detail/sp/800-131a/rev-2/final) | SHA-256 als Minimum-Standard |
| Bit-Rot betrifft ~0.5% aller Dateien/Jahr | [CERN Studies](https://cds.cern.ch/record/865788) | PAR2-Fehlerkorrektur für Langzeitarchivierung |

## Kernprinzipien

### 1. Drei-Phasen-Verifikation
```
Quelle → hashdeep Manifest → rsync --checksum → hashdeep Audit → Ziel
```

### 2. Immutabilität von Rohdaten
Originaldaten werden **niemals** verändert. Alle Transformationen erfolgen auf Kopien.

### 3. Vollständige Audit-Trails
Jede Operation wird mit Timestamp, Quelle, Ziel und Ergebnis protokolliert.

### 4. Graceful Degradation
Bei Fehlern: Informieren, nicht abstürzen. Selbstheilung wo möglich.

## Projektstruktur

```
datenassistent/
├── docs/                    # Dokumentation
│   ├── WISSENSBASIS.md     # Konsolidiertes Wissen
│   ├── ARCHITECTURE.md     # Systemarchitektur
│   ├── TOOLS.md            # Tool-Dokumentation
│   └── WORKFLOWS.md        # Standardisierte Workflows
├── src/                     # Quellcode
│   └── datenassistent/     # Python-Package
├── scripts/                 # Shell-Scripts für Migration
├── templates/              # Konfigurationsvorlagen
└── tests/                  # Test-Suite
```

## Schnellstart

```bash
# Installation (NixOS)
nix-shell -p hashdeep fclones exiftool

# Migration starten
bash scripts/migrate.sh /path/to/source /path/to/destination

# Verifikation prüfen
bash scripts/verify.sh /path/to/manifest.sha256 /path/to/destination
```

**Hinweis (macOS/APFS unter Linux):** APFS-Mounts haben oft UID/GID-Mapping-Probleme.
Nutze ggf. `sudo` und/oder `apfs-fuse -o uid=...,gid=...`.

**Hinweis (SMB-Performance, macOS):** `signing_required=no` und `dir_cache_off=yes`
in `/etc/nsmb.conf` können Transfers deutlich beschleunigen. Audit bleibt Pflicht.

## Dokumentation

- [Wissensbasis](docs/WISSENSBASIS.md) - Konsolidiertes Expertenwissen
- [Architektur](docs/ARCHITECTURE.md) - Systemdesign und Datenflüsse
- [Tools](docs/TOOLS.md) - Tool-Referenz mit Beispielen
- [Workflows](docs/WORKFLOWS.md) - Schritt-für-Schritt-Anleitungen

## Lizenz

Apache License 2.0 - Siehe [LICENSE](LICENSE)

## Mitwirkende

- **inodexa services GmbH** - Ursprüngliche Konzeption und Implementierung
