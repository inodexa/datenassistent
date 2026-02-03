# Datenassistent - Design-Dokument

**Datum:** 2026-02-03
**Status:** Validiert

## Übersicht

Der **Datenassistent** ist ein Python-basiertes Cross-Platform-TUI-Tool für integritätserhaltende Datenkopien. Er abstrahiert bewährte Tools (rsync, rclone, restic, borg, etc.) hinter einer einheitlichen, geführten Oberfläche.

### Kernprinzipien

1. **Integrität zuerst** - Lieber abbrechen als beschädigte Daten
2. **Transparenz** - Nutzer sieht immer was passiert
3. **Best Practices by Default** - Sichere Standardeinstellungen
4. **Flexibilität** - Erfahrene Nutzer können alles anpassen

### Entscheidungen im Überblick

| Aspekt | Entscheidung |
|--------|--------------|
| Sprache | Python mit textual TUI |
| Plattform | Cross-Platform (Linux, macOS, Windows) |
| Bedienung | Wizard-geführt mit Dashboard-Feedback |
| Backends | rsync, rclone, restic, borg, robocopy, ditto, native |
| Backend-Auswahl | Automatisch basierend auf Situation |
| Metadaten | Konfigurierbar: Vollständig / Portabel / Minimal |
| Verifikation | Mehrstufig: Schnell (Größe/Datum) + Tief (BLAKE3/SHA256) |
| Konflikte | Strategie vorwählbar + Checksummen-Info bei Unterschieden |
| Fehlerbehandlung | Sofortiger Abbruch bei Fehlern |
| Abbruch-Verhalten | Konfigurierbar: Aufräumen / Behalten / Alles behalten |
| Dry-Run | Standard vor jeder Operation |
| Logging | SQLite-Datenbank, detailliert, abfragbar |
| Konfiguration | XDG + projektspezifische Overrides |

---

## 1. Architektur

```
┌─────────────────────────────────────────┐
│         TUI (textual)                   │  ← Wizard + Dashboard
├─────────────────────────────────────────┤
│         Core Logic                      │  ← Orchestrierung, Verifikation
├─────────────────────────────────────────┤
│         Backend Abstraction Layer       │  ← Einheitliches Interface
├──────┬──────┬──────┬──────┬────────────┤
│rsync │rclone│restic│borg  │ native (cp)│  ← Backends
└──────┴──────┴──────┴──────┴────────────┘
```

**Intelligente Backend-Auswahl:** Das System wählt automatisch das optimale Tool basierend auf:
- Quelle/Ziel (lokal, SSH, Cloud, S3, etc.)
- Verfügbarkeit auf dem System
- Anforderungen (Delta-Sync, Deduplizierung, etc.)

---

## 2. Wizard-Flow & Benutzerführung

Der Kopiervorgang folgt einem klaren **5-Schritte-Wizard**:

```
[1. Quelle] → [2. Ziel] → [3. Optionen] → [4. Vorschau] → [5. Ausführung]
```

### Schritt 1 - Quelle wählen
- Dateibrowser mit Tastaturnavigation
- Mehrfachauswahl möglich (Dateien/Ordner)
- Schnellzugriff auf häufige Orte (Lesezeichen, Recent)
- Anzeige von Metadaten-Info (Größe, Anzahl Dateien)

### Schritt 2 - Ziel wählen
- Gleicher Browser, aber mit "Neuen Ordner erstellen"
- Warnung bei ungewöhnlichen Zielen (z.B. Root, Systemordner)
- Platzprüfung: Reicht der Speicherplatz?

### Schritt 3 - Optionen
- **Metadaten-Modus:** Vollständig / Portabel / Minimal
- **Konflikt-Strategie:** Neuere behalten / Größere / Immer überschreiben / Nie
- **Verifikation:** Schnell (Größe+Datum) / Tief (Checksumme)
- **Backend:** Automatisch / Manuell wählen
- **Bei Abbruch:** Aufräumen / Behalten / Alles behalten

### Schritt 4 - Vorschau (Dry-Run)
- Liste aller Aktionen: "Kopieren", "Überspringen", "Konflikt"
- Zusammenfassung: X Dateien, Y GB, geschätzter Speicherbedarf
- Konflikte mit Checksummen-Vergleich hervorgehoben

### Schritt 5 - Ausführung
- Wechsel in Dashboard-Ansicht

---

## 3. Dashboard-Ansicht

Nach Bestätigung wechselt die TUI in den **Dashboard-Modus**:

```
┌─────────────────────────────────────────────────────────────────┐
│  Datenassistent - Kopiervorgang läuft                [ESC=Abbrechen] │
├─────────────────────────────────────────────────────────────────┤
│  Fortschritt: ████████████░░░░░░░░ 58%    1.2 GB / 2.1 GB      │
│  Dateien:     142 / 245                   Geschwindigkeit: 85 MB/s │
│  Verstrichene Zeit: 00:02:14              Verbleibend: ~00:01:38   │
├─────────────────────────────────────────────────────────────────┤
│  Aktuelle Datei:                                                │
│  /home/user/Fotos/2024/urlaub/DSC_4521.ARW → /backup/Fotos/... │
├─────────────────────────────────────────────────────────────────┤
│  Log (letzte Aktionen):                                         │
│  ✓ DSC_4519.ARW ....................................... 24.5 MB │
│  ✓ DSC_4520.ARW ....................................... 24.1 MB │
│  ⏳ DSC_4521.ARW ...................................... [58%]    │
├─────────────────────────────────────────────────────────────────┤
│  Backend: rsync │ Verifikation: SHA256 │ Metadaten: Vollständig │
└─────────────────────────────────────────────────────────────────┘
```

**Features:**
- Live-Fortschritt mit Geschwindigkeit und ETA
- Scrollbares Log der abgeschlossenen Dateien
- Sofort sichtbar welches Backend/welche Optionen aktiv
- Abbruch jederzeit möglich

**Nach Abschluss:**
- Zusammenfassung: Erfolg/Fehler, Statistiken
- Verifikationsergebnis mit Checksummen
- Option: "Log speichern", "Erneut ausführen", "Neuer Vorgang"

---

## 4. Backend Abstraction Layer

Einheitliche Schnittstelle für alle Tools:

```python
class CopyBackend(Protocol):
    """Interface das jedes Backend implementiert"""

    def supports(self, source: Path, target: Path) -> bool: ...
    def dry_run(self, job: CopyJob) -> PreviewResult: ...
    def execute(self, job: CopyJob, progress_callback) -> CopyResult: ...
    def verify(self, job: CopyJob, mode: VerifyMode) -> VerifyResult: ...
    def cancel(self) -> None: ...
```

### Verfügbare Backends

| Backend | Lokal | SSH | S3/Cloud | Dedupe | Delta-Sync |
|---------|-------|-----|----------|--------|------------|
| rsync | ✓ | ✓ | ✗ | ✗ | ✓ |
| rclone | ✓ | ✓ | ✓ | ✗ | ✓ |
| restic | ✓ | ✓ | ✓ | ✓ | ✓ |
| borg | ✓ | ✓ | ✗ | ✓ | ✓ |
| robocopy | ✓ (Win) | ✗ | ✗ | ✗ | ✓ |
| ditto | ✓ (mac) | ✗ | ✗ | ✗ | ✗ |
| native | ✓ | ✗ | ✗ | ✗ | ✗ |

### Automatische Auswahl-Logik
1. Welche Backends sind installiert?
2. Was unterstützt die Quelle/Ziel-Kombination?
3. Welche Anforderungen hat der Nutzer (Dedupe, Cloud, etc.)?
4. → Bestes verfügbares Backend vorschlagen

**Fallback-Kette:** Wenn bevorzugtes Backend fehlt → nächstbestes → native Python-Implementierung als letzter Ausweg

---

## 5. Metadaten-Handling

### Drei Modi

**Vollständig (für lokale Backups):**
- POSIX: Permissions, Owner/Group, ACLs, xattrs, Timestamps
- macOS: Finder-Flags, Resource Forks, Quarantine-Attribute
- Windows: NTFS-Streams, Security Descriptors, Attribute
- Linux: SELinux-Kontexte, Capabilities

**Portabel (für Cross-Platform-Transfer):**
- Nur universelle Attribute: Timestamps, Basis-Permissions
- Nicht-übertragbare Metadaten → Sidecar-Datei (`.datenassistent-meta.json`)
- Sidecar ermöglicht spätere Wiederherstellung auf gleicher Plattform

**Minimal (für maximale Kompatibilität):**
- Nur Dateiinhalt, keine Metadaten
- Für Transfers zu eingeschränkten Zielen (FAT32, manche Cloud-Storage)

### Warnungen

```
⚠ Warnung: Ziel ist FAT32 - folgende Metadaten gehen verloren:
  - Permissions (rwxr-xr-x)
  - Owner/Group (tamino:users)
  - Symlinks (3 gefunden)
  → Empfehlung: Wechsel zu "Portabel" für Sidecar-Backup
```

---

## 6. Verifikation & Integritätssicherung

### Mehrstufiges System

**Schnelle Prüfung (Standard):**
- Größe und Änderungsdatum vergleichen
- Erkennt: Abgebrochene Kopien, offensichtliche Fehler
- Geschwindigkeit: ~1000 Dateien/Sekunde

**Tiefe Prüfung (Checksumme):**
- BLAKE3 (bevorzugt, schnell) oder SHA256 (breite Kompatibilität)
- Erkennt: Bit-Rot, stille Korruption, alle Datenabweichungen
- Geschwindigkeit: Disk-I/O-limitiert (~500 MB/s auf SSD)

### Verifikations-Workflow

```
Kopieren → Schnelle Prüfung → [Optional: Tiefe Prüfung] → Ergebnis
                                        │
                            Bei Langzeitarchivierung
                            automatisch empfohlen
```

### Checksummen-Speicherung
- Alle berechneten Checksummen → SQLite-Datenbank
- Ermöglicht spätere Re-Verifikation ohne Quelle
- Export als `.sha256` / `.blake3` Manifest-Dateien möglich

### Bei Verifikationsfehler

```
✗ Verifikation fehlgeschlagen:
  /backup/Fotos/DSC_4521.ARW
    Erwartet:  blake3:a4f2e8...
    Gefunden:  blake3:9b1c7d...
  → Kopie abgebrochen. Ziel bleibt unverändert.
```

---

## 7. Abbruch-Verhalten

Konfigurierbar im Wizard (Schritt 3 - Optionen):

**Aufräumen (Standard):**
- Unvollständige Dateien am Ziel löschen
- Zustand vor dem Transfer wiederherstellen

**Behalten:**
- Bereits vollständig kopierte Dateien behalten
- Nur aktuelle unvollständige Datei löschen

**Alles behalten:**
- Nichts löschen, auch unvollständige Dateien bleiben
- Für spätere Fortsetzung mit rsync/rclone

### Anzeige bei Abbruch

```
┌─────────────────────────────────────────────────────────────────┐
│  ⚠ Transfer abgebrochen                                         │
├─────────────────────────────────────────────────────────────────┤
│  Vollständig kopiert:    89 Dateien (1.8 GB)                   │
│  Unvollständig:          1 Datei (DSC_4521.ARW, 58%)           │
│  Noch ausstehend:        155 Dateien                            │
├─────────────────────────────────────────────────────────────────┤
│  Aktion: "Behalten" - Vollständige Dateien bleiben erhalten    │
│          Unvollständige Datei wurde gelöscht                    │
├─────────────────────────────────────────────────────────────────┤
│  [Fortsetzen]  [Log speichern]  [Schließen]                    │
└─────────────────────────────────────────────────────────────────┘
```

### Fortsetzung nach Abbruch
- Job wird in SQLite als "aborted" mit Liste der ausstehenden Dateien gespeichert
- Option "Fortsetzen" startet neuen Job mit nur den fehlenden Dateien
- Backends wie rsync/rclone nutzen automatisch Delta-Sync

---

## 8. Konflikt-Behandlung

### Vordefinierte Strategien (im Wizard wählbar)
- **Neuere behalten** - Datei mit neuerem Timestamp gewinnt
- **Größere behalten** - Größere Datei gewinnt
- **Immer überschreiben** - Ziel wird immer ersetzt
- **Nie überschreiben** - Bestehende Dateien bleiben

### Intelligenter Vergleich
Bei echten Unterschieden zusätzlich Checksummen-Info:
- Identische Checksumme → automatisch überspringen
- Unterschiedliche Checksumme → Strategie anwenden + Info anzeigen

---

## 9. Logging & Datenbank

SQLite-Datenbank in `~/.local/share/datenassistent/history.db`:

### Schema

```sql
-- Jeder Kopiervorgang
jobs (
    id              INTEGER PRIMARY KEY,
    started_at      TIMESTAMP,
    finished_at     TIMESTAMP,
    source_path     TEXT,
    target_path     TEXT,
    backend_used    TEXT,           -- 'rsync', 'rclone', etc.
    metadata_mode   TEXT,           -- 'full', 'portable', 'minimal'
    verify_mode     TEXT,           -- 'quick', 'deep'
    abort_behavior  TEXT,           -- 'cleanup', 'keep', 'keep_all'
    status          TEXT,           -- 'success', 'failed', 'aborted'
    total_files     INTEGER,
    total_bytes     INTEGER,
    error_message   TEXT
)

-- Jede kopierte Datei
files (
    id              INTEGER PRIMARY KEY,
    job_id          INTEGER REFERENCES jobs(id),
    source_path     TEXT,
    target_path     TEXT,
    size_bytes      INTEGER,
    checksum_algo   TEXT,           -- 'blake3', 'sha256', NULL
    checksum_value  TEXT,
    status          TEXT,           -- 'copied', 'skipped', 'failed', 'pending'
    metadata_json   TEXT            -- Gesicherte Metadaten
)

-- Konflikte und Entscheidungen
conflicts (
    id              INTEGER PRIMARY KEY,
    job_id          INTEGER REFERENCES jobs(id),
    file_path       TEXT,
    conflict_type   TEXT,           -- 'exists', 'different_size', etc.
    resolution      TEXT,           -- 'overwrite', 'skip', 'rename'
    source_checksum TEXT,
    target_checksum TEXT
)
```

### Abfrage-Möglichkeiten
- "Wann wurde diese Datei zuletzt gesichert?"
- "Welche Dateien hatten Konflikte?"
- "Alle Jobs der letzten 30 Tage"
- "Dateien mit fehlgeschlagener Verifikation"
- "Abgebrochene Jobs die fortgesetzt werden können"

---

## 10. Konfiguration

### XDG-konforme Verzeichnisstruktur

```
~/.config/datenassistent/
├── config.toml              # Globale Einstellungen
└── backends/
    ├── rsync.toml           # Backend-spezifische Optionen
    └── rclone.toml

~/.local/share/datenassistent/
├── history.db               # SQLite Log-Datenbank
├── bookmarks.toml           # Schnellzugriff-Orte
└── checksums/               # Exportierte Manifeste
    └── 2024-01-15_backup.blake3

# Optional: Projektspezifisch
.datenassistent/
├── config.toml              # Überschreibt globale Config
└── default-target.toml      # Vordefiniertes Ziel für diesen Ordner
```

### Beispiel config.toml

```toml
[defaults]
metadata_mode = "full"
verify_mode = "quick"
conflict_strategy = "ask"
abort_behavior = "cleanup"
checksum_algorithm = "blake3"

[backends]
preferred_order = ["rsync", "rclone", "native"]

[ui]
confirm_before_start = true
show_hidden_files = false
date_format = "%Y-%m-%d %H:%M"

[logging]
keep_days = 365              # Logs nach 1 Jahr löschen
export_manifests = true      # Checksummen-Dateien erstellen
```

---

## 11. Python-Projektstruktur

```
datenassistent/
├── pyproject.toml
├── README.md
├── src/
│   └── datenassistent/
│       ├── __init__.py
│       ├── __main__.py          # Entry point
│       ├── app.py               # Textual App Hauptklasse
│       │
│       ├── ui/                  # TUI-Komponenten
│       │   ├── wizard/
│       │   │   ├── source.py    # Schritt 1: Quelle wählen
│       │   │   ├── target.py    # Schritt 2: Ziel wählen
│       │   │   ├── options.py   # Schritt 3: Optionen
│       │   │   └── preview.py   # Schritt 4: Dry-Run Vorschau
│       │   ├── dashboard.py     # Schritt 5: Ausführungs-Dashboard
│       │   └── widgets/         # Wiederverwendbare Komponenten
│       │
│       ├── core/                # Geschäftslogik
│       │   ├── job.py           # CopyJob Datenklasse
│       │   ├── orchestrator.py  # Koordiniert Backend + Verifikation
│       │   ├── verification.py  # Checksummen-Berechnung
│       │   └── metadata.py      # Plattform-Metadaten-Handling
│       │
│       ├── backends/            # Backend-Implementierungen
│       │   ├── base.py          # Protocol/Interface
│       │   ├── rsync.py
│       │   ├── rclone.py
│       │   ├── restic.py
│       │   ├── borg.py
│       │   ├── robocopy.py      # Windows
│       │   ├── ditto.py         # macOS
│       │   └── native.py        # Python-Fallback
│       │
│       ├── db/                  # Persistenz
│       │   ├── models.py        # SQLite-Schema
│       │   └── repository.py    # Abfragen
│       │
│       └── config/              # Konfiguration
│           ├── loader.py        # TOML laden, Merging
│           └── schema.py        # Pydantic-Modelle
│
└── tests/
    ├── unit/
    ├── integration/
    └── fixtures/
```

### Dependencies

```toml
[project]
dependencies = [
    "textual>=0.50",         # TUI Framework
    "blake3",                # Schnelle Checksummen
    "pydantic>=2.0",         # Config-Validierung
    "platformdirs",          # XDG-Pfade Cross-Platform
]

[project.optional-dependencies]
dev = ["pytest", "pytest-asyncio", "ruff", "mypy"]
```

---

## Nächste Schritte

1. **Workspace einrichten** - Git-Repository, pyproject.toml, Grundstruktur
2. **Backend Abstraction Layer** - Protocol definieren, native Backend implementieren
3. **Core Logic** - CopyJob, Orchestrator, Verification
4. **TUI Wizard** - Schritt für Schritt aufbauen
5. **Backend-Integrationen** - rsync, rclone, etc.
6. **Testing** - Unit + Integration Tests
