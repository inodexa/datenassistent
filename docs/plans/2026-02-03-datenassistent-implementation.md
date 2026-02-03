# Datenassistent Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a cross-platform TUI tool for integrity-preserving file copies with intelligent backend selection, multi-level verification, and detailed logging.

**Architecture:** Layered design with TUI (textual) on top, core orchestration in the middle, and a backend abstraction layer wrapping rsync, rclone, and a native Python fallback. SQLite for logging, Pydantic for config, BLAKE3/SHA256 for verification.

**Tech Stack:** Python 3.13, textual (TUI), pydantic (config), blake3 (checksums), platformdirs (XDG paths), SQLite (logging), TOML (config files). Package management via `uv` (available through `nix-shell -p uv`).

**Environment Notes:**
- NixOS system - use `nix-shell -p uv` for package management
- Python 3.13.11 available at `/run/current-system/sw/bin/python3`
- rsync available at `/run/current-system/sw/bin/rsync`
- rclone available at `/run/current-system/sw/bin/rclone`
- restic, borg not currently installed

---

### Task 1: Project Scaffolding

**Files:**
- Create: `pyproject.toml`
- Create: `src/datenassistent/__init__.py`
- Create: `src/datenassistent/__main__.py`
- Create: `tests/__init__.py`
- Create: `tests/unit/__init__.py`
- Create: `tests/integration/__init__.py`

**Step 1: Create pyproject.toml**

```toml
[project]
name = "datenassistent"
version = "0.1.0"
description = "Cross-platform TUI tool for integrity-preserving file copies"
requires-python = ">=3.12"
dependencies = [
    "textual>=0.50",
    "blake3>=1.0",
    "pydantic>=2.0",
    "platformdirs>=4.0",
]

[project.scripts]
datenassistent = "datenassistent.__main__:main"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/datenassistent"]

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=0.23",
    "ruff>=0.4",
    "mypy>=1.10",
]

[tool.pytest.ini_options]
testpaths = ["tests"]
asyncio_mode = "auto"

[tool.ruff]
target-version = "py312"
line-length = 99

[tool.mypy]
python_version = "3.12"
strict = true
```

**Step 2: Create package files**

`src/datenassistent/__init__.py`:
```python
"""Datenassistent - Integrity-preserving file copy tool."""

__version__ = "0.1.0"
```

`src/datenassistent/__main__.py`:
```python
"""Entry point for python -m datenassistent."""

from datenassistent.app import DatenassistentApp


def main() -> None:
    app = DatenassistentApp()
    app.run()


if __name__ == "__main__":
    main()
```

`tests/__init__.py`, `tests/unit/__init__.py`, `tests/integration/__init__.py`: empty files.

**Step 3: Initialize uv environment and install dependencies**

Run: `nix-shell -p uv --run "uv sync --dev"`
Expected: Virtual environment created, all dependencies installed.

**Step 4: Verify pytest works**

Run: `nix-shell -p uv --run "uv run pytest --co -q"`
Expected: "no tests ran" (no test files yet, but pytest itself works)

**Step 5: Commit**

```bash
git add pyproject.toml src/ tests/
git commit -m "feat: scaffold project with pyproject.toml and package structure"
```

---

### Task 2: Configuration Schema (Pydantic Models)

**Files:**
- Create: `src/datenassistent/config/schema.py`
- Create: `src/datenassistent/config/__init__.py`
- Test: `tests/unit/test_config_schema.py`

**Step 1: Write the failing tests**

`tests/unit/test_config_schema.py`:
```python
"""Tests for configuration schema."""

from datenassistent.config.schema import (
    AbortBehavior,
    AppConfig,
    BackendsConfig,
    ConflictStrategy,
    DefaultsConfig,
    LoggingConfig,
    MetadataMode,
    UiConfig,
    VerifyMode,
)


class TestEnums:
    def test_metadata_mode_values(self):
        assert MetadataMode.FULL == "full"
        assert MetadataMode.PORTABLE == "portable"
        assert MetadataMode.MINIMAL == "minimal"

    def test_verify_mode_values(self):
        assert VerifyMode.QUICK == "quick"
        assert VerifyMode.DEEP == "deep"

    def test_conflict_strategy_values(self):
        assert ConflictStrategy.NEWER == "newer"
        assert ConflictStrategy.LARGER == "larger"
        assert ConflictStrategy.OVERWRITE == "overwrite"
        assert ConflictStrategy.SKIP == "skip"

    def test_abort_behavior_values(self):
        assert AbortBehavior.CLEANUP == "cleanup"
        assert AbortBehavior.KEEP == "keep"
        assert AbortBehavior.KEEP_ALL == "keep_all"


class TestDefaultsConfig:
    def test_defaults_have_safe_values(self):
        defaults = DefaultsConfig()
        assert defaults.metadata_mode == MetadataMode.FULL
        assert defaults.verify_mode == VerifyMode.QUICK
        assert defaults.conflict_strategy == ConflictStrategy.SKIP
        assert defaults.abort_behavior == AbortBehavior.CLEANUP
        assert defaults.checksum_algorithm == "blake3"


class TestAppConfig:
    def test_default_config(self):
        config = AppConfig()
        assert config.defaults.metadata_mode == MetadataMode.FULL
        assert config.backends.preferred_order == ["rsync", "rclone", "native"]
        assert config.ui.confirm_before_start is True
        assert config.logging.keep_days == 365

    def test_config_from_dict(self):
        data = {
            "defaults": {"verify_mode": "deep"},
            "backends": {"preferred_order": ["rclone", "rsync"]},
        }
        config = AppConfig.model_validate(data)
        assert config.defaults.verify_mode == VerifyMode.DEEP
        assert config.backends.preferred_order == ["rclone", "rsync"]
        # Unchanged defaults preserved
        assert config.defaults.metadata_mode == MetadataMode.FULL
```

**Step 2: Run tests to verify they fail**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_config_schema.py -v"`
Expected: FAIL with ModuleNotFoundError

**Step 3: Write implementation**

`src/datenassistent/config/__init__.py`: empty file.

`src/datenassistent/config/schema.py`:
```python
"""Configuration schema using Pydantic models."""

from enum import StrEnum

from pydantic import BaseModel


class MetadataMode(StrEnum):
    FULL = "full"
    PORTABLE = "portable"
    MINIMAL = "minimal"


class VerifyMode(StrEnum):
    QUICK = "quick"
    DEEP = "deep"


class ConflictStrategy(StrEnum):
    NEWER = "newer"
    LARGER = "larger"
    OVERWRITE = "overwrite"
    SKIP = "skip"


class AbortBehavior(StrEnum):
    CLEANUP = "cleanup"
    KEEP = "keep"
    KEEP_ALL = "keep_all"


class DefaultsConfig(BaseModel):
    metadata_mode: MetadataMode = MetadataMode.FULL
    verify_mode: VerifyMode = VerifyMode.QUICK
    conflict_strategy: ConflictStrategy = ConflictStrategy.SKIP
    abort_behavior: AbortBehavior = AbortBehavior.CLEANUP
    checksum_algorithm: str = "blake3"


class BackendsConfig(BaseModel):
    preferred_order: list[str] = ["rsync", "rclone", "native"]


class UiConfig(BaseModel):
    confirm_before_start: bool = True
    show_hidden_files: bool = False
    date_format: str = "%Y-%m-%d %H:%M"


class LoggingConfig(BaseModel):
    keep_days: int = 365
    export_manifests: bool = True


class AppConfig(BaseModel):
    defaults: DefaultsConfig = DefaultsConfig()
    backends: BackendsConfig = BackendsConfig()
    ui: UiConfig = UiConfig()
    logging: LoggingConfig = LoggingConfig()
```

**Step 4: Run tests to verify they pass**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_config_schema.py -v"`
Expected: All PASSED

**Step 5: Commit**

```bash
git add src/datenassistent/config/ tests/unit/test_config_schema.py
git commit -m "feat: add configuration schema with Pydantic models"
```

---

### Task 3: Configuration Loader (TOML + Merging)

**Files:**
- Create: `src/datenassistent/config/loader.py`
- Test: `tests/unit/test_config_loader.py`

**Step 1: Write the failing tests**

`tests/unit/test_config_loader.py`:
```python
"""Tests for configuration loading and merging."""

from pathlib import Path

from datenassistent.config.loader import load_config, merge_configs
from datenassistent.config.schema import AppConfig, MetadataMode, VerifyMode


class TestMergeConfigs:
    def test_merge_empty_override(self):
        base = AppConfig()
        override = AppConfig()
        merged = merge_configs(base, override)
        assert merged.defaults.metadata_mode == MetadataMode.FULL

    def test_override_replaces_values(self):
        base = AppConfig()
        override = AppConfig.model_validate(
            {"defaults": {"verify_mode": "deep", "metadata_mode": "minimal"}}
        )
        merged = merge_configs(base, override)
        assert merged.defaults.verify_mode == VerifyMode.DEEP
        assert merged.defaults.metadata_mode == MetadataMode.MINIMAL
        # Non-overridden value preserved from base
        assert merged.defaults.checksum_algorithm == "blake3"


class TestLoadConfig:
    def test_load_from_nonexistent_returns_defaults(self, tmp_path: Path):
        config = load_config(
            global_dir=tmp_path / "nonexistent",
            project_dir=None,
        )
        assert config == AppConfig()

    def test_load_from_toml_file(self, tmp_path: Path):
        config_dir = tmp_path / "config"
        config_dir.mkdir()
        config_file = config_dir / "config.toml"
        config_file.write_text(
            '[defaults]\nverify_mode = "deep"\n\n[ui]\nshow_hidden_files = true\n'
        )
        config = load_config(global_dir=config_dir, project_dir=None)
        assert config.defaults.verify_mode == VerifyMode.DEEP
        assert config.ui.show_hidden_files is True
        # Defaults preserved
        assert config.defaults.metadata_mode == MetadataMode.FULL

    def test_project_config_overrides_global(self, tmp_path: Path):
        global_dir = tmp_path / "global"
        global_dir.mkdir()
        (global_dir / "config.toml").write_text('[defaults]\nverify_mode = "deep"\n')

        project_dir = tmp_path / "project" / ".datenassistent"
        project_dir.mkdir(parents=True)
        (project_dir / "config.toml").write_text('[defaults]\nmetadata_mode = "minimal"\n')

        config = load_config(global_dir=global_dir, project_dir=project_dir)
        assert config.defaults.verify_mode == VerifyMode.DEEP  # from global
        assert config.defaults.metadata_mode == MetadataMode.MINIMAL  # from project
```

**Step 2: Run tests to verify they fail**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_config_loader.py -v"`
Expected: FAIL with ImportError

**Step 3: Write implementation**

`src/datenassistent/config/loader.py`:
```python
"""Load and merge TOML configuration files."""

import tomllib
from pathlib import Path

from datenassistent.config.schema import AppConfig


def merge_configs(base: AppConfig, override: AppConfig) -> AppConfig:
    """Deep-merge override into base. Override values take precedence."""
    base_dict = base.model_dump()
    override_dict = override.model_dump()
    merged = _deep_merge(base_dict, override_dict)
    return AppConfig.model_validate(merged)


def _deep_merge(base: dict, override: dict) -> dict:
    """Recursively merge override into base dict."""
    result = base.copy()
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def load_config(
    global_dir: Path,
    project_dir: Path | None,
) -> AppConfig:
    """Load config from global dir, optionally merge with project-level overrides."""
    config = AppConfig()

    global_file = global_dir / "config.toml"
    if global_file.is_file():
        global_data = _load_toml(global_file)
        global_config = AppConfig.model_validate(global_data)
        config = merge_configs(config, global_config)

    if project_dir is not None:
        project_file = project_dir / "config.toml"
        if project_file.is_file():
            project_data = _load_toml(project_file)
            project_config = AppConfig.model_validate(project_data)
            config = merge_configs(config, project_config)

    return config


def _load_toml(path: Path) -> dict:
    """Read and parse a TOML file."""
    with open(path, "rb") as f:
        return tomllib.load(f)
```

**Step 4: Run tests to verify they pass**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_config_loader.py -v"`
Expected: All PASSED

**Step 5: Commit**

```bash
git add src/datenassistent/config/loader.py tests/unit/test_config_loader.py
git commit -m "feat: add TOML config loader with global/project merging"
```

---

### Task 4: CopyJob Data Model

**Files:**
- Create: `src/datenassistent/core/__init__.py`
- Create: `src/datenassistent/core/job.py`
- Test: `tests/unit/test_job.py`

**Step 1: Write the failing tests**

`tests/unit/test_job.py`:
```python
"""Tests for CopyJob data model."""

from pathlib import Path

from datenassistent.config.schema import (
    AbortBehavior,
    ConflictStrategy,
    MetadataMode,
    VerifyMode,
)
from datenassistent.core.job import CopyJob, FileEntry, JobStatus


class TestFileEntry:
    def test_create_file_entry(self, tmp_path: Path):
        entry = FileEntry(
            source=tmp_path / "a.txt",
            target=tmp_path / "backup" / "a.txt",
            size_bytes=1024,
        )
        assert entry.source == tmp_path / "a.txt"
        assert entry.size_bytes == 1024
        assert entry.checksum is None

    def test_file_entry_with_checksum(self, tmp_path: Path):
        entry = FileEntry(
            source=tmp_path / "a.txt",
            target=tmp_path / "backup" / "a.txt",
            size_bytes=512,
            checksum="blake3:abc123",
        )
        assert entry.checksum == "blake3:abc123"


class TestCopyJob:
    def test_create_minimal_job(self, tmp_path: Path):
        job = CopyJob(
            source=tmp_path / "src",
            target=tmp_path / "dst",
        )
        assert job.source == tmp_path / "src"
        assert job.target == tmp_path / "dst"
        assert job.metadata_mode == MetadataMode.FULL
        assert job.verify_mode == VerifyMode.QUICK
        assert job.conflict_strategy == ConflictStrategy.SKIP
        assert job.abort_behavior == AbortBehavior.CLEANUP
        assert job.status == JobStatus.PENDING
        assert job.files == []

    def test_job_total_bytes(self, tmp_path: Path):
        job = CopyJob(
            source=tmp_path / "src",
            target=tmp_path / "dst",
            files=[
                FileEntry(
                    source=tmp_path / "a", target=tmp_path / "b", size_bytes=100
                ),
                FileEntry(
                    source=tmp_path / "c", target=tmp_path / "d", size_bytes=200
                ),
            ],
        )
        assert job.total_bytes == 300
        assert job.total_files == 2
```

**Step 2: Run tests to verify they fail**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_job.py -v"`
Expected: FAIL with ModuleNotFoundError

**Step 3: Write implementation**

`src/datenassistent/core/__init__.py`: empty file.

`src/datenassistent/core/job.py`:
```python
"""CopyJob and related data models."""

from enum import StrEnum
from pathlib import Path

from pydantic import BaseModel, computed_field

from datenassistent.config.schema import (
    AbortBehavior,
    ConflictStrategy,
    MetadataMode,
    VerifyMode,
)


class JobStatus(StrEnum):
    PENDING = "pending"
    RUNNING = "running"
    SUCCESS = "success"
    FAILED = "failed"
    ABORTED = "aborted"


class FileEntry(BaseModel):
    """A single file to be copied."""

    source: Path
    target: Path
    size_bytes: int
    checksum: str | None = None


class CopyJob(BaseModel):
    """Represents a complete copy operation."""

    source: Path
    target: Path
    metadata_mode: MetadataMode = MetadataMode.FULL
    verify_mode: VerifyMode = VerifyMode.QUICK
    conflict_strategy: ConflictStrategy = ConflictStrategy.SKIP
    abort_behavior: AbortBehavior = AbortBehavior.CLEANUP
    backend: str | None = None  # None = auto-select
    status: JobStatus = JobStatus.PENDING
    files: list[FileEntry] = []

    @computed_field  # type: ignore[prop-decorator]
    @property
    def total_bytes(self) -> int:
        return sum(f.size_bytes for f in self.files)

    @computed_field  # type: ignore[prop-decorator]
    @property
    def total_files(self) -> int:
        return len(self.files)
```

**Step 4: Run tests to verify they pass**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_job.py -v"`
Expected: All PASSED

**Step 5: Commit**

```bash
git add src/datenassistent/core/ tests/unit/test_job.py
git commit -m "feat: add CopyJob and FileEntry data models"
```

---

### Task 5: Database Layer (SQLite Schema + Repository)

**Files:**
- Create: `src/datenassistent/db/__init__.py`
- Create: `src/datenassistent/db/models.py`
- Create: `src/datenassistent/db/repository.py`
- Test: `tests/unit/test_db.py`

**Step 1: Write the failing tests**

`tests/unit/test_db.py`:
```python
"""Tests for SQLite database layer."""

from datetime import datetime, timezone
from pathlib import Path

from datenassistent.db.repository import JobRecord, JobRepository


class TestJobRepository:
    def test_create_and_get_job(self, tmp_path: Path):
        repo = JobRepository(tmp_path / "test.db")
        job_id = repo.create_job(
            source_path="/home/user/src",
            target_path="/backup/dst",
            backend_used="rsync",
            metadata_mode="full",
            verify_mode="quick",
            abort_behavior="cleanup",
        )
        assert job_id == 1

        job = repo.get_job(job_id)
        assert job is not None
        assert job.source_path == "/home/user/src"
        assert job.target_path == "/backup/dst"
        assert job.backend_used == "rsync"
        assert job.status == "running"

    def test_complete_job(self, tmp_path: Path):
        repo = JobRepository(tmp_path / "test.db")
        job_id = repo.create_job(
            source_path="/src",
            target_path="/dst",
            backend_used="native",
            metadata_mode="full",
            verify_mode="quick",
            abort_behavior="cleanup",
        )
        repo.complete_job(job_id, status="success", total_files=10, total_bytes=2048)

        job = repo.get_job(job_id)
        assert job is not None
        assert job.status == "success"
        assert job.total_files == 10
        assert job.total_bytes == 2048
        assert job.finished_at is not None

    def test_add_file_record(self, tmp_path: Path):
        repo = JobRepository(tmp_path / "test.db")
        job_id = repo.create_job(
            source_path="/src",
            target_path="/dst",
            backend_used="native",
            metadata_mode="full",
            verify_mode="quick",
            abort_behavior="cleanup",
        )
        repo.add_file_record(
            job_id=job_id,
            source_path="/src/a.txt",
            target_path="/dst/a.txt",
            size_bytes=512,
            checksum_algo="blake3",
            checksum_value="abc123",
            status="copied",
        )
        files = repo.get_files_for_job(job_id)
        assert len(files) == 1
        assert files[0]["source_path"] == "/src/a.txt"
        assert files[0]["checksum_value"] == "abc123"

    def test_list_recent_jobs(self, tmp_path: Path):
        repo = JobRepository(tmp_path / "test.db")
        for i in range(3):
            repo.create_job(
                source_path=f"/src{i}",
                target_path=f"/dst{i}",
                backend_used="native",
                metadata_mode="full",
                verify_mode="quick",
                abort_behavior="cleanup",
            )
        jobs = repo.list_jobs(limit=2)
        assert len(jobs) == 2

    def test_get_nonexistent_job(self, tmp_path: Path):
        repo = JobRepository(tmp_path / "test.db")
        job = repo.get_job(999)
        assert job is None
```

**Step 2: Run tests to verify they fail**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_db.py -v"`
Expected: FAIL with ModuleNotFoundError

**Step 3: Write implementation**

`src/datenassistent/db/__init__.py`: empty file.

`src/datenassistent/db/models.py`:
```python
"""SQLite schema definition and migration."""

SCHEMA_VERSION = 1

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS jobs (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at      TEXT NOT NULL,
    finished_at     TEXT,
    source_path     TEXT NOT NULL,
    target_path     TEXT NOT NULL,
    backend_used    TEXT NOT NULL,
    metadata_mode   TEXT NOT NULL,
    verify_mode     TEXT NOT NULL,
    abort_behavior  TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'running',
    total_files     INTEGER,
    total_bytes     INTEGER,
    error_message   TEXT
);

CREATE TABLE IF NOT EXISTS files (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          INTEGER NOT NULL REFERENCES jobs(id),
    source_path     TEXT NOT NULL,
    target_path     TEXT NOT NULL,
    size_bytes      INTEGER NOT NULL,
    checksum_algo   TEXT,
    checksum_value  TEXT,
    status          TEXT NOT NULL,
    metadata_json   TEXT
);

CREATE TABLE IF NOT EXISTS conflicts (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          INTEGER NOT NULL REFERENCES jobs(id),
    file_path       TEXT NOT NULL,
    conflict_type   TEXT NOT NULL,
    resolution      TEXT NOT NULL,
    source_checksum TEXT,
    target_checksum TEXT
);
"""
```

`src/datenassistent/db/repository.py`:
```python
"""SQLite repository for job and file logging."""

import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from datenassistent.db.models import SCHEMA_SQL, SCHEMA_VERSION


@dataclass
class JobRecord:
    id: int
    started_at: str
    finished_at: str | None
    source_path: str
    target_path: str
    backend_used: str
    metadata_mode: str
    verify_mode: str
    abort_behavior: str
    status: str
    total_files: int | None
    total_bytes: int | None
    error_message: str | None


class JobRepository:
    """Manages SQLite database for copy job logging."""

    def __init__(self, db_path: Path) -> None:
        self._db_path = db_path
        db_path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(db_path))
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA foreign_keys=ON")
        self._init_schema()

    def _init_schema(self) -> None:
        self._conn.executescript(SCHEMA_SQL)
        self._conn.execute(
            "INSERT OR IGNORE INTO schema_version (version) VALUES (?)",
            (SCHEMA_VERSION,),
        )
        self._conn.commit()

    def create_job(
        self,
        source_path: str,
        target_path: str,
        backend_used: str,
        metadata_mode: str,
        verify_mode: str,
        abort_behavior: str,
    ) -> int:
        now = datetime.now(timezone.utc).isoformat()
        cursor = self._conn.execute(
            """INSERT INTO jobs
            (started_at, source_path, target_path, backend_used,
             metadata_mode, verify_mode, abort_behavior, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, 'running')""",
            (now, source_path, target_path, backend_used,
             metadata_mode, verify_mode, abort_behavior),
        )
        self._conn.commit()
        return cursor.lastrowid  # type: ignore[return-value]

    def complete_job(
        self,
        job_id: int,
        status: str,
        total_files: int | None = None,
        total_bytes: int | None = None,
        error_message: str | None = None,
    ) -> None:
        now = datetime.now(timezone.utc).isoformat()
        self._conn.execute(
            """UPDATE jobs SET finished_at=?, status=?, total_files=?,
            total_bytes=?, error_message=? WHERE id=?""",
            (now, status, total_files, total_bytes, error_message, job_id),
        )
        self._conn.commit()

    def get_job(self, job_id: int) -> JobRecord | None:
        row = self._conn.execute(
            "SELECT * FROM jobs WHERE id=?", (job_id,)
        ).fetchone()
        if row is None:
            return None
        return JobRecord(**dict(row))

    def list_jobs(self, limit: int = 20) -> list[JobRecord]:
        rows = self._conn.execute(
            "SELECT * FROM jobs ORDER BY started_at DESC LIMIT ?", (limit,)
        ).fetchall()
        return [JobRecord(**dict(r)) for r in rows]

    def add_file_record(
        self,
        job_id: int,
        source_path: str,
        target_path: str,
        size_bytes: int,
        status: str,
        checksum_algo: str | None = None,
        checksum_value: str | None = None,
        metadata_json: str | None = None,
    ) -> int:
        cursor = self._conn.execute(
            """INSERT INTO files
            (job_id, source_path, target_path, size_bytes,
             checksum_algo, checksum_value, status, metadata_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (job_id, source_path, target_path, size_bytes,
             checksum_algo, checksum_value, status, metadata_json),
        )
        self._conn.commit()
        return cursor.lastrowid  # type: ignore[return-value]

    def get_files_for_job(self, job_id: int) -> list[dict]:
        rows = self._conn.execute(
            "SELECT * FROM files WHERE job_id=? ORDER BY id", (job_id,)
        ).fetchall()
        return [dict(r) for r in rows]

    def close(self) -> None:
        self._conn.close()
```

**Step 4: Run tests to verify they pass**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_db.py -v"`
Expected: All PASSED

**Step 5: Commit**

```bash
git add src/datenassistent/db/ tests/unit/test_db.py
git commit -m "feat: add SQLite database layer for job and file logging"
```

---

### Task 6: Verification Module (BLAKE3 + SHA256 Checksums)

**Files:**
- Create: `src/datenassistent/core/verification.py`
- Test: `tests/unit/test_verification.py`

**Step 1: Write the failing tests**

`tests/unit/test_verification.py`:
```python
"""Tests for file verification and checksum computation."""

from pathlib import Path

from datenassistent.core.verification import (
    compute_checksum,
    quick_verify,
    deep_verify,
)


class TestComputeChecksum:
    def test_blake3_checksum(self, tmp_path: Path):
        f = tmp_path / "test.txt"
        f.write_text("hello world")
        result = compute_checksum(f, algorithm="blake3")
        assert result.startswith("blake3:")
        assert len(result) > 10

    def test_sha256_checksum(self, tmp_path: Path):
        f = tmp_path / "test.txt"
        f.write_text("hello world")
        result = compute_checksum(f, algorithm="sha256")
        assert result.startswith("sha256:")
        assert len(result) > 10

    def test_same_content_same_checksum(self, tmp_path: Path):
        f1 = tmp_path / "a.txt"
        f2 = tmp_path / "b.txt"
        f1.write_text("identical")
        f2.write_text("identical")
        assert compute_checksum(f1, "blake3") == compute_checksum(f2, "blake3")

    def test_different_content_different_checksum(self, tmp_path: Path):
        f1 = tmp_path / "a.txt"
        f2 = tmp_path / "b.txt"
        f1.write_text("content A")
        f2.write_text("content B")
        assert compute_checksum(f1, "blake3") != compute_checksum(f2, "blake3")


class TestQuickVerify:
    def test_identical_files_pass(self, tmp_path: Path):
        src = tmp_path / "src.txt"
        dst = tmp_path / "dst.txt"
        src.write_text("same")
        dst.write_text("same")
        assert quick_verify(src, dst) is True

    def test_different_size_fails(self, tmp_path: Path):
        src = tmp_path / "src.txt"
        dst = tmp_path / "dst.txt"
        src.write_text("short")
        dst.write_text("much longer content")
        assert quick_verify(src, dst) is False

    def test_missing_target_fails(self, tmp_path: Path):
        src = tmp_path / "src.txt"
        src.write_text("exists")
        assert quick_verify(src, tmp_path / "missing.txt") is False


class TestDeepVerify:
    def test_identical_files_pass(self, tmp_path: Path):
        src = tmp_path / "src.txt"
        dst = tmp_path / "dst.txt"
        src.write_text("same content")
        dst.write_text("same content")
        match, src_cs, dst_cs = deep_verify(src, dst, algorithm="blake3")
        assert match is True
        assert src_cs == dst_cs

    def test_different_files_fail(self, tmp_path: Path):
        src = tmp_path / "src.txt"
        dst = tmp_path / "dst.txt"
        src.write_text("original")
        dst.write_text("corrupted")
        match, src_cs, dst_cs = deep_verify(src, dst, algorithm="blake3")
        assert match is False
        assert src_cs != dst_cs
```

**Step 2: Run tests to verify they fail**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_verification.py -v"`
Expected: FAIL with ImportError

**Step 3: Write implementation**

`src/datenassistent/core/verification.py`:
```python
"""File verification using checksums."""

import hashlib
from pathlib import Path

import blake3

CHUNK_SIZE = 1024 * 1024  # 1 MB


def compute_checksum(path: Path, algorithm: str = "blake3") -> str:
    """Compute checksum for a file. Returns 'algorithm:hexdigest'."""
    if algorithm == "blake3":
        hasher = blake3.blake3()
    elif algorithm == "sha256":
        hasher = hashlib.sha256()
    else:
        raise ValueError(f"Unsupported algorithm: {algorithm}")

    with open(path, "rb") as f:
        while chunk := f.read(CHUNK_SIZE):
            hasher.update(chunk)

    return f"{algorithm}:{hasher.hexdigest()}"


def quick_verify(source: Path, target: Path) -> bool:
    """Quick verification: compare file size (and existence)."""
    if not target.exists():
        return False
    if not source.exists():
        return False
    return source.stat().st_size == target.stat().st_size


def deep_verify(
    source: Path, target: Path, algorithm: str = "blake3"
) -> tuple[bool, str, str]:
    """Deep verification: compare checksums. Returns (match, source_cs, target_cs)."""
    src_checksum = compute_checksum(source, algorithm)
    dst_checksum = compute_checksum(target, algorithm)
    return (src_checksum == dst_checksum, src_checksum, dst_checksum)
```

**Step 4: Run tests to verify they pass**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_verification.py -v"`
Expected: All PASSED

**Step 5: Commit**

```bash
git add src/datenassistent/core/verification.py tests/unit/test_verification.py
git commit -m "feat: add BLAKE3 and SHA256 checksum verification"
```

---

### Task 7: Backend Protocol + Native Python Backend

**Files:**
- Create: `src/datenassistent/backends/__init__.py`
- Create: `src/datenassistent/backends/base.py`
- Create: `src/datenassistent/backends/native.py`
- Test: `tests/unit/test_backend_native.py`

**Step 1: Write the failing tests**

`tests/unit/test_backend_native.py`:
```python
"""Tests for native Python copy backend."""

import os
from pathlib import Path

from datenassistent.backends.native import NativeBackend
from datenassistent.config.schema import AbortBehavior, MetadataMode, VerifyMode
from datenassistent.core.job import CopyJob


def _make_source_tree(base: Path) -> Path:
    """Create a small directory tree for testing."""
    src = base / "source"
    src.mkdir()
    (src / "file1.txt").write_text("hello")
    (src / "file2.txt").write_text("world")
    sub = src / "subdir"
    sub.mkdir()
    (sub / "file3.txt").write_text("nested")
    return src


class TestNativeBackend:
    def test_supports_local_paths(self, tmp_path: Path):
        backend = NativeBackend()
        assert backend.supports(tmp_path / "src", tmp_path / "dst") is True

    def test_supports_rejects_remote(self, tmp_path: Path):
        backend = NativeBackend()
        # Paths with ssh:// or s3:// prefix are not supported
        assert backend.supports(Path("ssh://server/path"), tmp_path) is False
        assert backend.supports(tmp_path, Path("s3://bucket/key")) is False

    def test_dry_run_lists_files(self, tmp_path: Path):
        src = _make_source_tree(tmp_path)
        dst = tmp_path / "target"
        backend = NativeBackend()
        job = CopyJob(source=src, target=dst)
        preview = backend.dry_run(job)
        assert preview.total_files == 3
        assert preview.total_bytes > 0
        assert len(preview.files) == 3

    def test_execute_copies_files(self, tmp_path: Path):
        src = _make_source_tree(tmp_path)
        dst = tmp_path / "target"
        backend = NativeBackend()
        job = CopyJob(source=src, target=dst)

        progress_events: list[dict] = []
        result = backend.execute(job, progress_callback=progress_events.append)

        assert result.status == "success"
        assert result.files_copied == 3
        assert (dst / "file1.txt").read_text() == "hello"
        assert (dst / "subdir" / "file3.txt").read_text() == "nested"
        assert len(progress_events) == 3

    def test_execute_preserves_timestamps(self, tmp_path: Path):
        src = _make_source_tree(tmp_path)
        dst = tmp_path / "target"
        backend = NativeBackend()
        job = CopyJob(source=src, target=dst, metadata_mode=MetadataMode.FULL)
        backend.execute(job, progress_callback=lambda e: None)

        src_stat = (src / "file1.txt").stat()
        dst_stat = (dst / "file1.txt").stat()
        assert abs(src_stat.st_mtime - dst_stat.st_mtime) < 0.01

    def test_execute_aborts_on_error(self, tmp_path: Path):
        src = _make_source_tree(tmp_path)
        dst = tmp_path / "target"
        dst.mkdir()
        # Make target dir read-only to cause write failure
        ro_subdir = dst / "subdir"
        ro_subdir.mkdir()
        os.chmod(ro_subdir, 0o444)

        backend = NativeBackend()
        job = CopyJob(
            source=src,
            target=dst,
            abort_behavior=AbortBehavior.CLEANUP,
        )
        result = backend.execute(job, progress_callback=lambda e: None)
        assert result.status == "failed"
        assert result.error is not None

        # Cleanup after test
        os.chmod(ro_subdir, 0o755)
```

**Step 2: Run tests to verify they fail**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_backend_native.py -v"`
Expected: FAIL with ImportError

**Step 3: Write implementation**

`src/datenassistent/backends/__init__.py`: empty file.

`src/datenassistent/backends/base.py`:
```python
"""Backend protocol and result types."""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Protocol

from datenassistent.core.job import CopyJob


@dataclass
class PreviewFile:
    source: Path
    target: Path
    size_bytes: int
    action: str = "copy"  # "copy", "skip", "conflict"


@dataclass
class PreviewResult:
    files: list[PreviewFile] = field(default_factory=list)
    total_files: int = 0
    total_bytes: int = 0


@dataclass
class CopyResult:
    status: str  # "success", "failed", "aborted"
    files_copied: int = 0
    bytes_copied: int = 0
    error: str | None = None


class CopyBackend(Protocol):
    """Interface that every copy backend must implement."""

    def supports(self, source: Path, target: Path) -> bool: ...
    def dry_run(self, job: CopyJob) -> PreviewResult: ...
    def execute(
        self, job: CopyJob, progress_callback: Callable[[dict[str, Any]], None]
    ) -> CopyResult: ...
    def cancel(self) -> None: ...
```

`src/datenassistent/backends/native.py`:
```python
"""Native Python copy backend (cross-platform fallback)."""

import shutil
from pathlib import Path
from typing import Any, Callable

from datenassistent.backends.base import (
    CopyResult,
    PreviewFile,
    PreviewResult,
)
from datenassistent.config.schema import MetadataMode
from datenassistent.core.job import CopyJob

_REMOTE_PREFIXES = ("ssh://", "s3://", "gs://", "az://", "ftp://", "sftp://")


class NativeBackend:
    """Pure Python file copy backend. Works everywhere, no dependencies."""

    def __init__(self) -> None:
        self._cancelled = False

    def supports(self, source: Path, target: Path) -> bool:
        src_str = str(source)
        dst_str = str(target)
        return not any(
            s.startswith(p) for s in (src_str, dst_str) for p in _REMOTE_PREFIXES
        )

    def dry_run(self, job: CopyJob) -> PreviewResult:
        files: list[PreviewFile] = []
        total_bytes = 0

        for src_file in _walk_files(job.source):
            rel = src_file.relative_to(job.source)
            dst_file = job.target / rel
            size = src_file.stat().st_size
            files.append(PreviewFile(source=src_file, target=dst_file, size_bytes=size))
            total_bytes += size

        return PreviewResult(
            files=files, total_files=len(files), total_bytes=total_bytes
        )

    def execute(
        self, job: CopyJob, progress_callback: Callable[[dict[str, Any]], None]
    ) -> CopyResult:
        self._cancelled = False
        files_copied = 0
        bytes_copied = 0

        preview = self.dry_run(job)

        for pf in preview.files:
            if self._cancelled:
                return CopyResult(
                    status="aborted",
                    files_copied=files_copied,
                    bytes_copied=bytes_copied,
                )

            try:
                pf.target.parent.mkdir(parents=True, exist_ok=True)

                if job.metadata_mode == MetadataMode.MINIMAL:
                    shutil.copy(pf.source, pf.target)
                else:
                    shutil.copy2(pf.source, pf.target)

                files_copied += 1
                bytes_copied += pf.size_bytes
                progress_callback(
                    {
                        "event": "file_copied",
                        "source": str(pf.source),
                        "target": str(pf.target),
                        "size": pf.size_bytes,
                        "files_copied": files_copied,
                        "bytes_copied": bytes_copied,
                    }
                )
            except OSError as e:
                return CopyResult(
                    status="failed",
                    files_copied=files_copied,
                    bytes_copied=bytes_copied,
                    error=f"Failed to copy {pf.source}: {e}",
                )

        return CopyResult(
            status="success",
            files_copied=files_copied,
            bytes_copied=bytes_copied,
        )

    def cancel(self) -> None:
        self._cancelled = True


def _walk_files(directory: Path) -> list[Path]:
    """Recursively list all files in directory, sorted for deterministic order."""
    files = sorted(f for f in directory.rglob("*") if f.is_file())
    return files
```

**Step 4: Run tests to verify they pass**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_backend_native.py -v"`
Expected: All PASSED

**Step 5: Commit**

```bash
git add src/datenassistent/backends/ tests/unit/test_backend_native.py
git commit -m "feat: add backend protocol and native Python copy backend"
```

---

### Task 8: Rsync Backend

**Files:**
- Create: `src/datenassistent/backends/rsync.py`
- Test: `tests/integration/test_backend_rsync.py`

**Step 1: Write the failing tests**

`tests/integration/test_backend_rsync.py`:
```python
"""Integration tests for rsync backend."""

import shutil
from pathlib import Path

import pytest

from datenassistent.backends.rsync import RsyncBackend
from datenassistent.config.schema import MetadataMode
from datenassistent.core.job import CopyJob


def _make_source_tree(base: Path) -> Path:
    src = base / "source"
    src.mkdir()
    (src / "file1.txt").write_text("hello")
    (src / "file2.txt").write_text("world")
    sub = src / "subdir"
    sub.mkdir()
    (sub / "file3.txt").write_text("nested")
    return src


@pytest.fixture
def rsync_available() -> bool:
    return shutil.which("rsync") is not None


class TestRsyncBackend:
    def test_supports_local_paths(self, tmp_path: Path):
        backend = RsyncBackend()
        assert backend.supports(tmp_path / "src", tmp_path / "dst") is True

    def test_supports_ssh_paths(self, tmp_path: Path):
        backend = RsyncBackend()
        assert backend.supports(Path("user@host:/path"), tmp_path) is True

    def test_supports_rejects_s3(self, tmp_path: Path):
        backend = RsyncBackend()
        assert backend.supports(Path("s3://bucket/key"), tmp_path) is False

    @pytest.mark.skipif(
        not shutil.which("rsync"), reason="rsync not installed"
    )
    def test_dry_run(self, tmp_path: Path):
        src = _make_source_tree(tmp_path)
        dst = tmp_path / "target"
        backend = RsyncBackend()
        job = CopyJob(source=src, target=dst)
        preview = backend.dry_run(job)
        assert preview.total_files >= 3

    @pytest.mark.skipif(
        not shutil.which("rsync"), reason="rsync not installed"
    )
    def test_execute_copies_files(self, tmp_path: Path):
        src = _make_source_tree(tmp_path)
        dst = tmp_path / "target"
        backend = RsyncBackend()
        job = CopyJob(source=src, target=dst)

        progress_events: list[dict] = []
        result = backend.execute(job, progress_callback=progress_events.append)

        assert result.status == "success"
        assert (dst / "file1.txt").read_text() == "hello"
        assert (dst / "subdir" / "file3.txt").read_text() == "nested"
```

**Step 2: Run tests to verify they fail**

Run: `nix-shell -p uv --run "uv run pytest tests/integration/test_backend_rsync.py -v"`
Expected: FAIL with ImportError

**Step 3: Write implementation**

`src/datenassistent/backends/rsync.py`:
```python
"""Rsync copy backend."""

import re
import shutil
import subprocess
from pathlib import Path
from typing import Any, Callable

from datenassistent.backends.base import (
    CopyResult,
    PreviewFile,
    PreviewResult,
)
from datenassistent.config.schema import MetadataMode
from datenassistent.core.job import CopyJob

_CLOUD_PREFIXES = ("s3://", "gs://", "az://")


class RsyncBackend:
    """Backend using rsync for local and SSH copies."""

    def __init__(self) -> None:
        self._process: subprocess.Popen | None = None  # type: ignore[type-arg]

    @staticmethod
    def is_available() -> bool:
        return shutil.which("rsync") is not None

    def supports(self, source: Path, target: Path) -> bool:
        src_str = str(source)
        dst_str = str(target)
        # rsync does NOT support cloud storage directly
        return not any(
            s.startswith(p) for s in (src_str, dst_str) for p in _CLOUD_PREFIXES
        )

    def _build_args(self, job: CopyJob, dry_run: bool = False) -> list[str]:
        args = ["rsync", "-r", "--info=progress2", "--info=name1"]

        if job.metadata_mode == MetadataMode.FULL:
            args.append("-a")  # archive mode: permissions, timestamps, etc.
        elif job.metadata_mode == MetadataMode.PORTABLE:
            args.extend(["-r", "-t"])  # recursive + timestamps
        else:
            args.append("-r")  # recursive only

        if dry_run:
            args.append("--dry-run")
            args.append("--itemize-changes")

        # Ensure source path ends with / to copy contents
        src = str(job.source).rstrip("/") + "/"
        dst = str(job.target).rstrip("/") + "/"

        args.extend([src, dst])
        return args

    def dry_run(self, job: CopyJob) -> PreviewResult:
        args = self._build_args(job, dry_run=True)
        result = subprocess.run(args, capture_output=True, text=True, check=False)

        files: list[PreviewFile] = []
        for line in result.stdout.splitlines():
            # itemize-changes format: >f+++++++++ path/to/file
            match = re.match(r"^[><ch.][fdLDS][+.cstpogaxn]+ (.+)$", line)
            if match and not match.group(1).endswith("/"):
                rel_path = match.group(1)
                src_file = job.source / rel_path
                dst_file = job.target / rel_path
                size = src_file.stat().st_size if src_file.exists() else 0
                files.append(
                    PreviewFile(source=src_file, target=dst_file, size_bytes=size)
                )

        total_bytes = sum(f.size_bytes for f in files)
        return PreviewResult(
            files=files, total_files=len(files), total_bytes=total_bytes
        )

    def execute(
        self, job: CopyJob, progress_callback: Callable[[dict[str, Any]], None]
    ) -> CopyResult:
        job.target.mkdir(parents=True, exist_ok=True)
        args = self._build_args(job, dry_run=False)

        try:
            self._process = subprocess.Popen(
                args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
            )
            files_copied = 0
            for line in self._process.stdout or []:
                line = line.strip()
                if not line:
                    continue
                # Track file names (not progress lines)
                if not line.startswith(" ") and not line.endswith("/"):
                    files_copied += 1
                    progress_callback(
                        {
                            "event": "file_copied",
                            "file": line,
                            "files_copied": files_copied,
                        }
                    )

            self._process.wait()
            if self._process.returncode != 0:
                stderr = (self._process.stderr or type(self._process.stdout)()).read()
                return CopyResult(
                    status="failed",
                    files_copied=files_copied,
                    error=f"rsync exited with code {self._process.returncode}: {stderr}",
                )

            return CopyResult(status="success", files_copied=files_copied)

        except OSError as e:
            return CopyResult(status="failed", error=str(e))
        finally:
            self._process = None

    def cancel(self) -> None:
        if self._process is not None:
            self._process.terminate()
```

**Step 4: Run tests to verify they pass**

Run: `nix-shell -p uv --run "uv run pytest tests/integration/test_backend_rsync.py -v"`
Expected: All PASSED (rsync is available on this system)

**Step 5: Commit**

```bash
git add src/datenassistent/backends/rsync.py tests/integration/test_backend_rsync.py
git commit -m "feat: add rsync copy backend"
```

---

### Task 9: Backend Registry + Auto-Selection

**Files:**
- Create: `src/datenassistent/backends/registry.py`
- Test: `tests/unit/test_backend_registry.py`

**Step 1: Write the failing tests**

`tests/unit/test_backend_registry.py`:
```python
"""Tests for backend registry and auto-selection."""

from pathlib import Path

from datenassistent.backends.registry import BackendRegistry
from datenassistent.backends.native import NativeBackend


class TestBackendRegistry:
    def test_register_and_get(self):
        registry = BackendRegistry()
        registry.register("native", NativeBackend)
        backend = registry.get("native")
        assert isinstance(backend, NativeBackend)

    def test_get_unknown_returns_none(self):
        registry = BackendRegistry()
        assert registry.get("unknown") is None

    def test_auto_select_local(self, tmp_path: Path):
        registry = BackendRegistry()
        registry.register("native", NativeBackend)
        name, backend = registry.auto_select(
            source=tmp_path / "src",
            target=tmp_path / "dst",
            preferred_order=["native"],
        )
        assert name == "native"
        assert isinstance(backend, NativeBackend)

    def test_auto_select_respects_order(self, tmp_path: Path):
        registry = BackendRegistry()
        registry.register("native", NativeBackend)
        name, backend = registry.auto_select(
            source=tmp_path / "src",
            target=tmp_path / "dst",
            preferred_order=["rsync", "native"],  # rsync not registered
        )
        assert name == "native"

    def test_auto_select_no_match_raises(self, tmp_path: Path):
        registry = BackendRegistry()
        import pytest
        with pytest.raises(RuntimeError, match="No suitable backend"):
            registry.auto_select(
                source=tmp_path / "src",
                target=tmp_path / "dst",
                preferred_order=["unknown"],
            )

    def test_list_available(self):
        registry = BackendRegistry()
        registry.register("native", NativeBackend)
        available = registry.list_available()
        assert "native" in available
```

**Step 2: Run tests to verify they fail**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_backend_registry.py -v"`
Expected: FAIL with ImportError

**Step 3: Write implementation**

`src/datenassistent/backends/registry.py`:
```python
"""Backend registry with auto-selection logic."""

from pathlib import Path
from typing import Any


class BackendRegistry:
    """Manages available copy backends and selects the best one."""

    def __init__(self) -> None:
        self._backends: dict[str, type] = {}

    def register(self, name: str, backend_cls: type) -> None:
        self._backends[name] = backend_cls

    def get(self, name: str) -> Any | None:
        cls = self._backends.get(name)
        if cls is None:
            return None
        return cls()

    def auto_select(
        self,
        source: Path,
        target: Path,
        preferred_order: list[str],
    ) -> tuple[str, Any]:
        """Select best backend for the given source/target.

        Tries backends in preferred_order, returns first that is registered
        and supports the source/target combination.
        """
        for name in preferred_order:
            cls = self._backends.get(name)
            if cls is None:
                continue
            instance = cls()
            if hasattr(instance, "is_available") and not instance.is_available():
                continue
            if instance.supports(source, target):
                return (name, instance)

        # Fallback: try any registered backend
        for name, cls in self._backends.items():
            instance = cls()
            if hasattr(instance, "is_available") and not instance.is_available():
                continue
            if instance.supports(source, target):
                return (name, instance)

        raise RuntimeError(
            f"No suitable backend found for {source} -> {target}. "
            f"Registered: {list(self._backends.keys())}"
        )

    def list_available(self) -> list[str]:
        """Return names of all registered backends."""
        return list(self._backends.keys())
```

**Step 4: Run tests to verify they pass**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_backend_registry.py -v"`
Expected: All PASSED

**Step 5: Commit**

```bash
git add src/datenassistent/backends/registry.py tests/unit/test_backend_registry.py
git commit -m "feat: add backend registry with auto-selection"
```

---

### Task 10: Orchestrator (Ties Everything Together)

**Files:**
- Create: `src/datenassistent/core/orchestrator.py`
- Test: `tests/unit/test_orchestrator.py`

**Step 1: Write the failing tests**

`tests/unit/test_orchestrator.py`:
```python
"""Tests for the copy orchestrator."""

from pathlib import Path

from datenassistent.config.schema import AppConfig, VerifyMode
from datenassistent.core.orchestrator import CopyOrchestrator


def _make_source_tree(base: Path) -> Path:
    src = base / "source"
    src.mkdir()
    (src / "file1.txt").write_text("hello")
    (src / "file2.txt").write_text("world")
    return src


class TestCopyOrchestrator:
    def test_preview(self, tmp_path: Path):
        src = _make_source_tree(tmp_path)
        dst = tmp_path / "target"
        config = AppConfig()
        orch = CopyOrchestrator(config=config, db_path=tmp_path / "test.db")
        preview = orch.preview(source=src, target=dst)
        assert preview.total_files == 2
        assert preview.total_bytes > 0

    def test_execute_with_quick_verify(self, tmp_path: Path):
        src = _make_source_tree(tmp_path)
        dst = tmp_path / "target"
        config = AppConfig()
        orch = CopyOrchestrator(config=config, db_path=tmp_path / "test.db")

        events: list[dict] = []
        result = orch.execute(
            source=src,
            target=dst,
            progress_callback=events.append,
        )
        assert result.status == "success"
        assert result.files_copied == 2
        assert (dst / "file1.txt").read_text() == "hello"

    def test_execute_with_deep_verify(self, tmp_path: Path):
        src = _make_source_tree(tmp_path)
        dst = tmp_path / "target"
        config = AppConfig.model_validate({"defaults": {"verify_mode": "deep"}})
        orch = CopyOrchestrator(config=config, db_path=tmp_path / "test.db")

        result = orch.execute(
            source=src,
            target=dst,
            progress_callback=lambda e: None,
        )
        assert result.status == "success"

    def test_execute_logs_to_database(self, tmp_path: Path):
        src = _make_source_tree(tmp_path)
        dst = tmp_path / "target"
        config = AppConfig()
        db_path = tmp_path / "test.db"
        orch = CopyOrchestrator(config=config, db_path=db_path)

        orch.execute(source=src, target=dst, progress_callback=lambda e: None)

        jobs = orch.repo.list_jobs()
        assert len(jobs) == 1
        assert jobs[0].status == "success"
        assert jobs[0].total_files == 2

        files = orch.repo.get_files_for_job(jobs[0].id)
        assert len(files) == 2
```

**Step 2: Run tests to verify they fail**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_orchestrator.py -v"`
Expected: FAIL with ImportError

**Step 3: Write implementation**

`src/datenassistent/core/orchestrator.py`:
```python
"""Orchestrates copy operations: backend selection, execution, verification, logging."""

from pathlib import Path
from typing import Any, Callable

from datenassistent.backends.base import CopyResult, PreviewResult
from datenassistent.backends.native import NativeBackend
from datenassistent.backends.registry import BackendRegistry
from datenassistent.config.schema import AppConfig, VerifyMode
from datenassistent.core.verification import deep_verify, quick_verify
from datenassistent.db.repository import JobRepository


class CopyOrchestrator:
    """Coordinates backend selection, copy execution, verification, and logging."""

    def __init__(self, config: AppConfig, db_path: Path) -> None:
        self.config = config
        self.repo = JobRepository(db_path)
        self._registry = BackendRegistry()
        self._register_backends()

    def _register_backends(self) -> None:
        self._registry.register("native", NativeBackend)
        # Conditionally register rsync/rclone if available
        try:
            from datenassistent.backends.rsync import RsyncBackend

            if RsyncBackend.is_available():
                self._registry.register("rsync", RsyncBackend)
        except ImportError:
            pass

    def preview(
        self,
        source: Path,
        target: Path,
        backend_name: str | None = None,
    ) -> PreviewResult:
        """Run dry-run preview of copy operation."""
        from datenassistent.core.job import CopyJob

        _, backend = self._select_backend(source, target, backend_name)
        job = CopyJob(source=source, target=target)
        return backend.dry_run(job)

    def execute(
        self,
        source: Path,
        target: Path,
        progress_callback: Callable[[dict[str, Any]], None],
        backend_name: str | None = None,
    ) -> CopyResult:
        """Execute copy with verification and logging."""
        from datenassistent.core.job import CopyJob

        name, backend = self._select_backend(source, target, backend_name)

        job = CopyJob(
            source=source,
            target=target,
            metadata_mode=self.config.defaults.metadata_mode,
            verify_mode=self.config.defaults.verify_mode,
            conflict_strategy=self.config.defaults.conflict_strategy,
            abort_behavior=self.config.defaults.abort_behavior,
            backend=name,
        )

        # Log job start
        job_id = self.repo.create_job(
            source_path=str(source),
            target_path=str(target),
            backend_used=name,
            metadata_mode=job.metadata_mode.value,
            verify_mode=job.verify_mode.value,
            abort_behavior=job.abort_behavior.value,
        )

        # Execute copy
        result = backend.execute(job, progress_callback)

        # Verify and log files
        if result.status == "success":
            preview = backend.dry_run(job)
            for pf in preview.files:
                verified = self._verify_file(pf.source, pf.target, job.verify_mode)
                checksum_algo = None
                checksum_value = None
                if job.verify_mode == VerifyMode.DEEP:
                    checksum_algo = self.config.defaults.checksum_algorithm
                    from datenassistent.core.verification import compute_checksum

                    checksum_value = compute_checksum(pf.target, checksum_algo)

                self.repo.add_file_record(
                    job_id=job_id,
                    source_path=str(pf.source),
                    target_path=str(pf.target),
                    size_bytes=pf.size_bytes,
                    checksum_algo=checksum_algo,
                    checksum_value=checksum_value,
                    status="copied" if verified else "failed",
                )

                if not verified:
                    self.repo.complete_job(
                        job_id,
                        status="failed",
                        total_files=result.files_copied,
                        total_bytes=result.bytes_copied,
                        error_message=f"Verification failed for {pf.target}",
                    )
                    return CopyResult(
                        status="failed",
                        files_copied=result.files_copied,
                        bytes_copied=result.bytes_copied,
                        error=f"Verification failed for {pf.target}",
                    )

        # Log job completion
        self.repo.complete_job(
            job_id,
            status=result.status,
            total_files=result.files_copied,
            total_bytes=result.bytes_copied,
            error_message=result.error,
        )

        return result

    def _select_backend(
        self,
        source: Path,
        target: Path,
        backend_name: str | None,
    ) -> tuple[str, Any]:
        if backend_name:
            backend = self._registry.get(backend_name)
            if backend is None:
                raise RuntimeError(f"Backend '{backend_name}' not found")
            return (backend_name, backend)
        return self._registry.auto_select(
            source, target, self.config.backends.preferred_order
        )

    @staticmethod
    def _verify_file(source: Path, target: Path, mode: VerifyMode) -> bool:
        if mode == VerifyMode.QUICK:
            return quick_verify(source, target)
        elif mode == VerifyMode.DEEP:
            match, _, _ = deep_verify(source, target)
            return match
        return True
```

**Step 4: Run tests to verify they pass**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_orchestrator.py -v"`
Expected: All PASSED

**Step 5: Commit**

```bash
git add src/datenassistent/core/orchestrator.py tests/unit/test_orchestrator.py
git commit -m "feat: add copy orchestrator with verification and logging"
```

---

### Task 11: Minimal TUI App Shell (Textual)

**Files:**
- Create: `src/datenassistent/app.py`
- Create: `src/datenassistent/ui/__init__.py`
- Create: `src/datenassistent/ui/wizard/__init__.py`
- Create: `src/datenassistent/ui/wizard/source.py`
- Create: `src/datenassistent/ui/widgets/__init__.py`

**Step 1: Write a smoke test**

`tests/unit/test_app.py`:
```python
"""Smoke test for the TUI app."""

import pytest
from datenassistent.app import DatenassistentApp


class TestApp:
    @pytest.mark.asyncio
    async def test_app_starts(self):
        """Verify the app can be instantiated and has correct title."""
        app = DatenassistentApp()
        assert app.title == "Datenassistent"
```

**Step 2: Run test to verify it fails**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_app.py -v"`
Expected: FAIL with ImportError

**Step 3: Write implementation**

`src/datenassistent/ui/__init__.py`: empty file.
`src/datenassistent/ui/wizard/__init__.py`: empty file.
`src/datenassistent/ui/widgets/__init__.py`: empty file.

`src/datenassistent/app.py`:
```python
"""Main Textual TUI application."""

from textual.app import App, ComposeResult
from textual.widgets import Footer, Header, Static


class DatenassistentApp(App):
    """Cross-platform TUI for integrity-preserving file copies."""

    TITLE = "Datenassistent"
    SUB_TITLE = "Integrity-Preserving File Copies"

    BINDINGS = [
        ("q", "quit", "Quit"),
    ]

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static("Welcome to Datenassistent. Wizard coming soon.", id="welcome")
        yield Footer()
```

**Step 4: Run test to verify it passes**

Run: `nix-shell -p uv --run "uv run pytest tests/unit/test_app.py -v"`
Expected: All PASSED

**Step 5: Verify the app runs**

Run: `nix-shell -p uv --run "timeout 3 uv run python -m datenassistent || true"`
Expected: App starts briefly and exits (timeout), no crash.

**Step 6: Commit**

```bash
git add src/datenassistent/app.py src/datenassistent/ui/ tests/unit/test_app.py
git commit -m "feat: add minimal Textual TUI app shell"
```

---

### Task 12: Run Full Test Suite + Lint

**Step 1: Run all tests**

Run: `nix-shell -p uv --run "uv run pytest -v"`
Expected: All tests PASSED

**Step 2: Run ruff linter**

Run: `nix-shell -p uv --run "uv run ruff check src/ tests/"`
Expected: No errors (or fix any that appear)

**Step 3: Run ruff formatter**

Run: `nix-shell -p uv --run "uv run ruff format src/ tests/"`
Expected: Files formatted

**Step 4: Commit any formatting fixes**

```bash
git add -A
git commit -m "chore: lint and format codebase"
```

---

## Summary

Tasks 1-12 build the **foundation layer** of the Datenassistent:

| Task | Component | What it delivers |
|------|-----------|-----------------|
| 1 | Scaffolding | pyproject.toml, package structure, uv environment |
| 2 | Config Schema | Pydantic models for all configuration options |
| 3 | Config Loader | TOML parsing, global + project config merging |
| 4 | CopyJob Model | Data model for copy operations |
| 5 | Database | SQLite schema, job/file logging repository |
| 6 | Verification | BLAKE3 + SHA256 checksum computation and comparison |
| 7 | Native Backend | Pure Python copy backend (cross-platform fallback) |
| 8 | Rsync Backend | rsync integration for local + SSH copies |
| 9 | Backend Registry | Auto-selection logic based on source/target + availability |
| 10 | Orchestrator | Ties backends, verification, and logging together |
| 11 | TUI Shell | Minimal Textual app that starts and shows a welcome screen |
| 12 | Quality Gate | Full test suite + linting |

**After these 12 tasks:** The core engine works end-to-end. You can programmatically copy files with verification and logging. The TUI shell is ready for the Wizard screens to be built in a follow-up plan.

**Follow-up plans needed:**
- **Phase 2:** TUI Wizard (source picker, target picker, options, preview, dashboard)
- **Phase 3:** Rclone backend, restic/borg backends
- **Phase 4:** Conflict resolution, abort handling
- **Phase 5:** Cross-platform metadata handling, sidecar files
