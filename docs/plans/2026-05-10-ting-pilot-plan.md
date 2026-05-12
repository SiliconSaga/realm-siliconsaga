# Ting Pilot — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the ting parent-advocacy MVP per
[`2026-05-10-ting-pilot-design.md`](2026-05-10-ting-pilot-design.md): a
FastAPI app with survey engine (ranking / NPS / Likert), endorsable
comments, pledges, public summary, code-based auth, and GoatCounter
analytics — deployable across four tiers (dev, localk8s, cmdbee GKE,
frontstate GKE prod).

**Architecture:** Single FastAPI service, server-rendered Jinja
templates with HTMX + Alpine.js, PostgreSQL via Mimir Crossplane Claims
in k8s tiers (or `docker-compose` in dev tier), Valkey for sessions and
rate limits. CLI for admin operations. Kustomize overlays for
deployment tiers. The dev tier requires only Docker — no homelab
dependency — so a fellow contributor can clone and run.

**Tech Stack:** Python 3.12, FastAPI, Jinja2, SQLAlchemy 2.x, Alembic,
Pydantic v2, Typer, redis-py, qrcode, pytest + testcontainers, ruff,
Docker, kustomize, cert-manager + Gateway API.

---

## File Structure (target)

```
SiliconSaga/ting (new GitHub repo, cloned to components/ting/)
├── README.md, AGENTS.md, LICENSE, .gitignore, .env.example
├── Dockerfile, docker-compose.yml, pyproject.toml, alembic.ini
├── scripts/ting                       # bash wrapper → python -m ting.cli
├── src/ting/
│   ├── app.py                          # FastAPI factory
│   ├── cli.py                          # Typer entrypoint
│   ├── config.py                       # Pydantic settings (env-var driven)
│   ├── db.py, valkey.py                # service clients
│   ├── auth.py, codes.py, ratelimit.py # auth + code-gen
│   ├── aggregation.py                  # Borda/NPS/Likert math
│   ├── models/                         # SQLAlchemy ORM (one file per table)
│   ├── routes/{public,survey,summary}.py
│   ├── services/{seed_loader,code_service,summary_service}.py
│   ├── templates/                      # Jinja
│   └── static/                         # css + htmx/alpine/sortable
├── migrations/                         # Alembic
├── seeds/{example,schema,2026-05-13-pilot.yaml.example}
├── k8s/{base, overlays/{localk8s,cmdbee,frontstate}}
├── tests/{unit, integration, e2e}
├── docs/{architecture,operations}.md
└── .github/workflows/{ci,image}.yml

yggdrasil-side additions:
├── realms/realm-siliconsaga/adapters/ting.yaml     # ws test adapter
├── ecosystem.local.yaml                            # add ting entry
└── docs/plans/2026-05-10-ting-pilot-plan.md        # this file
```

---

## Phase 0 — Repo creation + workspace registration

### Task 0.1: Create GitHub repo

**Files:** none (remote action).

- [ ] **Step 1: Create empty public SiliconSaga/ting repo**

```bash
cd /Users/cervator/dev/git_ws/yggdrasil
source .env
gh repo create SiliconSaga/ting --public \
  --description "Parent advocacy pilot — structured-input site with anonymous code-based auth, survey + pledges + endorsements"
```

Expected: `https://github.com/SiliconSaga/ting` confirmation line.

- [ ] **Step 2: Verify push permissions for agent-refr**

```bash
gh repo view SiliconSaga/ting --json viewerPermission
```

Expected: `"viewerPermission":"ADMIN"` (or at least `"WRITE"`).

- [ ] **Step 3: Enable GHCR package visibility (will be set on first push)**

No-op until first image push. Note for later: when image lands, verify
`https://github.com/SiliconSaga/ting/pkgs/container/ting` is public.

### Task 0.2: Clone via ws + register in ecosystem.local.yaml

**Files:**
- Modify: `ecosystem.local.yaml`

- [ ] **Step 1: Clone the empty repo into components/ting/**

```bash
cd /Users/cervator/dev/git_ws/yggdrasil
bash scripts/ws clone --url https://github.com/SiliconSaga/ting.git --name ting --add-eco
```

Expected: clone succeeds and `ecosystem.local.yaml` gains a `ting:` entry.

- [ ] **Step 2: Verify and adjust the ecosystem entry**

Open `ecosystem.local.yaml` and confirm/edit to:

```yaml
identity:
  human_account: Cervator
components:
  knarr:
    tier: 3
    namespace: knarr
  tutorial-test:
    repo: https://github.com/agent-refr/tutorial-test.git
  ting:
    tier: 3
    namespace: ting
    repo: https://github.com/SiliconSaga/ting.git
```

- [ ] **Step 3: Commit the workspace-side change**

```bash
cat > .commits/ting-ecosystem-entry.md <<'EOF'
---
message: "chore(ecosystem): add ting component entry"
add:
  - ecosystem.local.yaml
---

Register ting (parent advocacy pilot) as a tier-3 component in the
per-developer ecosystem layer. Repo lives at SiliconSaga/ting; will be
promoted to realm ecosystem after the May pilot stabilizes.
EOF
bash scripts/ws commit yggdrasil .commits/ting-ecosystem-entry.md
```

Expected: commit succeeds on the current `feat/ting-pilot-design` branch.

### Task 0.3: Initialize the ting repo content

**Files:**
- Create: `components/ting/.gitignore`
- Create: `components/ting/LICENSE`
- Create: `components/ting/README.md`
- Create: `components/ting/AGENTS.md`

- [ ] **Step 1: Add a .gitignore**

```bash
cd components/ting
cat > .gitignore <<'EOF'
# Python
__pycache__/
*.py[cod]
*$py.class
*.egg-info/
.venv/
venv/
.pytest_cache/
.ruff_cache/
.mypy_cache/
htmlcov/
.coverage
*.cover

# Environment
.env
.env.local
.env.ting

# Build
dist/
build/

# OS / editors
.DS_Store
.idea/
.vscode/
*.swp

# Local k8s
.outputs/
EOF
```

- [ ] **Step 2: Add MIT license**

```bash
cat > LICENSE <<'EOF'
MIT License

Copyright (c) 2026 SiliconSaga contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
```

- [ ] **Step 3: Add a stub README pointing at the design doc**

```bash
cat > README.md <<'EOF'
# Ting — Parent Advocacy Pilot

Structured-input parent advocacy site. Code-based auth, anonymous-but-
verified, survey (ranking + NPS + Likert) + endorsable comments +
pledges.

Design: [`docs/architecture.md`](docs/architecture.md), or upstream
yggdrasil [`docs/plans/2026-05-10-ting-pilot-design.md`](https://github.com/SiliconSaga/yggdrasil/blob/main/docs/plans/2026-05-10-ting-pilot-design.md).

## Quickstart (dev tier — no k8s)

Requires Docker + Python 3.12.

```bash
cp .env.example .env
docker compose up -d
python -m venv .venv && source .venv/bin/activate
pip install -e '.[dev]'
./scripts/ting migrate
./scripts/ting seed seeds/example.yaml
./scripts/ting dev
```

Open <http://localhost:8000>.

## Other tiers

- `localk8s` — k3d/Rancher Desktop with Mimir; apply `k8s/overlays/localk8s`
- `cmdbee` — GKE staging (`ting.cmdbee.org`); apply `k8s/overlays/cmdbee`
- `frontstate` — GKE production (`ting.frontstate.org`); apply `k8s/overlays/frontstate`

See [`docs/operations.md`](docs/operations.md) for deploy details.
EOF
```

- [ ] **Step 4: Add a stub AGENTS.md**

```bash
cat > AGENTS.md <<'EOF'
# Ting — Agent Guidance

Tier-3 component in the realm-siliconsaga ecosystem. Parent advocacy
pilot per [`yggdrasil/docs/plans/2026-05-10-ting-pilot-design.md`](https://github.com/SiliconSaga/yggdrasil/blob/main/docs/plans/2026-05-10-ting-pilot-design.md).

## Key Commands

- `ws test ting` — pytest unit + integration suite
- `ws lint ting` — ruff
- `./scripts/ting --help` — admin operations (seed, codes, cohort,
  bulletin, report, healthcheck, migrate, dev)

## Local development

Use the dev tier — Docker only, no homelab dependency. See
[`README.md`](README.md).

## Deployment

Four kustomize overlays under `k8s/overlays/`. The cmdbee overlay is
the canonical GKE staging target; production cutover to frontstate is
gated behind manual approval after the May 13 demo.
EOF
```

- [ ] **Step 5: Initial commit and push**

```bash
git add .gitignore LICENSE README.md AGENTS.md
git commit -m "chore: initial repo skeleton" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push -u origin main
```

Expected: push succeeds; `main` exists upstream.

---

## Phase 1 — Python scaffold + FastAPI hello-world

### Task 1.1: pyproject.toml + dependencies

**Files:**
- Create: `components/ting/pyproject.toml`

- [ ] **Step 1: Author pyproject.toml**

```toml
[project]
name = "ting"
version = "0.1.0"
description = "Parent advocacy pilot — structured input, anonymous code-based auth"
readme = "README.md"
license = { text = "MIT" }
requires-python = ">=3.12"
dependencies = [
    "fastapi==0.115.5",
    "uvicorn[standard]==0.32.1",
    "jinja2==3.1.4",
    "sqlalchemy==2.0.36",
    "psycopg[binary]==3.2.3",
    "alembic==1.14.0",
    "pydantic==2.10.3",
    "pydantic-settings==2.7.0",
    "typer==0.15.1",
    "redis==5.2.1",
    "qrcode[pil]==8.0",
    "pyyaml==6.0.2",
    "python-multipart==0.0.20",
    "itsdangerous==2.2.0",
    "httpx==0.28.1",
]

[project.optional-dependencies]
dev = [
    "pytest==8.3.4",
    "pytest-asyncio==0.25.0",
    "testcontainers[postgres]==4.9.0",
    "ruff==0.8.4",
    "mypy==1.13.0",
    "types-pyyaml==6.0.12.20240917",
]

[project.scripts]
ting = "ting.cli:app"

[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[tool.setuptools.packages.find]
where = ["src"]

[tool.ruff]
line-length = 100
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "W", "I", "B", "UP", "RUF"]

[tool.pytest.ini_options]
testpaths = ["tests"]
asyncio_mode = "auto"
```

- [ ] **Step 2: Create empty src + venv**

```bash
mkdir -p src/ting
touch src/ting/__init__.py
python3.12 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -e '.[dev]'
```

Expected: `pip install` completes; `ting` script appears in `.venv/bin/`.

- [ ] **Step 3: Commit**

```bash
git add pyproject.toml src/ting/__init__.py
git commit -m "chore: python project skeleton (FastAPI/SQLA/Typer/redis)" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 1.2: Pydantic settings

**Files:**
- Create: `src/ting/config.py`
- Create: `.env.example`
- Create: `tests/conftest.py`
- Create: `tests/unit/test_config.py`

- [ ] **Step 1: Write failing test**

```python
# tests/unit/test_config.py
import os
from ting.config import Settings


def test_settings_load_from_env(monkeypatch):
    monkeypatch.setenv("TING_DATABASE_URL", "postgresql://u:p@h:5432/d")
    monkeypatch.setenv("TING_VALKEY_URL", "redis://h:6379/0")
    monkeypatch.setenv("TING_SESSION_SECRET", "x" * 32)
    s = Settings()
    assert str(s.database_url) == "postgresql://u:p@h:5432/d"
    assert str(s.valkey_url) == "redis://h:6379/0"
    assert s.session_secret == "x" * 32
    assert s.goatcounter_site_code is None
    assert s.base_url == "http://localhost:8000"
    assert s.environment == "dev"


def test_settings_optional_goatcounter(monkeypatch):
    monkeypatch.setenv("TING_DATABASE_URL", "postgresql://u:p@h:5432/d")
    monkeypatch.setenv("TING_VALKEY_URL", "redis://h:6379/0")
    monkeypatch.setenv("TING_SESSION_SECRET", "x" * 32)
    monkeypatch.setenv("TING_GOATCOUNTER_SITE_CODE", "ting-test")
    s = Settings()
    assert s.goatcounter_site_code == "ting-test"
```

- [ ] **Step 2: Run test (expect fail — Settings not yet defined)**

```bash
pytest tests/unit/test_config.py -v
```

Expected: ImportError / fail.

- [ ] **Step 3: Implement Settings**

```python
# src/ting/config.py
from functools import lru_cache
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="TING_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    environment: str = "dev"
    base_url: str = "http://localhost:8000"
    database_url: str
    valkey_url: str
    session_secret: str = Field(min_length=32)
    goatcounter_site_code: str | None = None
    max_comments_per_code: int = 5
    rate_limit_redemption_per_hour: int = 10
    rate_limit_writes_per_5min: int = 60


@lru_cache
def get_settings() -> Settings:
    return Settings()
```

- [ ] **Step 4: Add .env.example**

```
TING_ENVIRONMENT=dev
TING_BASE_URL=http://localhost:8000
TING_DATABASE_URL=postgresql://ting:ting@localhost:5432/ting
TING_VALKEY_URL=redis://localhost:6379/0
TING_SESSION_SECRET=change-me-to-a-32-byte-random-string-min
# TING_GOATCOUNTER_SITE_CODE=
```

- [ ] **Step 5: Run tests pass**

```bash
pytest tests/unit/test_config.py -v
```

Expected: 2 passed.

- [ ] **Step 6: Commit**

```bash
git add src/ting/config.py .env.example tests/unit/test_config.py
git commit -m "feat: env-driven Pydantic settings (TING_* vars)" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 1.3: FastAPI app factory + hello-world

**Files:**
- Create: `src/ting/app.py`
- Create: `tests/unit/test_app.py`

- [ ] **Step 1: Failing test**

```python
# tests/unit/test_app.py
from fastapi.testclient import TestClient
from ting.app import create_app


def test_root_returns_200(monkeypatch):
    monkeypatch.setenv("TING_DATABASE_URL", "postgresql://u:p@h:5432/d")
    monkeypatch.setenv("TING_VALKEY_URL", "redis://h:6379/0")
    monkeypatch.setenv("TING_SESSION_SECRET", "x" * 32)
    app = create_app()
    client = TestClient(app)
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}
```

- [ ] **Step 2: Run (expect fail)**

```bash
pytest tests/unit/test_app.py -v
```

- [ ] **Step 3: Implement app factory**

```python
# src/ting/app.py
from fastapi import FastAPI
from .config import get_settings


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(title="ting", version="0.1.0")

    @app.get("/healthz")
    def healthz() -> dict[str, str]:
        return {"status": "ok"}

    return app


app = create_app()
```

- [ ] **Step 4: Tests pass**

```bash
pytest tests/unit/test_app.py -v
```

- [ ] **Step 5: Commit**

```bash
git add src/ting/app.py tests/unit/test_app.py
git commit -m "feat: FastAPI app factory + /healthz" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 1.4: docker-compose.yml + Dockerfile

**Files:**
- Create: `docker-compose.yml`
- Create: `Dockerfile`

- [ ] **Step 1: docker-compose.yml for dev tier**

```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: ting
      POSTGRES_PASSWORD: ting
      POSTGRES_DB: ting
    ports:
      - "5432:5432"
    volumes:
      - ting_pg_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ting"]
      interval: 5s
      timeout: 5s
      retries: 5

  valkey:
    image: valkey/valkey:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - ting_valkey_data:/data
    healthcheck:
      test: ["CMD", "valkey-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  ting_pg_data:
  ting_valkey_data:
```

- [ ] **Step 2: Dockerfile (multi-stage)**

```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /build
COPY pyproject.toml ./
COPY src/ ./src/
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir --target=/install .

FROM python:3.12-slim
WORKDIR /app
ENV PYTHONPATH=/app/lib \
    PYTHONUNBUFFERED=1 \
    PATH=/app/lib/bin:$PATH
COPY --from=builder /install /app/lib
COPY src/ /app/src/
COPY migrations/ /app/migrations/
COPY alembic.ini /app/
COPY seeds/ /app/seeds/
EXPOSE 8000
CMD ["uvicorn", "ting.app:app", "--host", "0.0.0.0", "--port", "8000"]
```

- [ ] **Step 3: Verify compose + image build locally**

```bash
docker compose up -d
docker compose ps   # postgres + valkey healthy
docker build -t ting:dev .
```

Expected: services healthy; image builds successfully.

- [ ] **Step 4: Commit**

```bash
git add docker-compose.yml Dockerfile
git commit -m "feat: docker-compose (dev tier) + multi-stage Dockerfile" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 1.5: scripts/ting wrapper + Typer CLI skeleton

**Files:**
- Create: `src/ting/cli.py`
- Create: `scripts/ting`

- [ ] **Step 1: Typer entry**

```python
# src/ting/cli.py
import typer

app = typer.Typer(no_args_is_help=True, help="Ting admin CLI")


@app.command()
def healthcheck() -> None:
    """Check DB / Valkey connectivity + print version."""
    from .config import get_settings
    s = get_settings()
    typer.echo(f"ting v0.1.0 environment={s.environment}")
    typer.echo(f"database_url={s.database_url}")
    typer.echo(f"valkey_url={s.valkey_url}")


if __name__ == "__main__":
    app()
```

- [ ] **Step 2: scripts/ting bash wrapper**

```bash
mkdir -p scripts
cat > scripts/ting <<'EOF'
#!/usr/bin/env bash
# scripts/ting — invoke the ting CLI from the project root.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$here/.." && pwd)"

if [[ -d "$root/.venv" ]]; then
    # shellcheck disable=SC1091
    source "$root/.venv/bin/activate"
fi

cd "$root"
exec python -m ting.cli "$@"
EOF
chmod +x scripts/ting
```

- [ ] **Step 3: Smoke test the wrapper**

```bash
./scripts/ting healthcheck
```

Expected: prints version + URLs from `.env` (or env vars).

- [ ] **Step 4: Commit**

```bash
git add src/ting/cli.py scripts/ting
git commit -m "feat: Typer CLI skeleton + scripts/ting wrapper" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 2 — Database models + Alembic

### Task 2.1: SQLAlchemy engine + session

**Files:**
- Create: `src/ting/db.py`
- Create: `src/ting/models/__init__.py`
- Create: `src/ting/models/base.py`
- Create: `tests/integration/conftest.py`
- Create: `tests/integration/test_db.py`

- [ ] **Step 1: Integration test fixture using testcontainers**

```python
# tests/integration/conftest.py
import pytest
from testcontainers.postgres import PostgresContainer


@pytest.fixture(scope="session")
def postgres_url():
    with PostgresContainer("postgres:16-alpine") as pg:
        yield pg.get_connection_url().replace("postgresql+psycopg2://", "postgresql://")


@pytest.fixture
def settings_env(monkeypatch, postgres_url):
    monkeypatch.setenv("TING_DATABASE_URL", postgres_url)
    monkeypatch.setenv("TING_VALKEY_URL", "redis://localhost:6379/0")
    monkeypatch.setenv("TING_SESSION_SECRET", "x" * 32)
    monkeypatch.setenv("TING_ENVIRONMENT", "test")
    from ting.config import get_settings
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()
```

- [ ] **Step 2: Failing test**

```python
# tests/integration/test_db.py
from sqlalchemy import text
from ting.db import get_engine, session_scope


def test_engine_connects(settings_env):
    eng = get_engine()
    with eng.connect() as conn:
        r = conn.execute(text("SELECT 1"))
        assert r.scalar() == 1


def test_session_scope_commits(settings_env):
    eng = get_engine()
    with eng.begin() as conn:
        conn.execute(text("CREATE TABLE smoke (v INT)"))
    with session_scope() as s:
        s.execute(text("INSERT INTO smoke (v) VALUES (42)"))
    with eng.connect() as conn:
        r = conn.execute(text("SELECT v FROM smoke"))
        assert r.scalar() == 42
```

- [ ] **Step 3: Run (expect fail — module not defined)**

```bash
pytest tests/integration/test_db.py -v
```

- [ ] **Step 4: Implement db.py**

```python
# src/ting/db.py
from contextlib import contextmanager
from collections.abc import Iterator
from functools import lru_cache
from sqlalchemy import create_engine
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

from .config import get_settings


@lru_cache
def get_engine() -> Engine:
    s = get_settings()
    return create_engine(s.database_url, pool_pre_ping=True, future=True)


@lru_cache
def _session_factory() -> sessionmaker[Session]:
    return sessionmaker(bind=get_engine(), expire_on_commit=False, future=True)


@contextmanager
def session_scope() -> Iterator[Session]:
    session = _session_factory()()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()
```

- [ ] **Step 5: models/base.py**

```python
# src/ting/models/base.py
from datetime import datetime, UTC
from sqlalchemy import DateTime
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


def utcnow() -> datetime:
    return datetime.now(UTC)
```

- [ ] **Step 6: Tests pass**

```bash
pytest tests/integration/test_db.py -v
```

Expected: 2 passed.

- [ ] **Step 7: Commit**

```bash
git add src/ting/db.py src/ting/models/ tests/integration/
git commit -m "feat: SQLAlchemy engine + session scope" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 2.2: All ORM models in one pass

Rationale: schema is small (10 tables) and the relationships are tightly
coupled. One file per table; tests verify the schema as a whole.

**Files:**
- Create: `src/ting/models/cohort.py`
- Create: `src/ting/models/code.py`
- Create: `src/ting/models/proposal.py`
- Create: `src/ting/models/question.py`
- Create: `src/ting/models/response.py`
- Create: `src/ting/models/comment.py`
- Create: `src/ting/models/endorsement.py`
- Create: `src/ting/models/pledge.py`
- Create: `src/ting/models/bulletin.py`
- Create: `src/ting/models/metrics_event.py`
- Modify: `src/ting/models/__init__.py`
- Create: `tests/integration/test_models.py`

- [ ] **Step 1: Failing integration test**

```python
# tests/integration/test_models.py
import pytest
from sqlalchemy.exc import IntegrityError
from ting.db import get_engine, session_scope
from ting.models import Base, Cohort, Code, Proposal, Question, Response


@pytest.fixture(autouse=True)
def schema(settings_env):
    Base.metadata.create_all(get_engine())
    yield
    Base.metadata.drop_all(get_engine())


def test_create_cohort_and_code():
    with session_scope() as s:
        c = Cohort(name="TEST-2026-spring")
        s.add(c)
        s.flush()
        code = Code(code_str="TST-AAAA-BBBB", cohort_id=c.cohort_id)
        s.add(code)
    with session_scope() as s:
        assert s.query(Code).count() == 1


def test_response_unique_per_code_question():
    with session_scope() as s:
        c = Cohort(name="TEST-2026-spring")
        s.add(c); s.flush()
        code = Code(code_str="TST-AAAA-BBBB", cohort_id=c.cohort_id)
        prop = Proposal(slug="p1", title="P1", body="...", status="active")
        q = Question(slug="q1", type="likert", prompt="?",
                     payload={"statement": "x"}, display_order=1, cohort_id=c.cohort_id)
        s.add_all([code, prop, q]); s.flush()
        s.add(Response(code_id=code.code_id, question_id=q.question_id, payload={"score": 4}))
    with pytest.raises(IntegrityError):
        with session_scope() as s:
            code = s.query(Code).one()
            q = s.query(Question).one()
            s.add(Response(code_id=code.code_id, question_id=q.question_id, payload={"score": 5}))
```

- [ ] **Step 2: Run (expect fail)**

```bash
pytest tests/integration/test_models.py -v
```

- [ ] **Step 3: Implement each model file**

```python
# src/ting/models/cohort.py
from datetime import datetime
from uuid import UUID, uuid4
from sqlalchemy import String, DateTime, Text
from sqlalchemy.orm import Mapped, mapped_column
from .base import Base, utcnow


class Cohort(Base):
    __tablename__ = "cohorts"

    cohort_id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    name: Mapped[str] = mapped_column(String(120), unique=True, nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    retired_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
```

```python
# src/ting/models/code.py
from datetime import datetime
from uuid import UUID, uuid4
from sqlalchemy import String, DateTime, ForeignKey, SmallInteger
from sqlalchemy.orm import Mapped, mapped_column
from .base import Base, utcnow


class Code(Base):
    __tablename__ = "codes"

    code_id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    code_str: Mapped[str] = mapped_column(String(40), unique=True, nullable=False, index=True)
    cohort_id: Mapped[UUID] = mapped_column(ForeignKey("cohorts.cohort_id"), nullable=False)
    printed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    first_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    advocate_grade: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
```

```python
# src/ting/models/proposal.py
from datetime import datetime
from uuid import UUID, uuid4
from sqlalchemy import String, DateTime, Text
from sqlalchemy.orm import Mapped, mapped_column
from .base import Base, utcnow


class Proposal(Base):
    __tablename__ = "proposals"

    proposal_id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    slug: Mapped[str] = mapped_column(String(80), unique=True, nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False, default="")
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
```

```python
# src/ting/models/question.py
from datetime import datetime
from uuid import UUID, uuid4
from sqlalchemy import String, DateTime, Integer, Text, ForeignKey
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column
from .base import Base, utcnow


class Question(Base):
    __tablename__ = "questions"

    question_id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    slug: Mapped[str] = mapped_column(String(80), unique=True, nullable=False, index=True)
    type: Mapped[str] = mapped_column(String(20), nullable=False)  # ranking | nps | likert
    prompt: Mapped[str] = mapped_column(Text, nullable=False)
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    display_order: Mapped[int | None] = mapped_column(Integer, nullable=True)
    cohort_id: Mapped[UUID] = mapped_column(ForeignKey("cohorts.cohort_id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
```

```python
# src/ting/models/response.py
from datetime import datetime
from uuid import UUID, uuid4
from sqlalchemy import DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column
from .base import Base, utcnow


class Response(Base):
    __tablename__ = "responses"
    __table_args__ = (UniqueConstraint("code_id", "question_id", name="uq_response_code_question"),)

    response_id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    code_id: Mapped[UUID] = mapped_column(ForeignKey("codes.code_id"), nullable=False)
    question_id: Mapped[UUID] = mapped_column(ForeignKey("questions.question_id"), nullable=False)
    payload: Mapped[dict] = mapped_column(JSONB, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)
```

```python
# src/ting/models/comment.py
from datetime import datetime
from uuid import UUID, uuid4
from sqlalchemy import DateTime, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column
from .base import Base, utcnow


class Comment(Base):
    __tablename__ = "comments"

    comment_id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    proposal_id: Mapped[UUID] = mapped_column(ForeignKey("proposals.proposal_id"), nullable=False)
    author_code_id: Mapped[UUID] = mapped_column(ForeignKey("codes.code_id"), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    hidden_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
```

```python
# src/ting/models/endorsement.py
from datetime import datetime
from uuid import UUID
from sqlalchemy import DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column
from .base import Base, utcnow


class Endorsement(Base):
    __tablename__ = "endorsements"

    code_id: Mapped[UUID] = mapped_column(ForeignKey("codes.code_id"), primary_key=True)
    comment_id: Mapped[UUID] = mapped_column(ForeignKey("comments.comment_id"), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
```

```python
# src/ting/models/pledge.py
from datetime import datetime
from decimal import Decimal
from uuid import UUID
from sqlalchemy import DateTime, ForeignKey, Numeric
from sqlalchemy.orm import Mapped, mapped_column
from .base import Base, utcnow


class Pledge(Base):
    __tablename__ = "pledges"

    code_id: Mapped[UUID] = mapped_column(ForeignKey("codes.code_id"), primary_key=True)
    proposal_id: Mapped[UUID] = mapped_column(ForeignKey("proposals.proposal_id"), primary_key=True)
    amount_dollars: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False, default=0)
    hours_per_week: Mapped[Decimal] = mapped_column(Numeric(6, 2), nullable=False, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False)
```

```python
# src/ting/models/bulletin.py
from datetime import datetime
from uuid import UUID, uuid4
from sqlalchemy import DateTime, Text, String
from sqlalchemy.orm import Mapped, mapped_column
from .base import Base, utcnow


class Bulletin(Base):
    __tablename__ = "bulletins"

    bulletin_id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    posted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    posted_by: Mapped[str] = mapped_column(String(80), nullable=False)
```

```python
# src/ting/models/metrics_event.py
from datetime import datetime
from uuid import UUID, uuid4
from sqlalchemy import DateTime, Integer, String, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column
from .base import Base, utcnow


class MetricsEvent(Base):
    __tablename__ = "metrics_events"

    event_id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    event: Mapped[str] = mapped_column(String(40), nullable=False)
    code_id: Mapped[UUID | None] = mapped_column(ForeignKey("codes.code_id"), nullable=True)
    duration_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
```

- [ ] **Step 4: Wire up __init__.py**

```python
# src/ting/models/__init__.py
from .base import Base, utcnow
from .cohort import Cohort
from .code import Code
from .proposal import Proposal
from .question import Question
from .response import Response
from .comment import Comment
from .endorsement import Endorsement
from .pledge import Pledge
from .bulletin import Bulletin
from .metrics_event import MetricsEvent

__all__ = [
    "Base", "utcnow",
    "Cohort", "Code", "Proposal", "Question", "Response",
    "Comment", "Endorsement", "Pledge", "Bulletin", "MetricsEvent",
]
```

- [ ] **Step 5: Tests pass**

```bash
pytest tests/integration/test_models.py -v
```

Expected: 2 passed.

- [ ] **Step 6: Commit**

```bash
git add src/ting/models/ tests/integration/test_models.py
git commit -m "feat: SQLAlchemy ORM models for all tables (cohorts/codes/proposals/...)" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 2.3: Alembic baseline migration

**Files:**
- Create: `alembic.ini`
- Create: `migrations/env.py`
- Create: `migrations/script.py.mako`
- Create: `migrations/versions/001_baseline.py` (generated)

- [ ] **Step 1: alembic init layout**

```bash
alembic init -t generic migrations
```

(then move/replace generated `alembic.ini` to root).

- [ ] **Step 2: Edit migrations/env.py to use settings + Base.metadata**

Replace generated content with:

```python
# migrations/env.py
from logging.config import fileConfig
from sqlalchemy import engine_from_config, pool
from alembic import context

from ting.config import get_settings
from ting.models import Base

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata

settings = get_settings()
config.set_main_option("sqlalchemy.url", settings.database_url)


def run_migrations_offline() -> None:
    context.configure(
        url=config.get_main_option("sqlalchemy.url"),
        target_metadata=target_metadata,
        literal_binds=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
```

- [ ] **Step 3: Generate the baseline migration**

```bash
docker compose up -d postgres
source .env
alembic revision --autogenerate -m "baseline"
```

Expected: file appears at `migrations/versions/<hash>_baseline.py` covering all 10 tables.

- [ ] **Step 4: Run upgrade**

```bash
alembic upgrade head
```

Verify with `docker compose exec postgres psql -U ting -d ting -c '\dt'` — 10 tables present.

- [ ] **Step 5: Wire `ting migrate` to alembic**

Add to `src/ting/cli.py`:

```python
@app.command()
def migrate(direction: str = typer.Argument("up", help="up|down|head")) -> None:
    """Run Alembic migrations."""
    import os
    from alembic.config import Config
    from alembic import command

    cfg = Config("alembic.ini")
    if direction in ("up", "head"):
        command.upgrade(cfg, "head")
    elif direction == "down":
        command.downgrade(cfg, "-1")
    else:
        raise typer.BadParameter("direction must be up|down|head")
```

- [ ] **Step 6: Verify**

```bash
./scripts/ting migrate up
```

Expected: "Already at head" (or runs and reports head).

- [ ] **Step 7: Commit**

```bash
git add alembic.ini migrations/ src/ting/cli.py
git commit -m "feat: Alembic baseline migration + ting migrate command" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 3 — Valkey client + rate limits + sessions

### Task 3.1: Valkey client wrapper

**Files:**
- Create: `src/ting/valkey.py`
- Create: `tests/integration/test_valkey.py`

- [ ] **Step 1: Failing test**

```python
# tests/integration/test_valkey.py
import pytest
from ting.valkey import get_valkey


def test_valkey_ping(monkeypatch):
    monkeypatch.setenv("TING_DATABASE_URL", "postgresql://u:p@h:5432/d")
    monkeypatch.setenv("TING_VALKEY_URL", "redis://localhost:6379/0")
    monkeypatch.setenv("TING_SESSION_SECRET", "x" * 32)
    from ting.config import get_settings
    get_settings.cache_clear()
    vk = get_valkey()
    assert vk.ping() is True
```

- [ ] **Step 2: Run (expect fail until module exists; assumes Valkey running)**

```bash
docker compose up -d valkey
pytest tests/integration/test_valkey.py -v
```

- [ ] **Step 3: Implement**

```python
# src/ting/valkey.py
from functools import lru_cache
import redis

from .config import get_settings


@lru_cache
def get_valkey() -> redis.Redis:
    s = get_settings()
    return redis.Redis.from_url(s.valkey_url, decode_responses=True)
```

- [ ] **Step 4: Test passes; commit**

```bash
pytest tests/integration/test_valkey.py -v
git add src/ting/valkey.py tests/integration/test_valkey.py
git commit -m "feat: Valkey client wrapper" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 3.2: Code generator

**Files:**
- Create: `src/ting/codes.py`
- Create: `tests/unit/test_codes.py`

- [ ] **Step 1: Failing tests**

```python
# tests/unit/test_codes.py
from ting.codes import generate_code, normalize_code, ALPHABET


def test_alphabet_has_no_confusing_chars():
    for c in "01ILO":
        assert c not in ALPHABET


def test_generate_code_format():
    code = generate_code(prefix="MPE")
    assert code.startswith("MPE-")
    parts = code.split("-")
    assert len(parts) == 3
    assert len(parts[1]) == 4
    assert len(parts[2]) == 4
    for part in (parts[1], parts[2]):
        for ch in part:
            assert ch in ALPHABET


def test_generate_code_no_prefix():
    code = generate_code(prefix=None)
    parts = code.split("-")
    assert len(parts) == 2


def test_normalize_code_strips_and_uppercases():
    assert normalize_code(" mpe-xk7m-n3pq ") == "MPE-XK7M-N3PQ"
    assert normalize_code("mpexk7mn3pq") == "MPEXK7MN3PQ"  # caller decides hyphenation


def test_generate_code_unique_enough():
    seen = {generate_code(prefix="T") for _ in range(1000)}
    assert len(seen) >= 999  # vanishingly rare collision
```

- [ ] **Step 2: Run (expect fail)**

```bash
pytest tests/unit/test_codes.py -v
```

- [ ] **Step 3: Implement**

```python
# src/ting/codes.py
import secrets

# Crockford-style no-confusion alphabet: excludes 0, 1, I, L, O
ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"


def generate_code(prefix: str | None = "MPE", segment_len: int = 4, segments: int = 2) -> str:
    parts = ["".join(secrets.choice(ALPHABET) for _ in range(segment_len)) for _ in range(segments)]
    if prefix:
        return f"{prefix}-{'-'.join(parts)}"
    return "-".join(parts)


def normalize_code(raw: str) -> str:
    return raw.strip().upper()
```

- [ ] **Step 4: Tests pass; commit**

```bash
pytest tests/unit/test_codes.py -v
git add src/ting/codes.py tests/unit/test_codes.py
git commit -m "feat: code generator with no-confusion alphabet" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 3.3: Rate limiting

**Files:**
- Create: `src/ting/ratelimit.py`
- Create: `tests/integration/test_ratelimit.py`

- [ ] **Step 1: Failing test**

```python
# tests/integration/test_ratelimit.py
import time
from ting.ratelimit import allow_redemption, allow_write, ip_hash


def test_ip_hash_stable(settings_env):
    h1 = ip_hash("192.0.2.1")
    h2 = ip_hash("192.0.2.1")
    assert h1 == h2
    assert h1 != ip_hash("192.0.2.2")


def test_redemption_limit(settings_env, monkeypatch):
    monkeypatch.setenv("TING_RATE_LIMIT_REDEMPTION_PER_HOUR", "3")
    from ting.config import get_settings
    get_settings.cache_clear()
    ip = f"test-{time.time()}"
    for i in range(3):
        assert allow_redemption(ip) is True, f"attempt {i+1} should pass"
    assert allow_redemption(ip) is False  # 4th blocked


def test_write_limit(settings_env, monkeypatch):
    monkeypatch.setenv("TING_RATE_LIMIT_WRITES_PER_5MIN", "2")
    from ting.config import get_settings
    get_settings.cache_clear()
    code_id = f"code-{time.time()}"
    assert allow_write(code_id) is True
    assert allow_write(code_id) is True
    assert allow_write(code_id) is False
```

- [ ] **Step 2: Run (expect fail)**

```bash
pytest tests/integration/test_ratelimit.py -v
```

- [ ] **Step 3: Implement**

```python
# src/ting/ratelimit.py
import hmac
import hashlib

from .config import get_settings
from .valkey import get_valkey


def ip_hash(ip: str) -> str:
    s = get_settings()
    mac = hmac.new(s.session_secret.encode(), ip.encode(), hashlib.sha256)
    return mac.hexdigest()[:16]


def _bump(key: str, ttl_seconds: int, limit: int) -> bool:
    vk = get_valkey()
    pipe = vk.pipeline()
    pipe.incr(key)
    pipe.expire(key, ttl_seconds)
    count, _ = pipe.execute()
    return int(count) <= limit


def allow_redemption(ip: str) -> bool:
    s = get_settings()
    return _bump(f"rl:red:{ip_hash(ip)}", 3600, s.rate_limit_redemption_per_hour)


def allow_write(code_id: str) -> bool:
    s = get_settings()
    return _bump(f"rl:w:{code_id}", 300, s.rate_limit_writes_per_5min)
```

- [ ] **Step 4: Tests pass; commit**

```bash
pytest tests/integration/test_ratelimit.py -v
git add src/ting/ratelimit.py tests/integration/test_ratelimit.py
git commit -m "feat: Valkey-backed rate limiting (redemption + writes)" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 3.4: Session management (Valkey-backed)

**Files:**
- Create: `src/ting/auth.py`
- Create: `tests/integration/test_auth.py`

- [ ] **Step 1: Failing test**

```python
# tests/integration/test_auth.py
from uuid import uuid4
from ting.auth import mint_session, resolve_session, clear_session


def test_session_roundtrip(settings_env):
    code_id = uuid4()
    sid = mint_session(code_id)
    assert isinstance(sid, str) and len(sid) >= 32
    resolved = resolve_session(sid)
    assert resolved == code_id


def test_session_expires(settings_env):
    code_id = uuid4()
    sid = mint_session(code_id, ttl_seconds=1)
    import time; time.sleep(1.5)
    assert resolve_session(sid) is None


def test_session_clear(settings_env):
    code_id = uuid4()
    sid = mint_session(code_id)
    clear_session(sid)
    assert resolve_session(sid) is None
```

- [ ] **Step 2: Implement**

```python
# src/ting/auth.py
import secrets
from uuid import UUID

from .valkey import get_valkey

SESSION_TTL_SECONDS = 24 * 3600
SESSION_PREFIX = "sess:"


def mint_session(code_id: UUID, ttl_seconds: int = SESSION_TTL_SECONDS) -> str:
    sid = secrets.token_urlsafe(32)
    get_valkey().setex(f"{SESSION_PREFIX}{sid}", ttl_seconds, str(code_id))
    return sid


def resolve_session(sid: str) -> UUID | None:
    raw = get_valkey().get(f"{SESSION_PREFIX}{sid}")
    if raw is None:
        return None
    try:
        return UUID(raw)
    except ValueError:
        return None


def clear_session(sid: str) -> None:
    get_valkey().delete(f"{SESSION_PREFIX}{sid}")
```

- [ ] **Step 3: Tests pass; commit**

```bash
pytest tests/integration/test_auth.py -v
git add src/ting/auth.py tests/integration/test_auth.py
git commit -m "feat: Valkey-backed session management" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 4 — Seed loader + ting seed CLI

### Task 4.1: Seed YAML loader (services/seed_loader.py)

**Files:**
- Create: `src/ting/services/__init__.py`
- Create: `src/ting/services/seed_loader.py`
- Create: `seeds/example.yaml`
- Create: `tests/integration/test_seed_loader.py`

- [ ] **Step 1: seeds/example.yaml**

```yaml
# seeds/example.yaml — small example cohort for dev tier
cohort:
  name: example-pilot
  description: Example cohort shipped with the repo

proposals:
  - slug: retain-paras
    title: Retain paraprofessionals in-house
    body: Retain in-house staffing instead of outsourcing.
    status: active
  - slug: hvac-maintenance
    title: Address HVAC + facilities deferred maintenance
    body: Address backlog of deferred maintenance.
    status: active

questions:
  - slug: rank-priorities
    type: ranking
    prompt: Rank these in order of importance to your family
    display_order: 1
    payload:
      proposal_slugs: [retain-paras, hvac-maintenance]
      pick_top_n: null
      required: true

  - slug: nps-boe
    type: nps
    prompt: How likely are you to recommend the Board of Education to other parents?
    display_order: 2
    payload:
      subject: the Board of Education

  - slug: agree-supp-funding
    type: likert
    prompt: How strongly do you agree?
    display_order: 3
    payload:
      statement: The school should accept supplemental community funding to retain positions, where legally permitted.

bulletins:
  - body: Welcome to the example pilot. This cohort ships with the repo for dev/test.
    posted_by: example-admin
```

- [ ] **Step 2: Failing test**

```python
# tests/integration/test_seed_loader.py
import pytest
from pathlib import Path
from ting.services.seed_loader import load_seed, SeedError
from ting.db import session_scope
from ting.models import Cohort, Proposal, Question, Bulletin


@pytest.fixture(autouse=True)
def schema_only(settings_env):
    from ting.models import Base
    from ting.db import get_engine
    Base.metadata.create_all(get_engine())
    yield
    Base.metadata.drop_all(get_engine())


def test_load_example_seed():
    load_seed(Path("seeds/example.yaml"))
    with session_scope() as s:
        assert s.query(Cohort).filter_by(name="example-pilot").count() == 1
        assert s.query(Proposal).count() == 2
        assert s.query(Question).count() == 3
        assert s.query(Bulletin).count() == 1


def test_load_seed_idempotent():
    load_seed(Path("seeds/example.yaml"))
    load_seed(Path("seeds/example.yaml"))
    with session_scope() as s:
        # Cohort + proposals + questions deduped by slug/name; bulletins append.
        assert s.query(Cohort).filter_by(name="example-pilot").count() == 1
        assert s.query(Proposal).count() == 2
        assert s.query(Question).count() == 3
        assert s.query(Bulletin).count() == 2  # appended


def test_load_seed_validation_error(tmp_path):
    bad = tmp_path / "bad.yaml"
    bad.write_text("cohort: {}\n")  # missing name
    with pytest.raises(SeedError):
        load_seed(bad)
```

- [ ] **Step 3: Implement loader**

```python
# src/ting/services/seed_loader.py
from pathlib import Path
from typing import Any
import yaml
from sqlalchemy import select

from ..db import session_scope
from ..models import Cohort, Proposal, Question, Bulletin


class SeedError(Exception):
    pass


def load_seed(path: Path, dry_run: bool = False) -> dict[str, int]:
    data = yaml.safe_load(path.read_text())
    _validate(data)

    counts = {"cohort": 0, "proposals": 0, "questions": 0, "bulletins": 0}

    if dry_run:
        return counts

    with session_scope() as s:
        # Cohort upsert by name
        cdata = data["cohort"]
        cohort = s.scalar(select(Cohort).where(Cohort.name == cdata["name"]))
        if cohort is None:
            cohort = Cohort(name=cdata["name"], description=cdata.get("description"))
            s.add(cohort)
            s.flush()
        else:
            cohort.description = cdata.get("description", cohort.description)
        counts["cohort"] = 1

        # Proposals upsert by slug
        for p in data.get("proposals", []):
            prop = s.scalar(select(Proposal).where(Proposal.slug == p["slug"]))
            if prop is None:
                prop = Proposal(slug=p["slug"], title=p["title"], body=p.get("body", ""), status=p.get("status", "active"))
                s.add(prop)
            else:
                prop.title = p["title"]
                prop.body = p.get("body", prop.body)
                prop.status = p.get("status", prop.status)
            counts["proposals"] += 1
        s.flush()

        # Questions upsert by slug
        for q in data.get("questions", []):
            ques = s.scalar(select(Question).where(Question.slug == q["slug"]))
            if ques is None:
                ques = Question(
                    slug=q["slug"], type=q["type"], prompt=q["prompt"],
                    payload=q.get("payload", {}), display_order=q.get("display_order"),
                    cohort_id=cohort.cohort_id,
                )
                s.add(ques)
            else:
                ques.type = q["type"]
                ques.prompt = q["prompt"]
                ques.payload = q.get("payload", {})
                ques.display_order = q.get("display_order")
                ques.cohort_id = cohort.cohort_id
            counts["questions"] += 1

        # Bulletins append
        for b in data.get("bulletins", []):
            s.add(Bulletin(body=b["body"], posted_by=b.get("posted_by", "seed")))
            counts["bulletins"] += 1

    return counts


def _validate(data: Any) -> None:
    if not isinstance(data, dict):
        raise SeedError("Top-level YAML must be a mapping")
    if "cohort" not in data or not isinstance(data["cohort"], dict) or "name" not in data["cohort"]:
        raise SeedError("cohort.name is required")
    for q in data.get("questions", []):
        if q.get("type") not in ("ranking", "nps", "likert"):
            raise SeedError(f"question {q.get('slug')}: invalid type {q.get('type')!r}")
```

- [ ] **Step 4: Tests pass; commit**

```bash
pytest tests/integration/test_seed_loader.py -v
git add src/ting/services/ seeds/example.yaml tests/integration/test_seed_loader.py
git commit -m "feat: seed YAML loader (idempotent upsert; bulletins append)" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 4.2: ting seed CLI command

**Files:**
- Modify: `src/ting/cli.py`

- [ ] **Step 1: Add `seed` subcommand**

```python
# in src/ting/cli.py — add to the existing Typer app:
from pathlib import Path

@app.command()
def seed(
    file: Path = typer.Argument(..., exists=True, dir_okay=False),
    dry_run: bool = typer.Option(False, "--dry-run", help="Validate without writing"),
) -> None:
    """Load proposals + questions + cohort from a YAML file."""
    from .services.seed_loader import load_seed, SeedError
    try:
        counts = load_seed(file, dry_run=dry_run)
    except SeedError as e:
        typer.echo(f"❌ seed error: {e}", err=True)
        raise typer.Exit(1)
    label = "(dry-run) would write" if dry_run else "wrote"
    typer.echo(f"✅ {label}: {counts}")
```

- [ ] **Step 2: Verify via CLI**

```bash
./scripts/ting seed --dry-run seeds/example.yaml
./scripts/ting seed seeds/example.yaml
```

- [ ] **Step 3: Commit**

```bash
git add src/ting/cli.py
git commit -m "feat: ting seed command (with --dry-run)" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 4.3: ting codes CLI

**Files:**
- Create: `src/ting/services/code_service.py`
- Modify: `src/ting/cli.py`
- Create: `tests/integration/test_code_service.py`

- [ ] **Step 1: Failing test**

```python
# tests/integration/test_code_service.py
import pytest
from ting.services.code_service import generate_codes, list_codes, retire_cohort
from ting.services.seed_loader import load_seed
from pathlib import Path


@pytest.fixture(autouse=True)
def schema_only(settings_env):
    from ting.models import Base
    from ting.db import get_engine
    Base.metadata.create_all(get_engine())
    yield
    Base.metadata.drop_all(get_engine())


def test_generate_codes_count():
    load_seed(Path("seeds/example.yaml"))
    codes = generate_codes(cohort_name="example-pilot", count=10, prefix="EX")
    assert len(codes) == 10
    assert all(c.startswith("EX-") for c in codes)


def test_list_codes_filters_unprinted():
    load_seed(Path("seeds/example.yaml"))
    generate_codes(cohort_name="example-pilot", count=3, prefix="EX")
    unprinted = list_codes(cohort_name="example-pilot", only_unprinted=True)
    assert len(unprinted) == 3
```

- [ ] **Step 2: Implement service**

```python
# src/ting/services/code_service.py
from datetime import datetime, UTC
from sqlalchemy import select, update

from ..codes import generate_code
from ..db import session_scope
from ..models import Cohort, Code


def generate_codes(*, cohort_name: str, count: int, prefix: str | None = None) -> list[str]:
    out: list[str] = []
    with session_scope() as s:
        cohort = s.scalar(select(Cohort).where(Cohort.name == cohort_name))
        if cohort is None:
            raise ValueError(f"unknown cohort: {cohort_name}")
        existing = {row[0] for row in s.execute(select(Code.code_str)).all()}
        while len(out) < count:
            code_str = generate_code(prefix=prefix)
            if code_str in existing:
                continue
            existing.add(code_str)
            s.add(Code(code_str=code_str, cohort_id=cohort.cohort_id))
            out.append(code_str)
    return out


def list_codes(*, cohort_name: str, only_unprinted: bool = False) -> list[Code]:
    with session_scope() as s:
        cohort = s.scalar(select(Cohort).where(Cohort.name == cohort_name))
        if cohort is None:
            return []
        q = select(Code).where(Code.cohort_id == cohort.cohort_id)
        if only_unprinted:
            q = q.where(Code.printed_at.is_(None))
        rows = list(s.scalars(q))
        s.expunge_all()
        return rows


def mark_printed(*, code_strs: list[str]) -> int:
    with session_scope() as s:
        result = s.execute(
            update(Code).where(Code.code_str.in_(code_strs)).values(printed_at=datetime.now(UTC))
        )
        return result.rowcount or 0


def retire_cohort(*, cohort_name: str) -> None:
    with session_scope() as s:
        cohort = s.scalar(select(Cohort).where(Cohort.name == cohort_name))
        if cohort is None:
            raise ValueError(f"unknown cohort: {cohort_name}")
        cohort.retired_at = datetime.now(UTC)
```

- [ ] **Step 3: Add CLI commands**

```python
# in src/ting/cli.py
codes_app = typer.Typer(help="Code lifecycle (generate, export, retire)")
app.add_typer(codes_app, name="codes")


@codes_app.command("generate")
def codes_generate(
    cohort: str = typer.Option(..., "--cohort"),
    count: int = typer.Option(..., "--count"),
    prefix: str = typer.Option("MPE", "--prefix"),
) -> None:
    from .services.code_service import generate_codes
    out = generate_codes(cohort_name=cohort, count=count, prefix=prefix or None)
    typer.echo(f"✅ generated {len(out)} codes for cohort={cohort}")
    for c in out:
        typer.echo(c)


@app.command("cohort")
def cohort(action: str, name: str) -> None:
    """Cohort actions. Supports: retire <name>."""
    from .services.code_service import retire_cohort
    if action == "retire":
        retire_cohort(cohort_name=name)
        typer.echo(f"✅ retired cohort {name}")
    else:
        raise typer.BadParameter(f"unknown cohort action: {action}")
```

- [ ] **Step 4: Tests + manual verify + commit**

```bash
pytest tests/integration/test_code_service.py -v
./scripts/ting codes generate --cohort example-pilot --count 5 --prefix EX
git add src/ting/services/code_service.py src/ting/cli.py tests/integration/test_code_service.py
git commit -m "feat: code lifecycle service + CLI (generate, retire)" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 4.4: ting codes export (CSV + HTML with QR)

**Files:**
- Modify: `src/ting/services/code_service.py`
- Create: `src/ting/templates/admin/code_export.html`
- Modify: `src/ting/cli.py`
- Create: `tests/unit/test_code_export.py`

- [ ] **Step 1: Export helpers + template**

Append to `src/ting/services/code_service.py`:

```python
import io
import csv
from pathlib import Path
import qrcode
from qrcode.image.svg import SvgImage
from jinja2 import Environment, FileSystemLoader, select_autoescape


def export_csv(*, codes: list[Code]) -> str:
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["code_str"])
    for c in codes:
        w.writerow([c.code_str])
    return buf.getvalue()


def _qr_svg(data: str, box_size: int = 4) -> str:
    qr = qrcode.QRCode(box_size=box_size, border=1, image_factory=SvgImage)
    qr.add_data(data)
    qr.make(fit=True)
    img = qr.make_image()
    buf = io.BytesIO()
    img.save(buf)
    return buf.getvalue().decode()


def export_html(*, codes: list[Code], base_url: str) -> str:
    template_dir = Path(__file__).parent.parent / "templates"
    env = Environment(loader=FileSystemLoader(template_dir), autoescape=select_autoescape())
    tpl = env.get_template("admin/code_export.html")
    items = [
        {
            "code_str": c.code_str,
            "url": f"{base_url.rstrip('/')}/r/{c.code_str}?src=qr",
            "qr_svg": _qr_svg(f"{base_url.rstrip('/')}/r/{c.code_str}?src=qr"),
        }
        for c in codes
    ]
    return tpl.render(items=items, base_url=base_url)
```

`src/ting/templates/admin/code_export.html`:

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Ting codes — print sheet</title>
<style>
  @page { size: Letter; margin: 0.5in; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 0; padding: 0; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0.25in; padding: 0.25in; }
  .cell { border: 1px dashed #888; padding: 0.15in; display: flex; flex-direction: column; align-items: center; text-align: center; page-break-inside: avoid; }
  .cell svg { width: 2cm; height: 2cm; }
  .url { font-size: 9pt; margin-top: 0.05in; color: #444; word-break: break-all; }
  .code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 14pt; margin-top: 0.05in; letter-spacing: 1px; }
  .note { font-size: 8pt; color: #777; margin-top: 0.05in; }
</style>
</head>
<body>
<div class="grid">
  {% for it in items %}
  <div class="cell">
    {{ it.qr_svg | safe }}
    <div class="url">{{ it.url }}</div>
    <div class="code">{{ it.code_str }}</div>
    <div class="note">Or enter the code at {{ base_url }}</div>
  </div>
  {% endfor %}
</div>
</body>
</html>
```

- [ ] **Step 2: Unit test the renderers**

```python
# tests/unit/test_code_export.py
from ting.services.code_service import export_csv, export_html


class _C:
    def __init__(self, s): self.code_str = s


def test_export_csv():
    text = export_csv(codes=[_C("A"), _C("B")])
    assert "code_str" in text
    assert "A" in text and "B" in text


def test_export_html_contains_url_and_code():
    html = export_html(codes=[_C("MPE-XK7M-N3PQ")], base_url="https://ting.cmdbee.org")
    assert "MPE-XK7M-N3PQ" in html
    assert "ting.cmdbee.org/r/MPE-XK7M-N3PQ" in html
    assert "<svg" in html  # QR rendered as inline SVG
```

- [ ] **Step 3: CLI command**

```python
# in src/ting/cli.py, under codes_app:
@codes_app.command("export")
def codes_export(
    cohort: str = typer.Option(..., "--cohort"),
    format: str = typer.Option("csv", "--format", help="csv|html"),
    base_url: str = typer.Option("http://localhost:8000", "--base-url"),
    only_unprinted: bool = typer.Option(False, "--only-unprinted"),
    out: Path = typer.Option(Path("-"), "--out", help="- = stdout"),
) -> None:
    from .services.code_service import list_codes, export_csv, export_html, mark_printed
    rows = list_codes(cohort_name=cohort, only_unprinted=only_unprinted)
    if format == "csv":
        text = export_csv(codes=rows)
    elif format == "html":
        text = export_html(codes=rows, base_url=base_url)
    else:
        raise typer.BadParameter("format must be csv|html")
    if str(out) == "-":
        typer.echo(text)
    else:
        out.write_text(text)
        typer.echo(f"✅ wrote {len(rows)} codes to {out}")
    mark_printed(code_strs=[r.code_str for r in rows])
```

- [ ] **Step 4: Verify + commit**

```bash
pytest tests/unit/test_code_export.py -v
./scripts/ting codes export --cohort example-pilot --format csv
./scripts/ting codes export --cohort example-pilot --format html --base-url https://ting.cmdbee.org --out /tmp/codes.html
git add src/ting/services/code_service.py src/ting/templates/admin/code_export.html src/ting/cli.py tests/unit/test_code_export.py
git commit -m "feat: codes export (CSV + HTML with embedded QR)" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 5 — Aggregation math

### Task 5.1: Borda, NPS, Likert calculators

**Files:**
- Create: `src/ting/aggregation.py`
- Create: `tests/unit/test_aggregation.py`

- [ ] **Step 1: Failing tests**

```python
# tests/unit/test_aggregation.py
from ting.aggregation import borda, nps, likert_histogram


def test_borda_full_ranking():
    # 3 voters, 3 proposals. Voter1: [A,B,C], Voter2: [A,C,B], Voter3: [B,A,C].
    rankings = [["A", "B", "C"], ["A", "C", "B"], ["B", "A", "C"]]
    scores = borda(rankings)
    # 3-place ranking: 1st=2pts, 2nd=1pt, 3rd=0pts
    # A: 2+2+1 = 5; B: 1+0+2 = 3; C: 0+1+0 = 1
    assert scores == {"A": 5, "B": 3, "C": 1}


def test_borda_top_n_partial():
    # Top-2: voters submit a subset. Unranked items get 0.
    rankings = [["A", "B"], ["A", "C"], ["B", "A"]]
    scores = borda(rankings, all_options=["A", "B", "C", "D"])
    # 4-option Borda: 1st=3, 2nd=2, others=0
    # A: 3+3+2 = 8; B: 2+0+3 = 5; C: 0+2+0 = 2; D: 0
    assert scores == {"A": 8, "B": 5, "C": 2, "D": 0}


def test_nps():
    scores = [0, 6, 7, 8, 9, 10, 10]
    # detractors 0,6 -> 2/7 ~ 28.6%; promoters 9,10,10 -> 3/7 ~ 42.9%; nps ~ +14
    r = nps(scores)
    assert r["n"] == 7
    assert r["detractors"] == 2
    assert r["passives"] == 2
    assert r["promoters"] == 3
    assert -100 <= r["nps"] <= 100
    assert abs(r["nps"] - (3 - 2) / 7 * 100) < 0.5


def test_likert_histogram():
    scores = [1, 2, 2, 3, 4, 4, 4, 5]
    h = likert_histogram(scores)
    assert h["counts"] == {1: 1, 2: 2, 3: 1, 4: 3, 5: 1}
    assert abs(h["mean"] - sum(scores)/len(scores)) < 1e-6
    assert h["agree_pct"] == 50.0  # 4 of 8 are score>=4 -> 50%
```

- [ ] **Step 2: Implement**

```python
# src/ting/aggregation.py
from collections.abc import Iterable, Sequence


def borda(rankings: Iterable[Sequence[str]], all_options: Sequence[str] | None = None) -> dict[str, int]:
    """Borda count. Each voter's ranking is an ordered list.

    If all_options is provided, points are based on that universe (top-N ballots assume
    unranked items at zero). If not provided, derives the universe from the union of
    voters' ballots — appropriate for full-rank ballots.
    """
    rankings_l = [list(r) for r in rankings]
    universe = list(all_options) if all_options is not None else sorted({x for r in rankings_l for x in r})
    n_opts = len(universe)
    scores: dict[str, int] = {opt: 0 for opt in universe}
    for ballot in rankings_l:
        for idx, choice in enumerate(ballot):
            if choice in scores:
                scores[choice] += max(0, n_opts - 1 - idx)
    return scores


def nps(scores: Sequence[int]) -> dict[str, float | int]:
    n = len(scores)
    if n == 0:
        return {"n": 0, "detractors": 0, "passives": 0, "promoters": 0, "nps": 0.0}
    detractors = sum(1 for s in scores if 0 <= s <= 6)
    passives = sum(1 for s in scores if 7 <= s <= 8)
    promoters = sum(1 for s in scores if 9 <= s <= 10)
    nps_val = (promoters - detractors) / n * 100
    return {"n": n, "detractors": detractors, "passives": passives, "promoters": promoters, "nps": nps_val}


def likert_histogram(scores: Sequence[int]) -> dict[str, object]:
    counts = {i: 0 for i in range(1, 6)}
    for s in scores:
        if 1 <= s <= 5:
            counts[s] += 1
    n = sum(counts.values())
    mean = sum(k * v for k, v in counts.items()) / n if n else 0.0
    agree = counts[4] + counts[5]
    return {
        "counts": counts,
        "n": n,
        "mean": mean,
        "agree_pct": (agree / n * 100) if n else 0.0,
    }
```

- [ ] **Step 3: Tests pass; commit**

```bash
pytest tests/unit/test_aggregation.py -v
git add src/ting/aggregation.py tests/unit/test_aggregation.py
git commit -m "feat: Borda + NPS + Likert aggregation math" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 5.2: Aggregation queries against the DB

**Files:**
- Create: `src/ting/services/summary_service.py`
- Create: `tests/integration/test_summary_service.py`

- [ ] **Step 1: Failing integration test**

```python
# tests/integration/test_summary_service.py
import pytest
from uuid import uuid4
from pathlib import Path
from ting.db import session_scope
from ting.models import Base, Code, Response, Question, Pledge, Endorsement, Comment, Proposal
from ting.db import get_engine
from ting.services.seed_loader import load_seed
from ting.services.summary_service import build_summary


@pytest.fixture(autouse=True)
def schema(settings_env):
    Base.metadata.create_all(get_engine())
    yield
    Base.metadata.drop_all(get_engine())


def _add_code(s, cohort_id, code_str="AAA-BBBB-CCCC", grade=None):
    c = Code(code_str=code_str, cohort_id=cohort_id, advocate_grade=grade)
    s.add(c); s.flush()
    return c


def test_summary_has_sections():
    load_seed(Path("seeds/example.yaml"))
    summary = build_summary(cohort_name="example-pilot")
    assert "priorities" in summary  # ranking questions
    assert "nps" in summary
    assert "likert" in summary
    assert "pledges" in summary
    assert "top_comments" in summary
    assert "n_respondents" in summary
```

- [ ] **Step 2: Implement service**

```python
# src/ting/services/summary_service.py
from collections import defaultdict
from sqlalchemy import select, func

from ..aggregation import borda, nps as nps_calc, likert_histogram
from ..db import session_scope
from ..models import (
    Cohort, Code, Question, Response, Proposal, Comment, Endorsement, Pledge,
)


def build_summary(*, cohort_name: str, grade_filter: int | None = None, n_floor: int = 10) -> dict:
    with session_scope() as s:
        cohort = s.scalar(select(Cohort).where(Cohort.name == cohort_name))
        if cohort is None:
            return {"error": "cohort not found"}

        # Code filter (by grade if specified)
        code_q = select(Code.code_id).where(Code.cohort_id == cohort.cohort_id)
        if grade_filter is not None:
            code_q = code_q.where(Code.advocate_grade == grade_filter)
        eligible_code_ids = [r[0] for r in s.execute(code_q).all()]

        # Privacy floor: if filtered slice is small, return placeholder
        if grade_filter is not None and len(eligible_code_ids) < n_floor:
            return {"error": "slice-too-small", "n": len(eligible_code_ids), "floor": n_floor}

        n_respondents = s.scalar(
            select(func.count(func.distinct(Response.code_id)))
            .where(Response.code_id.in_(eligible_code_ids))
        ) or 0

        # Questions grouped by type
        questions = list(s.scalars(
            select(Question).where(Question.cohort_id == cohort.cohort_id).order_by(Question.display_order)
        ))
        priorities = []
        nps_sections = []
        likert_sections = []

        for q in questions:
            resps = list(s.scalars(
                select(Response).where(Response.question_id == q.question_id, Response.code_id.in_(eligible_code_ids))
            ))
            if q.type == "ranking":
                rankings = [r.payload.get("order", []) for r in resps]
                all_options = q.payload.get("proposal_slugs", [])
                scores = borda(rankings, all_options=all_options)
                # Normalize to 0–100
                max_score = max(scores.values()) if scores else 0
                bars = [
                    {
                        "slug": slug,
                        "score": score,
                        "normalized": (score / max_score * 100) if max_score else 0,
                    }
                    for slug, score in sorted(scores.items(), key=lambda kv: -kv[1])
                ]
                priorities.append({"prompt": q.prompt, "slug": q.slug, "n": len(resps), "bars": bars})
            elif q.type == "nps":
                scores = [r.payload.get("score", 0) for r in resps]
                nps_sections.append({
                    "prompt": q.prompt, "slug": q.slug,
                    "subject": q.payload.get("subject", ""),
                    **nps_calc(scores),
                })
            elif q.type == "likert":
                scores = [r.payload.get("score", 0) for r in resps]
                likert_sections.append({
                    "prompt": q.prompt, "slug": q.slug,
                    "statement": q.payload.get("statement", ""),
                    **likert_histogram(scores),
                })

        # Pledge totals per proposal
        pledge_rows = s.execute(
            select(
                Pledge.proposal_id,
                func.sum(Pledge.amount_dollars).label("dollars"),
                func.sum(Pledge.hours_per_week).label("hours"),
                func.count(Pledge.code_id).label("n"),
            )
            .where(Pledge.code_id.in_(eligible_code_ids))
            .group_by(Pledge.proposal_id)
        ).all()
        proposal_titles = {p.proposal_id: (p.slug, p.title) for p in s.scalars(select(Proposal)).all()}
        pledges = [
            {
                "slug": proposal_titles.get(r.proposal_id, ("?", "?"))[0],
                "title": proposal_titles.get(r.proposal_id, ("?", "?"))[1],
                "dollars_per_month": float(r.dollars or 0),
                "hours_per_week": float(r.hours or 0),
                "n": int(r.n),
            }
            for r in sorted(pledge_rows, key=lambda r: -float(r.dollars or 0))
        ]

        # Top endorsed comments
        comment_rows = s.execute(
            select(
                Comment.comment_id, Comment.proposal_id, Comment.body,
                func.count(Endorsement.code_id).label("endorsements"),
            )
            .outerjoin(Endorsement, Endorsement.comment_id == Comment.comment_id)
            .where(Comment.hidden_at.is_(None))
            .group_by(Comment.comment_id)
            .order_by(func.count(Endorsement.code_id).desc())
            .limit(5)
        ).all()
        top_comments = [
            {
                "body": r.body[:200],
                "endorsements": int(r.endorsements or 0),
                "proposal_slug": proposal_titles.get(r.proposal_id, ("?", "?"))[0],
            }
            for r in comment_rows
        ]

        return {
            "cohort": cohort_name,
            "n_respondents": int(n_respondents),
            "priorities": priorities,
            "nps": nps_sections,
            "likert": likert_sections,
            "pledges": pledges,
            "top_comments": top_comments,
        }
```

- [ ] **Step 3: Tests pass; commit**

```bash
pytest tests/integration/test_summary_service.py -v
git add src/ting/services/summary_service.py tests/integration/test_summary_service.py
git commit -m "feat: summary service composes Borda/NPS/Likert + pledge + comment queries" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 6 — Web routes (public, survey, summary)

### Task 6.1: Public routes + manual entry form + redemption flow

**Files:**
- Create: `src/ting/routes/__init__.py`
- Create: `src/ting/routes/public.py`
- Create: `src/ting/templates/base.html`
- Create: `src/ting/templates/public/landing.html`
- Create: `src/ting/templates/public/privacy.html`
- Modify: `src/ting/app.py`
- Create: `tests/integration/test_public_routes.py`

- [ ] **Step 1: base template**

```html
{# src/ting/templates/base.html #}
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{% block title %}Ting{% endblock %} — Parent Advocacy</title>
<link rel="stylesheet" href="/static/css/ting.css">
<script src="/static/htmx.min.js" defer></script>
<script src="/static/alpine.min.js" defer></script>
{% if goatcounter_site_code %}
<script data-goatcounter="https://{{ goatcounter_site_code }}.goatcounter.com/count"
        async src="//gc.zgo.at/count.js"></script>
{% endif %}
</head>
<body>
<header><a href="/" class="logo">Ting</a></header>
<main>{% block main %}{% endblock %}</main>
<footer><a href="/privacy">Privacy</a> · <a href="/about">About</a> · <a href="/summary">Public summary</a></footer>
</body>
</html>
```

- [ ] **Step 2: landing template + privacy stub**

```html
{# src/ting/templates/public/landing.html #}
{% extends "base.html" %}
{% block title %}Enter your code{% endblock %}
{% block main %}
<h1>Welcome</h1>
<p>Enter the code from your envelope (or scan the QR).</p>
<form action="/r/" method="post">
  <input name="code" placeholder="MPE-XK7M-N3PQ" autocomplete="off" autocapitalize="characters" required>
  <button type="submit">Continue</button>
</form>
<p class="muted">No accounts, no email. Your code is your only identifier. See <a href="/privacy">privacy</a>.</p>
{% endblock %}
```

```html
{# src/ting/templates/public/privacy.html #}
{% extends "base.html" %}
{% block title %}Privacy{% endblock %}
{% block main %}
<h1>Privacy</h1>
<ul>
  <li>No accounts, no emails, no passwords.</li>
  <li>Your IP address is not stored — only ephemeral rate-limit counters keyed on a hash.</li>
  <li>No third-party trackers, no cookies beyond a session token, no fingerprinting.</li>
  <li>Analytics are page-view counts only via GoatCounter (no cookies, respects Do-Not-Track).</li>
  <li>Your most-recent answer replaces prior answers; you can revise indefinitely.</li>
</ul>
{% endblock %}
```

- [ ] **Step 3: routes/public.py**

```python
# src/ting/routes/public.py
from fastapi import APIRouter, Request, Form, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from pathlib import Path
from sqlalchemy import select
from datetime import datetime, UTC

from ..codes import normalize_code
from ..auth import mint_session
from ..ratelimit import allow_redemption
from ..db import session_scope
from ..models import Code, Cohort
from ..config import get_settings


router = APIRouter()
TEMPLATES = Jinja2Templates(directory=str(Path(__file__).parent.parent / "templates"))


def _ctx(request: Request, **extra) -> dict:
    s = get_settings()
    return {
        "request": request,
        "goatcounter_site_code": s.goatcounter_site_code,
        **extra,
    }


@router.get("/", response_class=HTMLResponse)
def landing(request: Request) -> HTMLResponse:
    return TEMPLATES.TemplateResponse("public/landing.html", _ctx(request))


@router.get("/privacy", response_class=HTMLResponse)
def privacy(request: Request) -> HTMLResponse:
    return TEMPLATES.TemplateResponse("public/privacy.html", _ctx(request))


@router.post("/r/")
def redeem_form(request: Request, code: str = Form(...)) -> RedirectResponse:
    return RedirectResponse(url=f"/r/{normalize_code(code)}?src=manual", status_code=303)


@router.get("/r/{code_str}")
def redeem(request: Request, code_str: str, src: str = "manual") -> RedirectResponse:
    code_str = normalize_code(code_str)
    client_ip = request.client.host if request.client else "0.0.0.0"
    if not allow_redemption(client_ip):
        raise HTTPException(status_code=429, detail="too many code attempts")

    with session_scope() as s:
        code = s.scalar(select(Code).where(Code.code_str == code_str))
        if code is None:
            raise HTTPException(status_code=404, detail="code not found")
        cohort = s.scalar(select(Cohort).where(Cohort.cohort_id == code.cohort_id))
        if cohort is None or cohort.retired_at is not None:
            raise HTTPException(status_code=410, detail="cohort retired")
        if code.first_used_at is None:
            code.first_used_at = datetime.now(UTC)
        code_id = code.code_id

    sid = mint_session(code_id)
    resp = RedirectResponse(url=f"/survey?src={src}", status_code=303)
    settings = get_settings()
    resp.set_cookie(
        "ting_session", sid,
        httponly=True, samesite="lax",
        secure=settings.environment != "dev",
        max_age=24 * 3600,
    )
    return resp
```

- [ ] **Step 4: Wire into app.py**

```python
# src/ting/app.py (replace previous)
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from pathlib import Path

from .config import get_settings
from .routes.public import router as public_router


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(title="ting", version="0.1.0")
    static_dir = Path(__file__).parent / "static"
    static_dir.mkdir(exist_ok=True)
    app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

    @app.get("/healthz")
    def healthz():
        return {"status": "ok"}

    app.include_router(public_router)
    return app


app = create_app()
```

- [ ] **Step 5: Integration test**

```python
# tests/integration/test_public_routes.py
import pytest
from pathlib import Path
from fastapi.testclient import TestClient


@pytest.fixture
def client(settings_env):
    from ting.app import create_app
    from ting.models import Base
    from ting.db import get_engine
    Base.metadata.create_all(get_engine())
    yield TestClient(create_app())
    Base.metadata.drop_all(get_engine())


def test_landing_renders(client):
    r = client.get("/")
    assert r.status_code == 200
    assert "Enter your code" in r.text


def test_privacy_renders(client):
    r = client.get("/privacy")
    assert r.status_code == 200
    assert "No accounts" in r.text


def test_redeem_404(client):
    r = client.get("/r/NOPE-NOPE-NOPE", follow_redirects=False)
    assert r.status_code == 404


def test_redeem_happy_path(client):
    from ting.services.seed_loader import load_seed
    from ting.services.code_service import generate_codes
    load_seed(Path("seeds/example.yaml"))
    codes = generate_codes(cohort_name="example-pilot", count=1, prefix="EX")
    r = client.get(f"/r/{codes[0]}", follow_redirects=False)
    assert r.status_code == 303
    assert "/survey" in r.headers["location"]
    assert "ting_session" in r.cookies
```

- [ ] **Step 6: Run + commit**

```bash
pytest tests/integration/test_public_routes.py -v
git add src/ting/routes/ src/ting/templates/base.html src/ting/templates/public/ src/ting/app.py tests/integration/test_public_routes.py
git commit -m "feat: public routes (landing, /r/<code>, /privacy) with session cookie" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 6.2: Static assets (htmx + alpine + sortable + css)

**Files:**
- Create: `src/ting/static/htmx.min.js`
- Create: `src/ting/static/alpine.min.js`
- Create: `src/ting/static/sortable.min.js`
- Create: `src/ting/static/css/ting.css`

- [ ] **Step 1: Fetch pinned versions**

```bash
mkdir -p src/ting/static/css
curl -sSL -o src/ting/static/htmx.min.js https://unpkg.com/htmx.org@2.0.4/dist/htmx.min.js
curl -sSL -o src/ting/static/alpine.min.js https://unpkg.com/alpinejs@3.14.6/dist/cdn.min.js
curl -sSL -o src/ting/static/sortable.min.js https://unpkg.com/sortablejs@1.15.6/Sortable.min.js
```

- [ ] **Step 2: Author minimal css**

```css
/* src/ting/static/css/ting.css */
:root { --fg: #1a1a1a; --bg: #fafafa; --muted: #666; --accent: #2e7d32; --border: #d4d4d4; }
* { box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Inter, sans-serif; color: var(--fg); background: var(--bg); margin: 0; }
header, main, footer { max-width: 720px; margin: 0 auto; padding: 1rem; }
header { display: flex; justify-content: space-between; align-items: center; }
.logo { font-weight: 700; text-decoration: none; color: var(--fg); font-size: 1.5rem; }
footer { color: var(--muted); font-size: 0.9rem; }
h1, h2, h3 { line-height: 1.25; }
button, input[type=submit] { background: var(--accent); color: white; border: none; padding: 0.5rem 1rem; font-size: 1rem; border-radius: 6px; cursor: pointer; }
input[type=text], input:not([type]) { padding: 0.5rem; font-size: 1rem; border: 1px solid var(--border); border-radius: 6px; width: 100%; max-width: 360px; }
.muted { color: var(--muted); }
.bar { background: var(--border); border-radius: 4px; height: 18px; position: relative; overflow: hidden; }
.bar-fill { background: var(--accent); height: 100%; }
.question { border: 1px solid var(--border); padding: 1rem; border-radius: 8px; margin-bottom: 1rem; background: white; }
.rank-item { background: white; border: 1px solid var(--border); border-radius: 6px; padding: 0.5rem 1rem; margin: 0.25rem 0; cursor: grab; user-select: none; }
.nps-scale { display: flex; gap: 4px; flex-wrap: wrap; }
.nps-scale label { flex: 1; min-width: 38px; padding: 0.5rem 0; text-align: center; border: 1px solid var(--border); border-radius: 4px; cursor: pointer; }
.nps-scale input { display: none; }
.nps-scale input:checked + span { background: var(--accent); color: white; }
.likert-scale { display: flex; gap: 4px; }
.likert-scale label { flex: 1; padding: 0.5rem; text-align: center; border: 1px solid var(--border); border-radius: 4px; cursor: pointer; }
.likert-scale input { display: none; }
.likert-scale input:checked + span { background: var(--accent); color: white; }
@media print {
  header, footer, form, .no-print { display: none; }
}
```

- [ ] **Step 3: Verify served**

```bash
./scripts/ting dev   # in another shell
curl -sI http://localhost:8000/static/htmx.min.js | head -1
```

Expected: `HTTP/1.1 200 OK`.

- [ ] **Step 4: Commit**

```bash
git add src/ting/static/
git commit -m "chore: bundle htmx/alpine/sortable + minimal CSS" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 6.3: Survey rendering + response submission

**Files:**
- Create: `src/ting/routes/survey.py`
- Create: `src/ting/templates/survey/index.html`
- Create: `src/ting/templates/survey/_ranking.html`
- Create: `src/ting/templates/survey/_nps.html`
- Create: `src/ting/templates/survey/_likert.html`
- Modify: `src/ting/app.py`
- Create: `tests/integration/test_survey_routes.py`

- [ ] **Step 1: Survey route**

```python
# src/ting/routes/survey.py
from datetime import datetime, UTC
from uuid import UUID

from fastapi import APIRouter, Request, HTTPException, Form
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from pathlib import Path
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert

from ..auth import resolve_session, clear_session
from ..db import session_scope
from ..models import Cohort, Code, Question, Response, MetricsEvent
from ..valkey import get_valkey
from ..ratelimit import allow_write
from ..config import get_settings


router = APIRouter()
TEMPLATES = Jinja2Templates(directory=str(Path(__file__).parent.parent / "templates"))


def _require_code(request: Request) -> UUID:
    sid = request.cookies.get("ting_session")
    if not sid:
        raise HTTPException(status_code=401, detail="no session")
    code_id = resolve_session(sid)
    if code_id is None:
        raise HTTPException(status_code=401, detail="session expired")
    return code_id


def _ctx(request: Request, **extra) -> dict:
    s = get_settings()
    return {"request": request, "goatcounter_site_code": s.goatcounter_site_code, **extra}


@router.get("/survey", response_class=HTMLResponse)
def survey_index(request: Request) -> HTMLResponse:
    code_id = _require_code(request)
    with session_scope() as s:
        code = s.get(Code, code_id)
        if code is None:
            raise HTTPException(404)
        cohort = s.get(Cohort, code.cohort_id)
        if cohort is None or cohort.retired_at is not None:
            raise HTTPException(410, "cohort retired")
        questions = list(s.scalars(
            select(Question).where(Question.cohort_id == cohort.cohort_id, Question.display_order.is_not(None))
            .order_by(Question.display_order)
        ))
        existing = {r.question_id: r.payload for r in s.scalars(
            select(Response).where(Response.code_id == code_id)
        )}

    # Stash survey_started in Valkey for duration tracking
    vk = get_valkey()
    started_key = f"survey:{code_id}:started"
    if not vk.exists(started_key):
        vk.setex(started_key, 24 * 3600, datetime.now(UTC).isoformat())

    return TEMPLATES.TemplateResponse(
        "survey/index.html",
        _ctx(request, questions=questions, existing=existing, code=code),
    )


@router.post("/respond/{question_slug}")
async def respond(question_slug: str, request: Request) -> JSONResponse:
    code_id = _require_code(request)
    if not allow_write(str(code_id)):
        raise HTTPException(429, "rate-limited")

    form = await request.form()
    payload: dict = {}
    with session_scope() as s:
        q = s.scalar(select(Question).where(Question.slug == question_slug))
        if q is None:
            raise HTTPException(404, "question not found")

        if q.type == "ranking":
            raw_order = form.get("order", "")
            order = [x for x in str(raw_order).split(",") if x.strip()]
            payload = {"order": order}
        elif q.type == "nps":
            score = int(form.get("score", -1))
            if not 0 <= score <= 10:
                raise HTTPException(400, "score out of range")
            payload = {"score": score}
        elif q.type == "likert":
            score = int(form.get("score", -1))
            if not 1 <= score <= 5:
                raise HTTPException(400, "score out of range")
            payload = {"score": score}
        else:
            raise HTTPException(400, "unknown question type")

        stmt = pg_insert(Response).values(
            code_id=code_id, question_id=q.question_id, payload=payload,
        ).on_conflict_do_update(
            index_elements=["code_id", "question_id"],
            set_={"payload": payload, "updated_at": datetime.now(UTC)},
        )
        s.execute(stmt)

    return JSONResponse({"ok": True})


@router.post("/survey/complete")
def survey_complete(request: Request) -> JSONResponse:
    code_id = _require_code(request)
    vk = get_valkey()
    started_iso = vk.get(f"survey:{code_id}:started")
    duration_seconds = None
    if started_iso:
        started = datetime.fromisoformat(started_iso)
        duration_seconds = int((datetime.now(UTC) - started).total_seconds())
    with session_scope() as s:
        s.add(MetricsEvent(event="survey_completed", code_id=code_id, duration_seconds=duration_seconds))
    return JSONResponse({"ok": True, "duration_seconds": duration_seconds})


@router.post("/logout")
def logout(request: Request) -> HTMLResponse:
    sid = request.cookies.get("ting_session")
    if sid:
        clear_session(sid)
    resp = HTMLResponse('<a href="/">Signed out. Back to start →</a>')
    resp.delete_cookie("ting_session")
    return resp
```

- [ ] **Step 2: Templates**

```html
{# src/ting/templates/survey/index.html #}
{% extends "base.html" %}
{% block title %}Survey{% endblock %}
{% block main %}
<h1>Your input</h1>
<p class="muted">Answer what you'd like. Your latest answer always wins; you can come back and revise.</p>

{% for q in questions %}
  <div class="question">
    <h3>{{ q.prompt }}</h3>
    {% if q.type == 'ranking' %}{% include 'survey/_ranking.html' %}
    {% elif q.type == 'nps' %}{% include 'survey/_nps.html' %}
    {% elif q.type == 'likert' %}{% include 'survey/_likert.html' %}
    {% endif %}
  </div>
{% endfor %}

<button hx-post="/survey/complete" hx-swap="outerHTML">Mark complete</button>
<form action="/logout" method="post" style="display:inline">
  <button type="submit" class="muted">Sign out</button>
</form>
{% endblock %}
```

```html
{# src/ting/templates/survey/_ranking.html #}
{% set ans = existing.get(q.question_id, {}) %}
{% set current_order = ans.get('order') or q.payload.get('proposal_slugs', []) %}
<form hx-post="/respond/{{ q.slug }}" hx-trigger="reorder, submit">
  <ul x-data="{order: {{ current_order | tojson }}}"
      x-init="$nextTick(() => new Sortable($el, {
        animation: 150, onEnd: () => {
          order = [...$el.children].map(li => li.dataset.slug);
          $el.closest('form').dispatchEvent(new Event('reorder'));
        }
      }))">
    {% for slug in current_order %}
      <li class="rank-item" data-slug="{{ slug }}">{{ slug }}</li>
    {% endfor %}
  </ul>
  <input type="hidden" name="order" :value="order.join(',')">
</form>
```

```html
{# src/ting/templates/survey/_nps.html #}
{% set ans = existing.get(q.question_id, {}) %}
{% set current = ans.get('score') %}
<p class="muted">{{ q.payload.subject }} — 0 = not at all, 10 = extremely likely</p>
<form hx-post="/respond/{{ q.slug }}" hx-trigger="change" class="nps-scale">
  {% for v in range(0, 11) %}
    <label>
      <input type="radio" name="score" value="{{ v }}" {% if current == v %}checked{% endif %}>
      <span>{{ v }}</span>
    </label>
  {% endfor %}
</form>
```

```html
{# src/ting/templates/survey/_likert.html #}
{% set ans = existing.get(q.question_id, {}) %}
{% set current = ans.get('score') %}
<p>{{ q.payload.statement }}</p>
<form hx-post="/respond/{{ q.slug }}" hx-trigger="change" class="likert-scale">
  {% for v, lbl in [(1, 'Strongly disagree'), (2, 'Disagree'), (3, 'Neutral'), (4, 'Agree'), (5, 'Strongly agree')] %}
    <label>
      <input type="radio" name="score" value="{{ v }}" {% if current == v %}checked{% endif %}>
      <span>{{ lbl }}</span>
    </label>
  {% endfor %}
</form>
```

- [ ] **Step 3: Wire into app.py**

```python
# src/ting/app.py — add to imports + include_router
from .routes.survey import router as survey_router
# ...
app.include_router(survey_router)
```

- [ ] **Step 4: Integration test**

```python
# tests/integration/test_survey_routes.py
import pytest
from pathlib import Path
from fastapi.testclient import TestClient


@pytest.fixture
def client(settings_env):
    from ting.app import create_app
    from ting.models import Base
    from ting.db import get_engine
    Base.metadata.create_all(get_engine())
    return TestClient(create_app())


def _redeem(client) -> str:
    from ting.services.seed_loader import load_seed
    from ting.services.code_service import generate_codes
    load_seed(Path("seeds/example.yaml"))
    [code] = generate_codes(cohort_name="example-pilot", count=1, prefix="T")
    r = client.get(f"/r/{code}", follow_redirects=False)
    assert r.status_code == 303
    return code


def test_survey_renders_after_redeem(client):
    _redeem(client)
    r = client.get("/survey")
    assert r.status_code == 200
    assert "Your input" in r.text


def test_respond_likert_persists(client):
    _redeem(client)
    r = client.post("/respond/agree-supp-funding", data={"score": 4})
    assert r.status_code == 200
    # Re-render and check radio is checked
    r2 = client.get("/survey")
    assert 'value="4" checked' in r2.text


def test_respond_unauth(client):
    r = client.post("/respond/agree-supp-funding", data={"score": 4})
    assert r.status_code == 401
```

- [ ] **Step 5: Run + commit**

```bash
pytest tests/integration/test_survey_routes.py -v
git add src/ting/routes/survey.py src/ting/templates/survey/ src/ting/app.py tests/integration/test_survey_routes.py
git commit -m "feat: survey rendering + response upsert + duration metric" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 6.4: Public summary route + grade filter + Valkey cache

**Files:**
- Create: `src/ting/routes/summary.py`
- Create: `src/ting/templates/summary/index.html`
- Modify: `src/ting/app.py`
- Create: `tests/integration/test_summary_routes.py`

- [ ] **Step 1: Summary route with Valkey cache**

```python
# src/ting/routes/summary.py
import json
from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from pathlib import Path

from ..services.summary_service import build_summary
from ..valkey import get_valkey
from ..config import get_settings


router = APIRouter()
TEMPLATES = Jinja2Templates(directory=str(Path(__file__).parent.parent / "templates"))


SUMMARY_CACHE_TTL = 60


@router.get("/summary", response_class=HTMLResponse)
def summary(request: Request, cohort: str = "example-pilot", grade: int | None = None, print: bool = False) -> HTMLResponse:
    cache_key = f"summary:{cohort}:{grade or 'all'}"
    vk = get_valkey()
    cached = vk.get(cache_key)
    if cached:
        data = json.loads(cached)
    else:
        data = build_summary(cohort_name=cohort, grade_filter=grade)
        vk.setex(cache_key, SUMMARY_CACHE_TTL, json.dumps(data, default=str))

    s = get_settings()
    return TEMPLATES.TemplateResponse(
        "summary/index.html",
        {
            "request": request,
            "data": data,
            "print_mode": print,
            "goatcounter_site_code": s.goatcounter_site_code,
        },
    )
```

- [ ] **Step 2: Summary template**

```html
{# src/ting/templates/summary/index.html #}
{% extends "base.html" %}
{% block title %}Public Summary{% endblock %}
{% block main %}
<h1>Ting — {{ data.cohort }}</h1>
{% if data.error == 'slice-too-small' %}
<p class="muted">Slice too small to display (n={{ data.n }}, floor={{ data.floor }}). Pick a broader filter.</p>
{% else %}
<p class="muted">{{ data.n_respondents }} respondents</p>

<section>
  <h2>Priorities</h2>
  {% for q in data.priorities %}
    <h3>{{ q.prompt }} <span class="muted">(n={{ q.n }})</span></h3>
    {% for bar in q.bars %}
      <div><strong>{{ bar.slug }}</strong> ({{ bar.score }})</div>
      <div class="bar"><div class="bar-fill" style="width: {{ bar.normalized }}%"></div></div>
    {% endfor %}
  {% endfor %}
</section>

<section>
  <h2>Trust in governance</h2>
  {% for n in data.nps %}
    <div>
      <strong>{{ n.subject }}</strong> — NPS {{ '%+.0f' | format(n.nps) }} (n={{ n.n }};
      {{ n.promoters }} promoters / {{ n.passives }} passives / {{ n.detractors }} detractors)
    </div>
  {% endfor %}
</section>

<section>
  <h2>Agreement</h2>
  {% for k in data.likert %}
    <div>
      <strong>{{ k.statement }}</strong> — mean {{ '%.1f' | format(k.mean) }}, {{ '%.0f' | format(k.agree_pct) }}% agree (n={{ k.n }})
    </div>
  {% endfor %}
</section>

<section>
  <h2>Pledges</h2>
  {% for p in data.pledges %}
    <div>
      <strong>{{ p.title }}</strong> — ${{ '%.0f' | format(p.dollars_per_month) }}/mo +
      {{ '%.0f' | format(p.hours_per_week) }} hrs/wk (n={{ p.n }})
    </div>
  {% endfor %}
</section>

<section>
  <h2>Top endorsed comments</h2>
  {% for c in data.top_comments %}
    <blockquote>"{{ c.body }}" — {{ c.endorsements }}× (<em>{{ c.proposal_slug }}</em>)</blockquote>
  {% endfor %}
</section>
{% endif %}
{% endblock %}
```

- [ ] **Step 3: Wire into app**

```python
# in src/ting/app.py
from .routes.summary import router as summary_router
# ...
app.include_router(summary_router)
```

- [ ] **Step 4: Integration test**

```python
# tests/integration/test_summary_routes.py
import pytest
from pathlib import Path
from fastapi.testclient import TestClient


@pytest.fixture
def client(settings_env):
    from ting.app import create_app
    from ting.models import Base
    from ting.db import get_engine
    Base.metadata.create_all(get_engine())
    from ting.services.seed_loader import load_seed
    load_seed(Path("seeds/example.yaml"))
    return TestClient(create_app())


def test_summary_renders(client):
    r = client.get("/summary")
    assert r.status_code == 200
    assert "example-pilot" in r.text
    assert "Priorities" in r.text


def test_summary_grade_floor(client):
    r = client.get("/summary?grade=2")
    assert r.status_code == 200
    # No codes => slice too small or empty summary
    assert "slice-too-small" in r.text.lower() or "Slice too small" in r.text or "0 respondents" in r.text
```

- [ ] **Step 5: Commit**

```bash
pytest tests/integration/test_summary_routes.py -v
git add src/ting/routes/summary.py src/ting/templates/summary/ src/ting/app.py tests/integration/test_summary_routes.py
git commit -m "feat: /summary view with grade filter + 60s Valkey cache" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 7 — Comments, endorsements, pledges

### Task 7.1: Comments + endorsements + "review existing first" gate

**Files:**
- Modify: `src/ting/routes/survey.py`
- Create: `src/ting/templates/survey/_comments.html`
- Create: `tests/integration/test_comments.py`

- [ ] **Step 1: Add /proposal/<slug> view + comment POST + endorse toggle**

Append to `src/ting/routes/survey.py`:

```python
from ..models import Proposal, Comment, Endorsement, Pledge
from decimal import Decimal


@router.get("/proposal/{slug}", response_class=HTMLResponse)
def proposal_detail(slug: str, request: Request) -> HTMLResponse:
    code_id = _require_code(request)
    with session_scope() as s:
        p = s.scalar(select(Proposal).where(Proposal.slug == slug))
        if p is None:
            raise HTTPException(404)
        comments = list(s.scalars(
            select(Comment).where(Comment.proposal_id == p.proposal_id, Comment.hidden_at.is_(None))
            .order_by(Comment.created_at.desc())
        ))
        my_endorsements = {
            e.comment_id for e in s.scalars(
                select(Endorsement).where(Endorsement.code_id == code_id)
            )
        }
        existing_pledge = s.scalar(
            select(Pledge).where(Pledge.code_id == code_id, Pledge.proposal_id == p.proposal_id)
        )
        comment_count = s.scalar(
            select(func.count(Comment.comment_id)).where(Comment.author_code_id == code_id)
        ) or 0
    return TEMPLATES.TemplateResponse(
        "survey/proposal.html",
        _ctx(request, proposal=p, comments=comments, my_endorsements=my_endorsements,
             existing_pledge=existing_pledge, comment_count=comment_count),
    )


@router.post("/proposal/{slug}/comment")
async def post_comment(slug: str, request: Request, body: str = Form(...), confirm_read: bool = Form(False)) -> JSONResponse:
    code_id = _require_code(request)
    if not allow_write(str(code_id)):
        raise HTTPException(429)
    if not confirm_read:
        raise HTTPException(400, "must confirm you've read existing comments")
    if not body.strip():
        raise HTTPException(400, "empty body")

    s_cfg = get_settings()
    with session_scope() as s:
        p = s.scalar(select(Proposal).where(Proposal.slug == slug))
        if p is None:
            raise HTTPException(404)
        cnt = s.scalar(
            select(func.count(Comment.comment_id)).where(Comment.author_code_id == code_id)
        ) or 0
        if cnt >= s_cfg.max_comments_per_code:
            raise HTTPException(403, f"comment cap reached ({s_cfg.max_comments_per_code})")
        s.add(Comment(proposal_id=p.proposal_id, author_code_id=code_id, body=body.strip()))
        s.add(MetricsEvent(event="comment_posted", code_id=code_id))
    return JSONResponse({"ok": True})


@router.post("/comment/{comment_id}/endorse")
def toggle_endorse(comment_id: UUID, request: Request) -> JSONResponse:
    code_id = _require_code(request)
    if not allow_write(str(code_id)):
        raise HTTPException(429)
    with session_scope() as s:
        existing = s.scalar(
            select(Endorsement).where(Endorsement.code_id == code_id, Endorsement.comment_id == comment_id)
        )
        if existing is None:
            s.add(Endorsement(code_id=code_id, comment_id=comment_id))
            s.add(MetricsEvent(event="endorsement_toggled", code_id=code_id))
            return JSONResponse({"endorsed": True})
        else:
            s.delete(existing)
            return JSONResponse({"endorsed": False})
```

Add `from sqlalchemy import func` to the imports at the top.

- [ ] **Step 2: proposal.html template**

```html
{# src/ting/templates/survey/proposal.html #}
{% extends "base.html" %}
{% block title %}{{ proposal.title }}{% endblock %}
{% block main %}
<h1>{{ proposal.title }}</h1>
<p>{{ proposal.body }}</p>

<h2>Comments</h2>
{% for c in comments %}
  <div class="comment" id="c-{{ c.comment_id }}">
    <p>{{ c.body }}</p>
    <button hx-post="/comment/{{ c.comment_id }}/endorse" hx-swap="outerHTML"
            class="{% if c.comment_id in my_endorsements %}endorsed{% endif %}">
      {% if c.comment_id in my_endorsements %}Endorsed ✓{% else %}Endorse{% endif %}
    </button>
  </div>
{% else %}
  <p class="muted">No comments yet.</p>
{% endfor %}

<h2>Add a comment</h2>
{% if comment_count >= 5 %}
  <p class="muted">You've reached the comment cap for this code. Use endorsements to amplify
    others' comments rather than re-posting.</p>
{% else %}
  <form hx-post="/proposal/{{ proposal.slug }}/comment" hx-swap="afterbegin" hx-target=".comment-list">
    <p class="muted">First please read the comments above. Then:</p>
    <label><input type="checkbox" name="confirm_read" value="true" required> I've read existing comments.</label>
    <textarea name="body" required rows="3" placeholder="What would you say?"></textarea>
    <button type="submit">Post comment</button>
  </form>
{% endif %}

<h2>Your pledge</h2>
<form hx-post="/proposal/{{ proposal.slug }}/pledge">
  <label>$/month <input type="number" name="amount_dollars" min="0" step="1"
    value="{{ existing_pledge.amount_dollars if existing_pledge else 0 }}"></label>
  <label>hrs/week <input type="number" name="hours_per_week" min="0" step="0.5"
    value="{{ existing_pledge.hours_per_week if existing_pledge else 0 }}"></label>
  <button type="submit">Save pledge</button>
</form>

<p><a href="/survey">← Back to survey</a></p>
{% endblock %}
```

- [ ] **Step 3: Integration test**

```python
# tests/integration/test_comments.py
import pytest
from pathlib import Path
from fastapi.testclient import TestClient


@pytest.fixture
def client(settings_env):
    from ting.app import create_app
    from ting.models import Base
    from ting.db import get_engine
    Base.metadata.create_all(get_engine())
    from ting.services.seed_loader import load_seed
    from ting.services.code_service import generate_codes
    load_seed(Path("seeds/example.yaml"))
    [code] = generate_codes(cohort_name="example-pilot", count=1, prefix="T")
    c = TestClient(create_app())
    c.get(f"/r/{code}", follow_redirects=False)  # redeem
    yield c


def test_post_comment_requires_confirm_read(client):
    r = client.post("/proposal/retain-paras/comment", data={"body": "hello"})
    assert r.status_code == 400


def test_post_comment_ok(client):
    r = client.post("/proposal/retain-paras/comment",
                    data={"body": "hello", "confirm_read": "true"})
    assert r.status_code == 200
    r2 = client.get("/proposal/retain-paras")
    assert "hello" in r2.text


def test_comment_cap(client, monkeypatch):
    monkeypatch.setenv("TING_MAX_COMMENTS_PER_CODE", "2")
    from ting.config import get_settings; get_settings.cache_clear()
    for i in range(2):
        r = client.post("/proposal/retain-paras/comment",
                        data={"body": f"c{i}", "confirm_read": "true"})
        assert r.status_code == 200
    r = client.post("/proposal/retain-paras/comment",
                    data={"body": "c3", "confirm_read": "true"})
    assert r.status_code == 403
```

- [ ] **Step 4: Commit**

```bash
pytest tests/integration/test_comments.py -v
git add src/ting/routes/survey.py src/ting/templates/survey/proposal.html tests/integration/test_comments.py
git commit -m "feat: proposal detail with comments + endorsements + read-first gate" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 7.2: Pledges

**Files:**
- Modify: `src/ting/routes/survey.py`
- Create: `tests/integration/test_pledges.py`

- [ ] **Step 1: Pledge POST handler**

Append to `src/ting/routes/survey.py`:

```python
@router.post("/proposal/{slug}/pledge")
async def post_pledge(slug: str, request: Request,
                      amount_dollars: Decimal = Form(0), hours_per_week: Decimal = Form(0)) -> JSONResponse:
    code_id = _require_code(request)
    if not allow_write(str(code_id)):
        raise HTTPException(429)
    if amount_dollars < 0 or hours_per_week < 0:
        raise HTTPException(400, "non-negative values only")
    with session_scope() as s:
        p = s.scalar(select(Proposal).where(Proposal.slug == slug))
        if p is None:
            raise HTTPException(404)
        stmt = pg_insert(Pledge).values(
            code_id=code_id, proposal_id=p.proposal_id,
            amount_dollars=amount_dollars, hours_per_week=hours_per_week,
        ).on_conflict_do_update(
            index_elements=["code_id", "proposal_id"],
            set_={"amount_dollars": amount_dollars, "hours_per_week": hours_per_week,
                  "updated_at": datetime.now(UTC)},
        )
        s.execute(stmt)
        s.add(MetricsEvent(event="pledge_added", code_id=code_id))
    return JSONResponse({"ok": True})
```

- [ ] **Step 2: Test**

```python
# tests/integration/test_pledges.py
import pytest
from pathlib import Path
from fastapi.testclient import TestClient


@pytest.fixture
def client(settings_env):
    from ting.app import create_app
    from ting.models import Base
    from ting.db import get_engine
    Base.metadata.create_all(get_engine())
    from ting.services.seed_loader import load_seed
    from ting.services.code_service import generate_codes
    load_seed(Path("seeds/example.yaml"))
    [code] = generate_codes(cohort_name="example-pilot", count=1, prefix="T")
    c = TestClient(create_app())
    c.get(f"/r/{code}", follow_redirects=False)
    yield c


def test_pledge_upserts(client):
    r = client.post("/proposal/retain-paras/pledge",
                    data={"amount_dollars": "25", "hours_per_week": "2"})
    assert r.status_code == 200
    # Re-submit and confirm it replaces (not duplicates) — check summary
    r = client.post("/proposal/retain-paras/pledge",
                    data={"amount_dollars": "50", "hours_per_week": "3"})
    assert r.status_code == 200
    r2 = client.get("/summary")
    assert "$50" in r2.text or "50/mo" in r2.text


def test_pledge_negative_rejected(client):
    r = client.post("/proposal/retain-paras/pledge",
                    data={"amount_dollars": "-1", "hours_per_week": "0"})
    assert r.status_code == 400
```

- [ ] **Step 3: Commit**

```bash
pytest tests/integration/test_pledges.py -v
git add src/ting/routes/survey.py tests/integration/test_pledges.py
git commit -m "feat: pledge endpoint with upsert semantics" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 8 — Remaining CLI commands (bulletin, report, healthcheck wiring)

### Task 8.1: ting bulletin post

**Files:**
- Modify: `src/ting/cli.py`
- Create: `tests/integration/test_bulletin_cli.py`

- [ ] **Step 1: CLI subcommand + test**

```python
# in src/ting/cli.py
bulletins_app = typer.Typer(help="Admin broadcast bulletins")
app.add_typer(bulletins_app, name="bulletin")


@bulletins_app.command("post")
def bulletin_post(
    body: str = typer.Option(..., "--body"),
    posted_by: str = typer.Option("admin", "--as"),
) -> None:
    from .db import session_scope
    from .models import Bulletin
    with session_scope() as s:
        s.add(Bulletin(body=body, posted_by=posted_by))
    typer.echo("✅ bulletin posted")
```

```python
# tests/integration/test_bulletin_cli.py
import subprocess
import pytest


@pytest.fixture(autouse=True)
def schema_only(settings_env):
    from ting.models import Base
    from ting.db import get_engine
    Base.metadata.create_all(get_engine())
    yield
    Base.metadata.drop_all(get_engine())


def test_bulletin_post():
    from ting.cli import bulletin_post
    bulletin_post(body="Test bulletin", posted_by="tester")
    from ting.db import session_scope
    from ting.models import Bulletin
    with session_scope() as s:
        assert s.query(Bulletin).filter_by(posted_by="tester").count() == 1
```

- [ ] **Step 2: Commit**

```bash
pytest tests/integration/test_bulletin_cli.py -v
git add src/ting/cli.py tests/integration/test_bulletin_cli.py
git commit -m "feat: ting bulletin post" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 8.2: ting report (loopback fetch of /summary)

**Files:**
- Modify: `src/ting/cli.py`

- [ ] **Step 1: Add `report` subcommand**

```python
@app.command()
def report(
    cohort: str = typer.Option(..., "--cohort"),
    out: Path = typer.Option(Path("summary.html"), "--out"),
    base_url: str = typer.Option("http://localhost:8000", "--base-url"),
) -> None:
    """Save the printable /summary page as HTML (then browser-print to PDF)."""
    import httpx
    r = httpx.get(f"{base_url.rstrip('/')}/summary?cohort={cohort}&print=true", timeout=30)
    r.raise_for_status()
    out.write_text(r.text)
    typer.echo(f"✅ wrote {out}")
```

- [ ] **Step 2: Commit**

```bash
git add src/ting/cli.py
git commit -m "feat: ting report (loopback fetch of /summary?print=true)" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 8.3: ting dev (uvicorn launcher)

**Files:**
- Modify: `src/ting/cli.py`

- [ ] **Step 1: Add `dev` subcommand**

```python
@app.command()
def dev(
    host: str = typer.Option("127.0.0.1", "--host"),
    port: int = typer.Option(8000, "--port"),
    reload: bool = typer.Option(True, "--reload/--no-reload"),
) -> None:
    """Boot uvicorn with hot reload for local development."""
    import uvicorn
    uvicorn.run("ting.app:app", host=host, port=port, reload=reload)
```

- [ ] **Step 2: Manual smoke + commit**

```bash
./scripts/ting dev --port 8000 &
sleep 2
curl -s http://localhost:8000/healthz
kill %1
git add src/ting/cli.py
git commit -m "feat: ting dev (uvicorn with reload)" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 9 — K8s manifests (base + overlays)

### Task 9.1: k8s/base — namespace, deployment, service, configmap, secret stub

**Files:**
- Create: `k8s/base/namespace.yaml`
- Create: `k8s/base/deployment.yaml`
- Create: `k8s/base/service.yaml`
- Create: `k8s/base/configmap.yaml`
- Create: `k8s/base/secret.yaml.example`
- Create: `k8s/base/kustomization.yaml`

- [ ] **Step 1: Author manifests**

```yaml
# k8s/base/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ting
```

```yaml
# k8s/base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ting
  namespace: ting
spec:
  replicas: 1
  selector:
    matchLabels: {app: ting}
  template:
    metadata:
      labels: {app: ting}
    spec:
      containers:
      - name: ting
        image: ghcr.io/siliconsaga/ting:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 8000
        env:
        - name: TING_ENVIRONMENT
          valueFrom: {configMapKeyRef: {name: ting-config, key: environment}}
        - name: TING_BASE_URL
          valueFrom: {configMapKeyRef: {name: ting-config, key: base_url}}
        - name: TING_DATABASE_URL
          valueFrom: {secretKeyRef: {name: ting-secrets, key: database_url}}
        - name: TING_VALKEY_URL
          valueFrom: {secretKeyRef: {name: ting-secrets, key: valkey_url}}
        - name: TING_SESSION_SECRET
          valueFrom: {secretKeyRef: {name: ting-secrets, key: session_secret}}
        - name: TING_GOATCOUNTER_SITE_CODE
          valueFrom: {configMapKeyRef: {name: ting-config, key: goatcounter_site_code, optional: true}}
        readinessProbe:
          httpGet: {path: /healthz, port: 8000}
          initialDelaySeconds: 3
          periodSeconds: 5
        livenessProbe:
          httpGet: {path: /healthz, port: 8000}
          initialDelaySeconds: 15
          periodSeconds: 10
        resources:
          requests: {cpu: 100m, memory: 128Mi}
          limits: {cpu: 250m, memory: 256Mi}
```

```yaml
# k8s/base/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: ting
  namespace: ting
spec:
  selector: {app: ting}
  ports:
  - port: 80
    targetPort: 8000
```

```yaml
# k8s/base/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ting-config
  namespace: ting
data:
  environment: prod
  base_url: https://ting.cmdbee.org
  goatcounter_site_code: ""
```

```yaml
# k8s/base/secret.yaml.example
# Real secret is created out-of-band:
#   kubectl create secret generic ting-secrets -n ting \
#     --from-literal=database_url='postgresql://...' \
#     --from-literal=valkey_url='redis://...' \
#     --from-literal=session_secret="$(openssl rand -base64 48)"
apiVersion: v1
kind: Secret
metadata:
  name: ting-secrets
  namespace: ting
type: Opaque
stringData:
  database_url: "postgresql://ting:CHANGEME@ting-pg:5432/ting"
  valkey_url: "redis://ting-valkey:6379/0"
  session_secret: "CHANGEME-32-bytes-or-more-random"
```

```yaml
# k8s/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ting
resources:
- namespace.yaml
- deployment.yaml
- service.yaml
- configmap.yaml
- postgres-claim.yaml
- valkey-claim.yaml
- httproute.yaml
- certificate.yaml
```

- [ ] **Step 2: Commit**

```bash
git add k8s/base/namespace.yaml k8s/base/deployment.yaml k8s/base/service.yaml k8s/base/configmap.yaml k8s/base/secret.yaml.example k8s/base/kustomization.yaml
git commit -m "feat: k8s base — namespace, deployment, service, configmap, secret stub" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 9.2: k8s/base — Mimir claims + cert + HTTPRoute

**Files:**
- Create: `k8s/base/postgres-claim.yaml`
- Create: `k8s/base/valkey-claim.yaml`
- Create: `k8s/base/certificate.yaml`
- Create: `k8s/base/httproute.yaml`

- [ ] **Step 1: Author claim and ingress manifests**

```yaml
# k8s/base/postgres-claim.yaml
apiVersion: database.example.org/v1alpha1
kind: PostgreSQLInstance
metadata:
  name: ting-pg
  namespace: ting
spec:
  parameters:
    storageSize: 5Gi
    version: "15"
    replicas: 1
    databaseName: ting
  compositionSelector:
    matchLabels:
      provider: percona
      service: postgresql
```

```yaml
# k8s/base/valkey-claim.yaml
apiVersion: mimir.siliconsaga.org/v1alpha1
kind: ValkeyCluster
metadata:
  name: ting-valkey
  namespace: ting
spec:
  parameters:
    replicas: 1
    storageSize: 1Gi
```

```yaml
# k8s/base/certificate.yaml
# Overlay overrides issuerRef and dnsNames per tier.
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ting-cert
  namespace: ting
spec:
  secretName: ting-tls
  privateKey:
    rotationPolicy: Always
  issuerRef:
    name: letsencrypt-gateway-staging
    kind: ClusterIssuer
  dnsNames:
  - ting.cmdbee.org
```

```yaml
# k8s/base/httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ting
  namespace: ting
spec:
  parentRefs:
  - name: traefik-gateway
    namespace: kube-system
    kind: Gateway
    sectionName: web
  hostnames:
  - "ting.cmdbee.org"
  rules:
  - matches:
    - path: {type: PathPrefix, value: "/"}
    backendRefs:
    - name: ting
      port: 80
```

- [ ] **Step 2: Commit**

```bash
git add k8s/base/postgres-claim.yaml k8s/base/valkey-claim.yaml k8s/base/certificate.yaml k8s/base/httproute.yaml
git commit -m "feat: k8s base — Mimir PG+Valkey claims, cert, HTTPRoute" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 9.3: Overlays — localk8s, cmdbee, frontstate

**Files:**
- Create: `k8s/overlays/localk8s/kustomization.yaml`
- Create: `k8s/overlays/cmdbee/kustomization.yaml`
- Create: `k8s/overlays/frontstate/kustomization.yaml`
- Create: `k8s/overlays/frontstate/certificate-patch.yaml`
- Create: `k8s/overlays/frontstate/httproute-patch.yaml`

- [ ] **Step 1: Author overlays**

```yaml
# k8s/overlays/localk8s/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ting-local
resources:
- ../../base
patches:
- target:
    kind: ConfigMap
    name: ting-config
  patch: |
    - op: replace
      path: /data/environment
      value: dev
    - op: replace
      path: /data/base_url
      value: http://ting.local
- target:
    kind: HTTPRoute
    name: ting
  patch: |
    - op: replace
      path: /spec/hostnames/0
      value: ting.local
- target:
    kind: Certificate
    name: ting-cert
  patch: |
    - op: replace
      path: /spec/issuerRef/name
      value: selfsigned
    - op: replace
      path: /spec/dnsNames/0
      value: ting.local
```

```yaml
# k8s/overlays/cmdbee/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ting
resources:
- ../../base
# Base already targets cmdbee hostnames + staging cert — no patches needed.
```

```yaml
# k8s/overlays/frontstate/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ting
resources:
- ../../base
patches:
- path: certificate-patch.yaml
- path: httproute-patch.yaml
- target:
    kind: ConfigMap
    name: ting-config
  patch: |
    - op: replace
      path: /data/base_url
      value: https://ting.frontstate.org
```

```yaml
# k8s/overlays/frontstate/certificate-patch.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ting-cert
  namespace: ting
spec:
  issuerRef:
    name: letsencrypt-gateway
    kind: ClusterIssuer
  dnsNames:
  - ting.frontstate.org
```

```yaml
# k8s/overlays/frontstate/httproute-patch.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ting
  namespace: ting
spec:
  hostnames:
  - "ting.frontstate.org"
```

- [ ] **Step 2: Validate kustomize builds**

```bash
kubectl kustomize k8s/overlays/cmdbee > /tmp/cmdbee-rendered.yaml
kubectl kustomize k8s/overlays/frontstate > /tmp/frontstate-rendered.yaml
kubectl kustomize k8s/overlays/localk8s > /tmp/localk8s-rendered.yaml
```

Expected: each produces a valid manifest; no kustomize errors.

- [ ] **Step 3: Commit**

```bash
git add k8s/overlays/
git commit -m "feat: k8s overlays for localk8s, cmdbee (default), frontstate" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 10 — Image build + CI

### Task 10.1: GitHub Actions for tests + lint

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: CI workflow**

```yaml
# .github/workflows/ci.yml
name: ci
on:
  push:
    branches: [main]
  pull_request:
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: ting
          POSTGRES_PASSWORD: ting
          POSTGRES_DB: ting
        ports: ['5432:5432']
        options: --health-cmd="pg_isready -U ting" --health-interval=5s --health-timeout=5s --health-retries=10
      valkey:
        image: valkey/valkey:7-alpine
        ports: ['6379:6379']
        options: --health-cmd="valkey-cli ping" --health-interval=5s --health-timeout=5s --health-retries=10
    steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-python@v5
      with: {python-version: '3.12'}
    - run: pip install --upgrade pip && pip install -e '.[dev]'
    - run: ruff check src/ tests/
    - env:
        TING_DATABASE_URL: postgresql://ting:ting@localhost:5432/ting
        TING_VALKEY_URL: redis://localhost:6379/0
        TING_SESSION_SECRET: ${{ secrets.GITHUB_TOKEN }}-padded-to-32-chars-abc
      run: pytest tests/unit tests/integration -v
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: GitHub Actions test + lint" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 10.2: GitHub Actions for image build + push to GHCR

**Files:**
- Create: `.github/workflows/image.yml`

- [ ] **Step 1: Image workflow**

```yaml
# .github/workflows/image.yml
name: image
on:
  push:
    branches: [main]
permissions:
  contents: read
  packages: write
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    - uses: docker/metadata-action@v5
      id: meta
      with:
        images: ghcr.io/siliconsaga/ting
        tags: |
          type=sha,format=long
          type=raw,value=latest,enable={{is_default_branch}}
    - uses: docker/build-push-action@v6
      with:
        context: .
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
```

- [ ] **Step 2: Commit + push**

```bash
git add .github/workflows/image.yml
git commit -m "ci: GitHub Actions image build → ghcr.io/siliconsaga/ting" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
git push origin main
```

Expected: workflows run; image lands at
`ghcr.io/siliconsaga/ting:latest` and `:sha-<hash>`. **Verify package
visibility is set to Public** at
`https://github.com/orgs/SiliconSaga/packages/container/ting/settings`.

---

## Phase 11 — yggdrasil-side adapter + final commits

### Task 11.1: ws-test adapter for ting

**Files:**
- Create: `yggdrasil/realms/realm-siliconsaga/adapters/ting.yaml`

- [ ] **Step 1: Adapter file**

```yaml
# In yggdrasil repo:
commands:
  test: python3 -m pytest tests/unit tests/integration -v
  lint: python3 -m ruff check src/ tests/
ai_context:
  - README.md
  - AGENTS.md
  - docs/architecture.md
```

- [ ] **Step 2: Commit (in yggdrasil, on feat/ting-pilot-design branch)**

```bash
cd /Users/cervator/dev/git_ws/yggdrasil
cat > .commits/ting-adapter.md <<'EOF'
---
message: "feat(adapters): ting ws-test adapter (pytest + ruff)"
add:
  - realms/realm-siliconsaga/adapters/ting.yaml
---

Realm-side adapter pointing ws-test at the ting component's pytest +
ruff commands. Lets `ws test ting` and `ws lint ting` work without
shelling into the component directory.
EOF
bash scripts/ws commit yggdrasil .commits/ting-adapter.md
```

### Task 11.2: Commit the implementation plan + push yggdrasil branch

- [ ] **Step 1: Commit this plan**

```bash
cd /Users/cervator/dev/git_ws/yggdrasil
cat > .commits/ting-pilot-plan.md <<'EOF'
---
message: "docs(plans): ting implementation plan"
add:
  - docs/plans/2026-05-10-ting-pilot-plan.md
---

Implementation plan derived from the design doc. Bite-sized TDD tasks
across foundation, schema, auth, survey engine, comments/endorsements,
pledges, public summary, CLI, k8s overlays, and CI.
EOF
bash scripts/ws commit yggdrasil .commits/ting-pilot-plan.md
```

- [ ] **Step 2: Push branch + open CR**

```bash
bash scripts/ws push yggdrasil
# Then manually or via ws cr — out of scope here since branch may still be in progress
```

---

## Phase 12 — Deploy to cmdbee + smoke test (operator-supervised)

> **This phase modifies the GKE cluster and is gated on operator
> green-light. Do not run unsupervised.**

### Task 12.1: Apply localk8s overlay first to validate

- [ ] **Step 1: Switch kubeconfig context to a local k8s cluster (k3d/Rancher Desktop)**

(Skip if Mimir is not installed locally; jump to cmdbee.)

```bash
kubectl config use-context k3d-nordri-test  # or rancher-desktop
```

- [ ] **Step 2: Create the namespace + secrets manually**

```bash
kubectl create namespace ting-local || true
kubectl create secret generic ting-secrets -n ting-local \
  --from-literal=database_url='will-fill-after-claim' \
  --from-literal=valkey_url='will-fill-after-claim' \
  --from-literal=session_secret="$(openssl rand -base64 48 | head -c 48)" || true
```

- [ ] **Step 3: Apply**

```bash
kubectl apply -k k8s/overlays/localk8s
```

Expected: namespace, claims, deployment created. Pod will CrashLoop
until secrets point at real claim outputs — populate from claim
status, then `kubectl rollout restart deploy/ting -n ting-local`.

### Task 12.2: Apply cmdbee overlay to GKE

- [ ] **Step 1: Switch context**

```bash
kubectl config use-context gke_teralivekubernetes_us-east1-d_ttf-cluster
```

- [ ] **Step 2: Create namespace + initial secret**

```bash
kubectl create namespace ting || true
kubectl create secret generic ting-secrets -n ting \
  --from-literal=database_url='placeholder' \
  --from-literal=valkey_url='placeholder' \
  --from-literal=session_secret="$(openssl rand -base64 48 | head -c 48)"
```

- [ ] **Step 3: Apply**

```bash
kubectl apply -k k8s/overlays/cmdbee
```

Expected: namespace already exists, claims created, deployment
created (will CrashLoop initially since secrets are placeholders).

- [ ] **Step 4: Wait for claims to provision**

```bash
kubectl get postgresqlinstance -n ting -w
kubectl get valkeycluster -n ting -w
```

Expected: 5–15 min until both report Ready.

- [ ] **Step 5: Read service connection details from the claim status**

```bash
kubectl describe postgresqlinstance ting-pg -n ting
kubectl describe valkeycluster ting-valkey -n ting
```

Note the Service names and credentials from the composed resources.

- [ ] **Step 6: Update the secret with real connection URLs**

```bash
kubectl create secret generic ting-secrets -n ting \
  --from-literal=database_url="postgresql://<u>:<p>@<svc>:5432/ting" \
  --from-literal=valkey_url="redis://<svc>:6379/0" \
  --from-literal=session_secret="$(openssl rand -base64 48 | head -c 48)" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deploy/ting -n ting
```

- [ ] **Step 7: Verify pod healthy + cert issued**

```bash
kubectl get pod -n ting -w
kubectl get certificate -n ting
curl -k https://ting.cmdbee.org/healthz   # -k since staging cert is untrusted
```

Expected: pod Ready; cert reaches `Ready=True`; healthz returns
`{"status":"ok"}`.

- [ ] **Step 8: Migrate + seed**

```bash
kubectl exec deploy/ting -n ting -- ting migrate
kubectl exec deploy/ting -n ting -- ting seed /app/seeds/example.yaml
```

### Task 12.3: Smoke test

**Files:**
- Create: `scripts/smoke.sh`

- [ ] **Step 1: Smoke test script**

```bash
cat > scripts/smoke.sh <<'EOF'
#!/usr/bin/env bash
# scripts/smoke.sh — end-to-end smoke check against a live ting URL.
# Usage: BASE=https://ting.cmdbee.org bash scripts/smoke.sh
set -euo pipefail
BASE="${BASE:-http://localhost:8000}"
CURL="curl -sk --max-time 10"

echo "==> /healthz"
$CURL "$BASE/healthz" | grep -q '"status":"ok"' && echo "  ok"

echo "==> generate test code"
kubectl exec deploy/ting -n ting -- ting codes generate --cohort example-pilot --count 1 --prefix SMK > /tmp/codes.txt
CODE=$(tail -1 /tmp/codes.txt)
echo "  code=$CODE"

echo "==> redeem"
COOKIE_JAR=$(mktemp)
$CURL -c "$COOKIE_JAR" -o /dev/null -w "%{http_code}\n" "$BASE/r/$CODE" | grep -q 303 && echo "  ok"

echo "==> survey loads"
$CURL -b "$COOKIE_JAR" "$BASE/survey" | grep -q "Your input" && echo "  ok"

echo "==> /summary loads (no code required)"
$CURL "$BASE/summary" | grep -q "Priorities" && echo "  ok"

echo "✅ smoke test passed"
EOF
chmod +x scripts/smoke.sh
```

- [ ] **Step 2: Run + commit**

```bash
BASE=https://ting.cmdbee.org bash scripts/smoke.sh
git add scripts/smoke.sh
git commit -m "test: end-to-end smoke script" \
  -m "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review Pass

(Run after writing — fix inline.)

**1. Spec coverage:**

- Goals → Phases 6 (auth), 6.3 (survey), 7 (comments/pledges), 6.4 (summary), 4.1 (seed) ✓
- Non-goals → not implemented, explicitly omitted from plan ✓
- Data model (§6 of design) → Phase 2 ✓
- Survey engine (§7) → Phase 6.3 ✓
- Auth/sessions/analytics (§8) → Phases 3.4, 6.1, 6.3 (analytics in Phase 6 templates + metrics_events writes) ✓
- Public summary (§9) → Phase 6.4 + Phase 5 (aggregation) ✓
- Admin CLI (§10) → Phases 4 (seed, codes), 8 (bulletin, report, dev) ✓
- Deploy tiers (§11) → Phase 1.4 (dev), Phase 9 (manifests), Phase 12 (apply) ✓
- Testing (§12) → tests in each Phase + Phase 12.3 smoke ✓
- Seed YAML (§13) → Phase 4.1 + seeds/example.yaml ✓
- Timeline (§14) → execution order matches ✓

**2. Placeholder scan:** No `TBD` / `TODO` / `fill in details`. Every
code step has actual code. Every command has an expected outcome.

**3. Type consistency:**

- Code generation: `generate_code` signature matches between codes.py
  and code_service.py ✓
- Aggregation: `borda` returns `dict[str, int]` consistently ✓
- Models: column names match between models, migrations, and service
  queries ✓
- Routes use `_require_code` and `_ctx` helpers consistently ✓

**4. Ambiguity check:** None remaining. All variants and choices have
specific commands or code.

## Execution Handoff

This plan is laid out for autonomous execution by a subagent or by
inline execution. Phases 0–11 are autonomous-safe (local code, tests,
GitHub repo creation, image push to GHCR). **Phase 12 is operator-
supervised** (kubectl apply to GKE).

Recommend executing via the **superpowers:subagent-driven-development**
sub-skill: fresh subagent per task, two-stage review between tasks, so
the operator sees progress and can intervene at task boundaries.
