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

## 2.1 Preflight-Checks (vor jeder Migration)

```bash
# Quelle erreichbar?
[[ -d /quelle ]] && echo "Quelle OK"

# Ziel gemountet?
mountpoint -q /ziel && echo "Ziel gemountet"

# Tools vorhanden?
command -v hashdeep rsync >/dev/null && echo "Tools OK"
```

---

## 3. macOS/APFS-Quelle (typisch unter Linux)

**Ziel:** APFS-Volumes sind unter Linux oft mit UID-Mapping-Problemen gemountet.

```bash
# 1) APFS-Volume mounten (Beispiel)
sudo apfs-fuse -o uid=1000,gid=100 /dev/sdX /mnt/apfs

# 2) Migration mit Besitzanpassung (falls nötig)
sudo bash scripts/migrate.sh /mnt/apfs /mnt/nas/_IMPORT_RAW/disk01 disk01_mac
```

**Hinweis:** Wenn UID/GID nicht stimmt, ist `sudo` für den rsync-Teil erforderlich.

---

## 4. SMB-Performance (macOS)

**Ziel:** SMB-Transfers beschleunigen, ohne Integrität zu gefährden.

```ini
# /etc/nsmb.conf
[default]
signing_required=no
dir_cache_off=yes
```

**Ablauf:**
1. SMB-Share neu verbinden
2. `scripts/migrate.sh` laufen lassen (Audit bleibt obligatorisch)

---

## 5. Deduplizierung (Analyse-only)

**Ziel:** Duplikate finden, ohne Dateien zu verändern.

```bash
fclones group /ziel/_IMPORT_RAW --min 1M -o duplicates.txt
fclones group /ziel/_IMPORT_RAW --min 1M -f json > duplicates.json
```

---

## 6. Metadaten-Export (vor Normalisierung)

```bash
exiftool -csv -r /ziel/_IMPORT_RAW > metadata.csv
exiftool -json -r /ziel/_IMPORT_RAW > metadata.json
```

---

## 7. Nacharbeit (manuell, bewusst)

**Nur nach erfolgreicher Verifikation:**
- Umstrukturieren
- Dateinamen normalisieren
- Duplikate entfernen (niemals automatisch)

---

## 8. Fehlerbehandlung & Resume

**Grundprinzip:**
- Logs prüfen (rsync + hashdeep)
- Bei Abbruch: gleiches Kommando erneut starten

```bash
# Resume bei Abbruch
rsync -avhP --checksum /quelle/ /ziel/
```

**Hinweis:** `-P` sorgt für Resume-fähige Teiltransfers.

---

## 9. Logging & Artefakte

**Standardpfade:**
- `_MIGRATION_PROJECT/manifests/` → Quell-Manifest(e)
- `_MIGRATION_PROJECT/logs/` → rsync + Audit + Summary
- `_MIGRATION_PROJECT/metadata/` → xattrs/Metadaten-Exports

**Empfehlung:** Logs und Manifeste gemeinsam mit dem Ziel archivieren.

---

## 10. Sample-Check zwischen großen Läufen

```bash
# Schneller Zwischencheck (z.B. nach SMB-Wiederverbindung)
bash scripts/verify.sh --sample 2 /pfad/zum/manifest.sha256 /ziel/_IMPORT_RAW/disk01
```
