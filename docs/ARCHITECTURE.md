# Architektur: Datenassistent

> Systemdesign, Datenflüsse und Komponenten-Übersicht

---

## Systemübersicht

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DATENQUELLEN                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │ macOS APFS  │  │ macOS HFS+  │  │ Linux ext4  │  │ Windows     │        │
│  │ Time Machine│  │ External HD │  │ NFS/CIFS    │  │ NTFS        │        │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘        │
│         │                │                │                │               │
│         └────────────────┴────────────────┴────────────────┘               │
│                                   │                                         │
│                                   ▼                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                          MIGRATIONS-PIPELINE                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  PHASE 1: ERFASSUNG                                                 │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │   │
│  │  │ Pre-Flight  │→ │ Manifest    │→ │ xattr       │                 │   │
│  │  │ Checks      │  │ (hashdeep)  │  │ Dokumentation│                │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                   │                                         │
│                                   ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  PHASE 2: TRANSFER                                                  │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │   │
│  │  │ rsync       │→ │ Progress    │→ │ Logging     │                 │   │
│  │  │ --checksum  │  │ Monitoring  │  │             │                 │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                   │                                         │
│                                   ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  PHASE 3: VERIFIKATION                                              │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │   │
│  │  │ hashdeep    │→ │ Audit       │→ │ Summary     │                 │   │
│  │  │ Audit       │  │ Report      │  │ Log         │                 │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                              ROHDATEN-SPEICHER                              │
│                          _IMPORT_RAW/ (immutabel)                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                   │                                         │
│                                   ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  ANALYSE-PIPELINE                                                   │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │   │
│  │  │ Duplikat-   │  │ Metadaten-  │  │ Statistik-  │                 │   │
│  │  │ Erkennung   │  │ Extraktion  │  │ Reports     │                 │   │
│  │  │ (fclones)   │  │ (exiftool)  │  │             │                 │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                   │                                         │
│                                   ▼                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                            ZIEL-DATEISYSTEM                                 │
│                       Strukturierte Ablage (NAS/Cloud)                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Komponenten

### 1. Pre-Flight-Check-Modul

**Verantwortlichkeit:** Validierung aller Voraussetzungen vor Migration.

```
┌─────────────────────────────────────────┐
│           PRE-FLIGHT CHECKS             │
├─────────────────────────────────────────┤
│  ┌─────────────────┐                    │
│  │ Quelle          │                    │
│  │ - Existiert?    │                    │
│  │ - Lesbar?       │                    │
│  │ - Gemountet?    │                    │
│  └─────────────────┘                    │
│  ┌─────────────────┐                    │
│  │ Ziel            │                    │
│  │ - Existiert?    │                    │
│  │ - Schreibbar?   │                    │
│  │ - Genug Platz?  │                    │
│  └─────────────────┘                    │
│  ┌─────────────────┐                    │
│  │ Tools           │                    │
│  │ - hashdeep?     │                    │
│  │ - rsync?        │                    │
│  │ - fclones?      │                    │
│  └─────────────────┘                    │
│  ┌─────────────────┐                    │
│  │ Netzwerk        │                    │
│  │ - NAS erreichbar│                    │
│  │ - SMB-Mount OK? │                    │
│  └─────────────────┘                    │
└─────────────────────────────────────────┘
```

### 2. Manifest-Generator

**Verantwortlichkeit:** Forensische Prüfsummen-Erstellung.

```
Input: Quell-Verzeichnis
       │
       ▼
┌─────────────────────┐
│  hashdeep           │
│  -r -l -c sha256    │
└─────────────────────┘
       │
       ▼
Output: manifest_source.sha256
        ├── Dateigröße
        ├── SHA256-Hash
        └── Relativer Pfad
```

**Format:**
```
%%%% HASHDEEP-1.0
%%%% size,sha256,filename
2625,70e535f...917,./dokument.pdf
```

### 3. Transfer-Engine

**Verantwortlichkeit:** Zuverlässiger, verifizierbarer Dateitransfer.

```
┌─────────────────────────────────────────────────────────────┐
│                    TRANSFER ENGINE                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐ │
│  │ rsync   │ OR │ rclone  │ OR │ cp +    │ OR │ SSH     │ │
│  │ Primary │    │ Fast    │    │ verify  │    │ Tunnel  │ │
│  └────┬────┘    └────┬────┘    └────┬────┘    └────┬────┘ │
│       │              │              │              │       │
│       └──────────────┴──────────────┴──────────────┘       │
│                          │                                  │
│                          ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              TRANSFER-OPTIONEN                      │   │
│  │  • --checksum: Block-Level Prüfsummen              │   │
│  │  • -P: Partial + Progress (Resume-fähig)           │   │
│  │  • --exclude: macOS System-Dateien                 │   │
│  │  • --log-file: Detailliertes Protokoll             │   │
│  │  • --chown/--chmod: Ownership-Anpassung            │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Implementierungsbezug:**
- `scripts/migrate.sh` (End-to-End Migration mit rsync + hashdeep)

### 4. Audit-Verifikator

**Verantwortlichkeit:** Forensische Verifikation nach Transfer.

```
┌─────────────────────────────────────────────────────────────┐
│                    AUDIT VERIFIKATOR                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Input:                                                     │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │ Quell-Manifest  │    │ Ziel-Verzeichnis│                │
│  │ (Source of      │    │ (zu prüfen)     │                │
│  │  Truth)         │    │                 │                │
│  └────────┬────────┘    └────────┬────────┘                │
│           │                      │                          │
│           └──────────┬───────────┘                          │
│                      ▼                                      │
│           ┌─────────────────────┐                          │
│           │ hashdeep -a         │                          │
│           │ (Audit-Modus)       │                          │
│           └──────────┬──────────┘                          │
│                      │                                      │
│           ┌──────────┴──────────┐                          │
│           ▼                     ▼                          │
│  ┌─────────────────┐   ┌─────────────────┐                 │
│  │ "Audit passed"  │   │ Fehler-Report   │                 │
│  │ → ERFOLG        │   │ → FEHLER        │                 │
│  │ → Log schreiben │   │ → Details       │                 │
│  └─────────────────┘   │   - No match    │                 │
│                        │   - Modified    │                 │
│                        │   - Moved       │                 │
│                        │   - Not found   │                 │
│                        └─────────────────┘                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Implementierungsbezug:**
- `scripts/verify.sh` (Audit-only Verifikation gegen Manifest)

### 5. Duplikat-Analysator

**Verantwortlichkeit:** Erkennung identischer Dateien.

```
┌─────────────────────────────────────────────────────────────┐
│                  DUPLIKAT-ANALYSATOR                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Phase 1: Größen-Gruppierung                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Dateien nach Größe gruppieren (O(n))                │   │
│  │ → Nur Gruppen mit >1 Datei weiter prüfen           │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          ▼                                  │
│  Phase 2: Hash-Prefix                                       │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Ersten 64KB hashen (schnell)                        │   │
│  │ → Nur gleiche Prefixes weiter prüfen               │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          ▼                                  │
│  Phase 3: Vollständiger Hash                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Komplette Datei hashen                              │   │
│  │ → 100% byte-identisch garantiert                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          ▼                                  │
│  Output: Duplikat-Gruppen                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Group 1: [file_a.zip, copy_of_a.zip, backup/a.zip] │   │
│  │ Group 2: [doc.pdf, archive/doc.pdf]                │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Datenflüsse

### Migration Workflow

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  QUELLE  │ →  │ MANIFEST │ →  │ TRANSFER │ →  │  AUDIT   │ →  │ IMPORT   │
│          │    │          │    │          │    │          │    │  _RAW    │
└──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
     │               │               │               │               │
     ▼               ▼               ▼               ▼               ▼
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│ Dateien  │    │ SHA256   │    │ rsync    │    │ hashdeep │    │ 1:1      │
│ lesen    │    │ pro      │    │ Protokoll│    │ Audit    │    │ Kopie    │
│          │    │ Datei    │    │          │    │ Report   │    │          │
└──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
```

### Analyse Workflow

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│ IMPORT   │ →  │ DUPLIKAT │ →  │ METADATEN│ →  │ REPORTS  │
│ _RAW     │    │ SCAN     │    │ EXTRAKT  │    │          │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
     │               │               │               │
     ▼               ▼               ▼               ▼
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│ Alle     │    │ fclones  │    │ exiftool │    │ JSON/CSV │
│ Rohdaten │    │ JSON     │    │ CSV      │    │ Zusammen-│
│          │    │ Report   │    │          │    │ fassung  │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
```

---

## Verzeichnisstruktur

### Projekt-Repository

```
datenassistent/
├── README.md                 # Projekt-Übersicht
├── LICENSE                   # Apache 2.0
├── pyproject.toml           # Python-Projekt-Definition
│
├── docs/                    # Dokumentation
│   ├── WISSENSBASIS.md     # Konsolidiertes Wissen
│   ├── ARCHITECTURE.md     # Diese Datei
│   ├── TOOLS.md            # Tool-Referenz
│   └── WORKFLOWS.md        # Schritt-für-Schritt
│
├── src/                     # Quellcode
│   └── datenassistent/
│       ├── __init__.py
│       ├── __main__.py     # CLI Entry Point
│       ├── config/         # Konfiguration
│       ├── core/           # Kern-Logik
│       │   ├── manifest.py
│       │   ├── transfer.py
│       │   ├── verify.py
│       │   └── duplicates.py
│       ├── platforms/      # OS-spezifisch
│       └── utils/          # Hilfsfunktionen
│
├── scripts/                 # Shell-Scripts
│   ├── migrate.sh          # Haupt-Migration
│   ├── verify.sh           # Standalone-Verifikation
│   ├── analyze.sh          # Duplikat-Analyse
│   └── preflight.sh        # Voraussetzungsprüfung
│
├── templates/              # Konfigurationsvorlagen
│   ├── config.toml.example
│   └── exclusions.txt
│
└── tests/                  # Test-Suite
    ├── test_manifest.py
    ├── test_transfer.py
    └── test_verify.py
```

### Migrations-Arbeitsverzeichnis

```
_MIGRATION_PROJECT/
├── CLAUDE.md               # AI-Kontext
├── AGENTS.md               # Universeller AI-Standard
├── README.md               # Projekt-Dokumentation
│
├── manifests/              # SHA256-Prüfsummen
│   ├── disk01_source.sha256
│   ├── disk02_source.sha256
│   └── ...
│
├── metadata/               # Extrahierte Metadaten
│   ├── disk01_xattrs.txt
│   ├── disk01_exif.csv
│   └── ...
│
├── logs/                   # Operations-Logs
│   ├── YYYY-MM-DD_diskXX_rsync.log
│   ├── YYYY-MM-DD_diskXX_audit.log
│   └── verification_summary.log  # Master-Log
│
├── reports/                # Analyse-Reports
│   ├── duplicates.json
│   ├── statistics.txt
│   └── ...
│
└── scripts/                # Migrations-Scripts
    ├── copy-disk01.sh
    ├── copy-disk02.sh
    └── ...
```

---

## Sicherheitsarchitektur

### Datenfluss-Sicherheit

```
┌─────────────────────────────────────────────────────────────┐
│                   SICHERHEITSSCHICHTEN                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. SOURCE OF TRUTH                                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Quell-Manifest (hashdeep)                           │   │
│  │ → SHA-256 jeder Datei                               │   │
│  │ → Unveränderlich nach Erstellung                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  2. TRANSFER-INTEGRITÄT                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ rsync --checksum                                    │   │
│  │ → Block-Level Rolling Checksums                     │   │
│  │ → Erkennt Korruption während Transfer              │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  3. POST-TRANSFER-AUDIT                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ hashdeep Audit-Modus                                │   │
│  │ → Bit-für-Bit Vergleich gegen Manifest             │   │
│  │ → Keine Toleranz für Abweichungen                  │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  4. IMMUTABILITÄT                                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ _IMPORT_RAW/ ist read-only                          │   │
│  │ → Keine Modifikationen nach Verifikation           │   │
│  │ → Alle Transformationen auf Kopien                 │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  5. AUDIT-TRAIL                                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ verification_summary.log (append-only)              │   │
│  │ → Jede Operation mit Timestamp                      │   │
│  │ → Quelle, Ziel, Ergebnis dokumentiert              │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Fehlerbehandlungs-Hierarchie

```
┌─────────────────────────────────────────────────────────────┐
│                  FEHLERBEHANDLUNG                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Level 1: PREVENTION                                        │
│  ├─ Pre-Flight Checks                                      │
│  ├─ Speicherplatz-Prüfung                                  │
│  └─ Tool-Verfügbarkeit                                     │
│                                                             │
│  Level 2: DETECTION                                         │
│  ├─ rsync Checksums erkennen Bit-Fehler                    │
│  ├─ hashdeep Audit erkennt Abweichungen                    │
│  └─ Logging aller Operationen                              │
│                                                             │
│  Level 3: RECOVERY                                          │
│  ├─ rsync -P ermöglicht Resume                             │
│  ├─ PAR2 kann beschädigte Dateien reparieren               │
│  └─ Original-Quelle bleibt unverändert                     │
│                                                             │
│  Level 4: DOCUMENTATION                                     │
│  ├─ Alle Fehler werden geloggt                             │
│  ├─ Manifeste dokumentieren erwarteten Zustand             │
│  └─ Audit-Logs ermöglichen Nachverfolgung                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```
