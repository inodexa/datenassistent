# Workflows: Datenassistent

> Standardisierte, sichere Abläufe für Migration, Verifikation und Analyse

---

## 1. End-to-End Migration (empfohlen)

**Ziel:** Forensisch verifizierte 1:1-Kopie in `_IMPORT_RAW/`.

```bash
# 1) Migration inkl. Manifest + Audit
bash scripts/migrate.sh /quelle /ziel/_IMPORT_RAW/disk01 disk01

# 2) Optional: separate Audit-Phase wiederholen
bash scripts/verify.sh /pfad/zum/manifest.sha256 /ziel/_IMPORT_RAW/disk01
```

**Ergebnis:** Vollständige Logs + Manifest + Audit-Report in `_MIGRATION_PROJECT/`.

---

## 2. Reine Verifikation (Audit-only)

**Ziel:** Vorhandenes Manifest gegen Ziel prüfen (z.B. nach erneuter Kopie).

```bash
bash scripts/verify.sh /pfad/zum/manifest.sha256 /ziel/_IMPORT_RAW/disk01
```

---

## 3. Deduplizierung (Analyse-only)

**Ziel:** Duplikate finden, ohne Dateien zu verändern.

```bash
fclones group /ziel/_IMPORT_RAW --min 1M -o duplicates.txt
fclones group /ziel/_IMPORT_RAW --min 1M -f json > duplicates.json
```

---

## 4. Metadaten-Export (vor Normalisierung)

```bash
exiftool -csv -r /ziel/_IMPORT_RAW > metadata.csv
exiftool -json -r /ziel/_IMPORT_RAW > metadata.json
```

---

## 5. Nacharbeit (manuell, bewusst)

**Nur nach erfolgreicher Verifikation:**
- Umstrukturieren
- Dateinamen normalisieren
- Duplikate entfernen (niemals automatisch)

