# Ting — Parent Advocacy Pilot Design

**Status:** Approved (single-pass; implementation rolls directly from this doc)
**Drafted:** 2026-05-10
**Target PTA demo:** 2026-05-13 (Wed)
**Target backpack distribution:** 2026-05-22 (Fri)
**Target BoE meeting deliverable:** 2026-06-15 (Mon)
**Component repo (to be created):** `SiliconSaga/ting`
**Component path:** `components/ting/`

---

## 1. Summary

Ting is a structured-input parent-advocacy site for one school's worth of
families. The first piece of a longer platform vision sketched in
[`schools/next-year.md`](https://github.com/SiliconSaga/schools/blob/main/next-year.md);
deliberately scoped tight for a four-day POC so a working version can be
demonstrated at the May 13 PTA meeting and rolled to MPE families on May 22.

Codes printed in backpack envelopes are the entire authentication model. A
holder visits the site (URL on the envelope plus a QR), is bound to a session,
and can answer a survey (ranking, NPS, agree/disagree), endorse comments,
post a bounded number of new comments, and attach pledges of money or hours
to specific proposals. All responses are anonymous; no PII is collected.
A public summary view shows aggregated results and is the artifact taken to
the June 15 BoE meeting.

The name "ting" comes from Scandinavian assemblies (Althing); aliased on
DNS to `thing` and `althing` for flexibility.

## 2. Goals

- **Anonymous-but-verified input.** Real parents, no accounts, no PII.
- **Forced prioritization.** Ranking-style questions force trade-offs rather
  than the "everything is important" plateau of typical surveys.
- **Symmetric framing.** NPS-style trust questions cover all governance
  bodies (BoE, union, PTA, this site itself) — not adversarial.
- **One-page BoE deliverable.** Aggregate output fits on a printed page or
  tablet screen.
- **Privacy-first analytics.** GoatCounter (no cookies, no fingerprinting,
  respects DNT). No IP persistence.
- **Deployable by a fellow hobbyist.** Local dev requires Docker only — no
  homelab dependency. Production tiers ride existing workspace machinery.

## 3. Non-goals (deferred to iteration 2+)

- Account system / login / passwords
- Personalized board-side responses to individual codes
- Moderation tooling beyond admin soft-hide
- Identity proofing beyond the code itself
- Real-time updates / WebSockets
- Counter-offers as a first-class entity (deferred from public-page wording;
  may surface later as a comment subtype)
- Sentiment-over-time visualizations across cohorts
- WebSocket-driven live updates of `/summary`
- Admin web UI for proposal/question editing (YAML re-seed only for MVP;
  bulletin web post in iteration 1.5)
- Vouching mechanism for incident tracking
- OpenCollective hookup for pledged funds
- Generalized "Raised Topics platform" architecture
- Decidim / Pol.is / other civic-tech integrations

## 4. Context

### 4.1 The public page

The forward-looking framing lives in
[`SiliconSaga/schools` → `next-year.md`](https://github.com/SiliconSaga/schools/blob/main/next-year.md).
Key promises that ting must honor:

- Ranked, forced choices (covered by the ranking question type below)
- Endorsement over re-posting (covered by endorsable comments)
- Offered time and funds attached to positions (covered by pledges)
- The site is for *anyone with a code*, not just PTA members
- The site is not anti-board or anti-union — framed as aggregation, not
  opposition

The public page lists "counter-offers and alternatives" as a feature. The
MVP defers this to iteration 2; the public page should be updated to soften
that promise to "later iteration" after the 5/13 demo, not before.

### 4.2 Pivot from pairwise to survey

The thalamus design notes originally proposed pairwise A-vs-B comparisons.
During brainstorming this was pivoted to a structured *survey* model
(ranking, NPS, Likert) — closer to familiar UX (e.g. the WOPE budget
survey) and operationally simpler. Pairwise can return later as a
comparison-style question type if needed.

### 4.3 Political framing constraints

The platform must not be perceived as a PTA-only tool, anti-board, or
anti-union. The design captures this by:

- Requiring symmetric NPS coverage across BoE / union / PTA / this site
- Aggregating *for* board members rather than advocating *against* them
- Public summary view available without a code (transparency)

## 5. Architecture

Single FastAPI service, server-rendered with Jinja templates, deployed as
one Kubernetes Deployment behind Gateway API HTTPRoute. Postgres and Valkey
come from Mimir via Crossplane Claims. No SPA, no bundler — HTMX for
in-place updates, Alpine.js + SortableJS for the drag-to-rank widget.

```
                          ting.cmdbee.org (test) / ting.frontstate.org (prod)
                                 │
                     ┌───── Gateway API ─────┐
                     │   (HTTPRoute + TLS)   │
                     └───────────┬───────────┘
                                 │
                       ┌─────────▼─────────┐
                       │  ting (FastAPI)   │
                       │  Jinja + HTMX     │
                       │  + scripts/ting   │
                       └────┬────────┬─────┘
                            │        │
              PostgreSQLInstance      ValkeyCluster
              (Crossplane claim       (Crossplane claim
               via Percona)            via Mimir Valkey XRD)
                       └─── Mimir / Crossplane ───┘
```

Three deploy artifacts at the manifest layer:

- **Web pod** — FastAPI app, public-facing
- **PostgreSQLInstance claim** — `kind: PostgreSQLInstance`, `apiVersion: database.example.org/v1alpha1`
- **ValkeyCluster claim** — `kind: ValkeyCluster`, `apiVersion: mimir.siliconsaga.org/v1alpha1`

No worker process; no async queue. Cohort retire and report generation
run from the CLI as one-shot commands. If/when cron is needed (daily
cohort drift alerts, etc.), add a separate `Job` then.

## 6. Data model

PostgreSQL schema. Core design principle: enforce
one-response-per-code-per-thing as a DB-level uniqueness constraint, so
revisits naturally replace rather than stack. JSONB payloads for
type-flexible survey content.

```sql
cohorts          -- batches of codes (MPE-2026-spring-pilot, MPE-2026-fall, …)
  cohort_id pk, name unique, description, created_at, retired_at nullable

codes            -- auth tokens distributed in envelopes
  code_id pk, code_str unique, cohort_id fk,
  printed_at nullable, first_used_at nullable,
  advocate_grade smallint nullable  -- 0=K, 1=1st, …, 12=12th; set on first use

proposals        -- persistent advocacy items, survive cohort cycles
  proposal_id pk, slug unique, title, body, status, created_at

questions        -- survey questions per cohort
  question_id pk, slug, type (ranking | nps | likert),
  prompt text, payload jsonb, display_order int, cohort_id fk
  -- payload examples:
  --   ranking: { proposal_slugs: [...], pick_top_n: N | null, required: bool }
  --   nps:     { subject: "the BoE", required: bool }
  --   likert:  { statement: "…", required: bool }

responses        -- one per (code, question); UPDATE replaces
  code_id fk, question_id fk, payload jsonb, updated_at
  UNIQUE (code_id, question_id)

comments         -- free-text discussion on proposals
  comment_id pk, proposal_id fk, author_code_id fk,
  body text, created_at, hidden_at nullable  -- admin soft-hide

endorsements     -- one per (code, comment)
  PRIMARY KEY (code_id, comment_id), created_at

pledges          -- one per (code, proposal); UPDATE replaces
  PRIMARY KEY (code_id, proposal_id),
  amount_dollars numeric, hours_per_week numeric, updated_at

bulletins        -- admin broadcast posts
  bulletin_id pk, body text, posted_at, posted_by text

metrics_events   -- thin analytics table for server-side duration tracking
  event text, code_id fk, duration_seconds int nullable, recorded_at
```

### Design choices

- **JSONB payloads** for question/response data instead of wide per-type
  tables. Adding a new question type later is a code-only change.
- **Proposals persist across cohorts.** Only the questions asking about
  them are cohort-scoped.
- **`advocate_grade` on `codes`**, set on first redeem, locked thereafter.
  Simpler than self-identifying on every write; usable as a consistent
  slice for aggregate views.
- **No IP persistence.** Rate limit counters live in Valkey, keyed on
  `code_id` and a hashed-IP (HMAC-SHA256, 8 bytes), TTL'd. No row of
  identifying network metadata touches disk.
- **Comment caps enforced in app code**, not DB. Default
  `max_comments_per_code = 5` (configurable per cohort).
- **Immutable on cohort retire.** Setting `cohorts.retired_at` blocks
  writes against that cohort's codes but preserves all data. No DELETE
  statements in the MVP. Enables sentiment-over-time analysis later.
- **Comments use a "review existing first" gate**: when posting to a
  proposal, all existing comments on that proposal are shown sorted by
  endorsement count, with a required "I've read these" checkbox. No
  NLP-based similarity in MVP.

## 7. Survey engine

Three question types, each a triple of `(input UI widget, response
payload schema, aggregation function)`. Adding a fourth type later is a
code-only change.

### 7.1 Ranking

- **Input:** Mobile-friendly drag-to-rank list (Alpine.js + SortableJS,
  ~5KB). A "pick top N" variant constrains the answer to a top-N
  subset. Keyboard / accessibility fallback: numbered dropdowns.
- **Response payload:** `{ "order": [proposal_slug, proposal_slug, …] }`.
- **Aggregation:** Borda count (or first-place plurality + Borda for
  top-N). Display as horizontal bar chart; normalize to 0–100 so
  different ranking questions are visually comparable.

### 7.2 NPS

- **Input:** Horizontal 0–10 scale, labeled "Not at all likely / Extremely
  likely." Tap-target sized for thumb.
- **Response payload:** `{ "score": 0..10 }`.
- **Aggregation:** Standard NPS = `%promoters (9–10) − %detractors (0–6)`.
  Display as NPS number plus stacked-bar of promoters / passives /
  detractors plus response count.

### 7.3 Likert

- **Input:** 5-point scale (Strongly disagree / Disagree / Neutral /
  Agree / Strongly agree) as horizontal pill row of radio buttons.
- **Response payload:** `{ "score": 1..5 }`.
- **Aggregation:** Mean + histogram. Display as histogram plus
  one-line headline ("63% agree or strongly agree").

### 7.4 Cross-cutting

- **Single scrollable page** for the survey, not one-question-at-a-time
  wizards. Less precious UX, matches WOPE survey shape.
- **Per-question required vs optional** — `payload.required: true` blocks
  submit if unanswered. Default optional.
- **Resume in-progress** — session is keyed on code; navigating away and
  coming back picks up at the last save state. Every save is an upsert.
- **Order** by `questions.display_order`; admin reorders by editing the
  seed YAML and re-running `ting seed`.

## 8. Auth, sessions, and analytics

### 8.1 Code format

8 chars from a no-confusion alphabet (Crockford-ish: excludes `0/O/1/I/L`),
hyphenated 4-4 with an optional cohort prefix: `MPE-XK7M-N3PQ`. The
alphabet is 31 characters (`23456789ABCDEFGHJKMNPQRSTUVWXYZ` — digits
2-9 plus letters A-Z minus I/L/O), giving 31⁸ ≈ 853B unique combinations.
Input normalized to uppercase + hyphens stripped before lookup.

### 8.2 Entry paths (analytics-distinguishable)

```
QR scan       →  https://ting.cmdbee.org/r/MPE-XK7M-N3PQ?src=qr     →  session  →  /survey
Manual entry  →  https://ting.cmdbee.org → form → /r/MPE-XK7M-N3PQ?src=manual    →  session  →  /survey
Public view   →  https://ting.cmdbee.org/summary  (no code required)
```

### 8.3 Session

Server mints a random 32-byte urlsafe-b64 session_id, stores
`{code_id, started_at}` in Valkey with 24h sliding TTL, sets an
HTTPOnly + SameSite=Lax + Secure cookie. The code is **never** stored in
the cookie — only the opaque session_id. Logout clears the cookie.

### 8.4 Rate limits

- **Per-IP-hash:** 10 code-redemption attempts / hour. `ip_hash =
  HMAC-SHA256(IP, server-secret)[:8 bytes]`. Non-reversible; ephemeral
  in Valkey; never persisted to disk.
- **Per-code:** 60 writes / 5 min. Covers thumb-fat-fingers without
  enabling enumeration.

### 8.5 Privacy stance

- No IPs to disk. Ever.
- No third-party trackers, no fingerprinting, no cookies beyond session.
- Respect `DNT: 1` (skip analytics calls).
- `/privacy` page covers exactly what is and isn't tracked. Linked from
  footer + code-entry page.

### 8.6 Analytics — GoatCounter

Standard 1KB no-cookie script on every page. Plus custom events:

| Event | When fires | Useful for |
|---|---|---|
| `code_entry_qr` | redemption URL had `?src=qr` | QR vs manual breakdown |
| `code_entry_manual` | manual entry form succeeded | (same) |
| `survey_started` | first survey page render with active session | completion denominator |
| `survey_completed` | last required question answered + final save | completion numerator |
| `pledge_added` | first pledge persists | feature engagement |
| `comment_posted` | comment submit succeeded | feature engagement |
| `endorsement_toggled` | endorsement add or remove | feature engagement |

Survey duration: server stashes `started_at` in Valkey on `survey_started`,
computes `duration_seconds` on `survey_completed`, inserts one row in
`metrics_events` (thin event log, no content links).

GoatCounter is opt-in via `GOATCOUNTER_SITE_CODE` env var; unset (default
in dev tier) means the script tag isn't rendered.

## 9. Public summary view

URL: `/summary` (and per-proposal `/proposal/<slug>`). No code required.

Sections rendered:

- **Priorities** — Borda-scored ranking questions as horizontal bar charts.
- **Trust in governance** — NPS results per subject, stacked bar with
  promoter/passive/detractor split.
- **Agreement** — Likert distributions as histograms (collapsible if >5).
- **Pledges** — totals per proposal: dollars/month and hours/week, plus
  respondent count. Row links to `/proposal/<slug>`.
- **Top endorsed comments** — top 5 system-wide with endorsement counts.
- **Admin bulletins** — only shown if active in current cohort.

### 9.1 Grade filter

`?grade=k-2` re-runs aggregations on the matching `advocate_grade` slice.
Hidden when n<10 in a slice (privacy floor — don't let small slices
identify individuals).

### 9.2 Caching

Aggregate render is cached in Valkey for 60s (300s before BoE meeting if
load demands). Writes don't invalidate; up-to-60s staleness is acceptable.

### 9.3 Printed-PDF / tablet output

Same HTML page with `?print=true` variant: drops filter chrome, applies
print CSS for A4/Letter. Workflow for BoE: browser print-to-PDF, commit
the PDF to `schools` repo, email to board members ahead of meeting. No
in-app PDF generation logic.

### 9.4 Live updates (deferred)

`<meta http-equiv="refresh" content="60">` on `/summary` for the MVP
gives "live-ish" updates during the demo. WebSocket-driven real-time
updates are iteration 2.

## 10. Admin path — `scripts/ting` CLI

Thin Python CLI using Typer; wrapper script `scripts/ting` resolves the
venv and calls `python -m ting.cli`. Talks directly to the same Postgres
+ Valkey the app uses. In-cluster ops via `kubectl exec`.

```
ting seed <yaml-file>          load/upsert proposals + questions + cohorts
ting seed --dry-run <yaml>     validate without writing
ting codes generate            generate codes for a cohort
    --cohort MPE-2026-spring
    --count 400
    [--prefix MPE]
ting codes export              export codes for printing
    --cohort MPE-2026-spring
    --format csv|html          csv = mail-merge feed; html = QR-per-code printable
    --base-url https://ting.cmdbee.org
    [--only-unprinted]
ting cohort retire <name>      mark cohort retired; reads ok, writes blocked
ting bulletin post             post broadcast bulletin
    --body "..."
    --as cervator
ting report                    generate the BoE one-pager
    --cohort MPE-2026-spring
    --out summary.html
ting healthcheck               DB / Valkey / version dump
ting migrate                   run Alembic migrations
ting dev                       boot app via uvicorn against dev-tier services
```

### 10.1 Code generation specifics

- `code_str = <prefix>-<4 chars>-<4 chars>` from no-confusion alphabet
- Bulk insert in a single transaction; retry-on-collision (vanishingly rare)
- Generated `printed_at = NULL`; `codes export` flips to `now()` so the
  unprinted slice can be re-exported with `--only-unprinted`

### 10.2 Code export — HTML format

Self-contained HTML page with embedded CSS and inline-SVG QR codes (via
the `qrcode` Python lib). Layout: 8 codes per A4/Letter page, 2×4 grid;
each cell shows QR (~2cm), full URL, and the alphanumeric code in large
monospace for backup manual entry. User opens in browser, prints to PDF
or paper, mail-merges or cut-and-folds from there. No in-app PDF
dependency.

### 10.3 Secrets and access

DB and Valkey URLs come from env vars (k8s Secret on the pod). Local
operator CLI use reads `.env.ting` in the component dir. No shared admin
password — CLI authorization is "you have shell access on a pod or
workstation with the secret." Matches knarr.

## 11. Deploy tiers

Four tiers, all sharing the same code with env-var-driven configuration:

### 11.1 `dev` — local, no k8s

- Anywhere with Docker; works on a fellow PTA dad's laptop, zero homelab.
- `docker-compose.yml` at repo root brings up Postgres 16 + Valkey 7.
- App runs locally via `uvicorn` with hot reload (`./scripts/ting dev`).
- Hostname: `localhost:8000`. No cert, no DNS, no k8s.
- Onboarding: clone → copy `.env.example` → `docker compose up -d` →
  `./scripts/ting migrate` → `./scripts/ting seed seeds/example.yaml` →
  `./scripts/ting dev`. ~5 minutes to first localhost hit.

### 11.2 `localk8s` — k3d / Rancher Desktop with Mimir

- For validating the same Mimir Claims path before pushing to GKE.
- Kustomize overlay `k8s/overlays/localk8s` applies the full stack into
  a `ting-local` namespace.
- Hostname: `ting.local` via `/etc/hosts`; self-signed cert.
- Requires Mimir installed locally (k3d-nordri-test or equivalent).

### 11.3 `cmdbee` — GKE staging

- Kustomize overlay `k8s/overlays/cmdbee`.
- Hostname: `ting.cmdbee.org`. Wildcard A record on cmdbee.org already
  points at the Traefik LB; no DNS work needed.
- Cert: `letsencrypt-gateway-staging` ClusterIssuer (browser will warn
  "untrusted" — acceptable for the 5/13 demo).
- **The 5/13 PTA-meeting demo runs from here.**

### 11.4 `frontstate` — GKE production (deferred)

- Kustomize overlay `k8s/overlays/frontstate`.
- Hostname: `ting.frontstate.org`. DNS cutover after 5/13 green light.
- Cert: `letsencrypt-gateway` (prod) ClusterIssuer.
- Triggered post-5/13 demo with explicit user approval; manifest applies
  must regenerate the printed QR codes with the new base URL before
  envelope stuffing.

### 11.5 Repository layout

```
components/ting/
├── AGENTS.md                # agent guidance
├── README.md                # human-facing setup, deploy, ops
├── Dockerfile               # python:3.12-slim base, multi-stage (local dev: 3.12+)
├── docker-compose.yml       # dev tier: postgres + valkey
├── pyproject.toml           # FastAPI, Jinja2, SQLAlchemy, Alembic, Typer, qrcode, httpx, etc.
├── .env.example
├── scripts/
│   └── ting                 # bash wrapper → python -m ting.cli
├── src/ting/
│   ├── __init__.py
│   ├── app.py               # FastAPI app factory
│   ├── cli.py               # Typer entrypoint
│   ├── config.py            # Pydantic settings (env-var driven)
│   ├── db.py                # SQLAlchemy engine + session
│   ├── valkey.py            # redis-py client wrapper
│   ├── auth.py              # code redemption + session cookie
│   ├── ratelimit.py
│   ├── codes.py             # generation + alphabet helpers
│   ├── aggregation.py       # Borda, NPS, Likert calc
│   ├── models/              # SQLAlchemy ORM
│   ├── routes/              # FastAPI routers: public, survey, summary
│   ├── services/            # business logic
│   ├── templates/           # Jinja templates
│   └── static/              # css, htmx.min.js, alpine.min.js, sortable.min.js
├── migrations/              # Alembic
├── seeds/
│   ├── example.yaml         # ships with the repo
│   ├── 2026-05-13-pilot.yaml.example   # cohort scaffold
│   └── schema.md            # YAML format docs
├── k8s/
│   ├── base/                # kustomize base (namespace, deployment, service, ...)
│   └── overlays/
│       ├── localk8s/
│       ├── cmdbee/
│       └── frontstate/
├── tests/
│   ├── conftest.py
│   ├── unit/
│   ├── integration/         # testcontainers-postgres
│   └── e2e/                 # KUTTL manifest tests
└── docs/
    ├── architecture.md
    ├── operations.md
    └── plans/
```

### 11.6 Image build

GitHub Actions on push to `main`: build, tag
`ghcr.io/siliconsaga/ting:<sha>` + `:latest`, push as a **public** GHCR
package (so no imagePullSecret is needed in the cluster). Kustomize tags
reference `:<sha>` for auditable deploys.

### 11.7 Deploy flow (MVP, manual kubectl)

```bash
# 1. Build & push image (Actions on push to main, or local docker build + push)
# 2. Bump image tag in k8s/overlays/cmdbee/kustomization.yaml
ws commit ting .commits/bump-image-<sha>.md
ws push ting
# 3. Apply
kubectl apply -k components/ting/k8s/overlays/cmdbee
# 4. Initial schema + seed
kubectl exec deploy/ting -n ting -- ting migrate
kubectl exec deploy/ting -n ting -- ting seed /app/seeds/2026-05-13-pilot.yaml
# 5. Generate + export rehearsal codes
ting codes generate --cohort MPE-2026-spring-rehearsal --count 30
ting codes export --cohort MPE-2026-spring-rehearsal --format html \
    --base-url https://ting.cmdbee.org > rehearsal.html
# Open rehearsal.html in browser → print to PDF/paper
```

ArgoCD wiring (iteration 1.5): add `nidavellir/apps/ting-app.yaml`
pointing at `components/ting/k8s/overlays/cmdbee`, sync wave 20. Removes
the manual `kubectl apply` step.

### 11.8 Resource ask

- web pod: 250m CPU / 256Mi memory
- PostgreSQLInstance: 500m CPU / 512Mi memory (Percona overhead)
- ValkeyCluster: 100m CPU / 64Mi memory

Comfortable on the existing homelab cluster.

## 12. Testing strategy

| Layer | Tool | Covers | When |
|---|---|---|---|
| **Unit** | pytest | code-gen alphabet, Borda math, NPS calc, Likert histogram, session mint/verify, rate-limit math | every save (sub-second) |
| **Integration** | pytest + testcontainers-postgres | schema migrations, response upsert replaces, cohort retire blocks writes, pledge update path, endorsement uniqueness | every push (~30s) |
| **E2E** | KUTTL | namespace + Cert + HTTPRoute apply, cert reaches Ready, `curl` returns 200 | on demand |
| **Smoke** | bash + curl | redeem test code → submit response → assert `/summary` reflects it | before declaring deploy ready (Day 4 morning) |

No BDD for MVP. `ws test` adapter at
`realms/realm-siliconsaga/adapters/ting.yaml`:

```yaml
commands:
  test: python3 -m pytest tests/unit tests/integration
  lint: python3 -m ruff check src/ tests/
ai_context:
  - README.md
  - AGENTS.md
  - docs/architecture.md
```

CI: GitHub Actions runs unit + integration on every push (Postgres
testcontainer). E2E runs only on manual dispatch (needs live cluster).
Lint is a separate fast-fail job.

## 13. Seed YAML format

Lives at `components/ting/seeds/<cohort-name>.yaml`. `ting seed <file>`
upserts everything idempotently; slugs are stable identifiers.

```yaml
cohort:
  name: MPE-2026-spring-pilot
  description: First pilot cohort, MPE families, spring 2026
  retired_at: null

proposals:
  - slug: retain-paras
    title: Retain paraprofessionals in-house (don't outsource)
    body: |
      The May 4 budget shifted paraprofessionals to outsourced staffing.
      This proposal advocates for in-house retention via supplemental
      funding routed through the PTA or similar 501(c)(3).
    status: active
  # … more proposals …

questions:
  - slug: rank-priorities-spring
    type: ranking
    prompt: Rank these in order of importance to your family
    display_order: 1
    payload:
      proposal_slugs: [retain-paras, security-coordinator, hvac-maintenance, cooperative-purchasing]
      pick_top_n: null     # null = rank all; integer = top-N
      required: true

  - slug: nps-boe
    type: nps
    prompt: How likely are you to recommend the Board of Education to other parents?
    display_order: 2
    payload:
      subject: the Board of Education

  - slug: nps-union
    type: nps
    prompt: How likely are you to recommend the local teachers' union to other parents?
    display_order: 3
    payload:
      subject: the local teachers union

  - slug: nps-pta
    type: nps
    prompt: How likely are you to recommend the PTA to other parents?
    display_order: 4
    payload:
      subject: the PTA

  - slug: nps-ting
    type: nps
    prompt: How likely are you to recommend this site to other parents?
    display_order: 5
    payload:
      subject: this site

  - slug: agree-supp-funding
    type: likert
    prompt: How strongly do you agree?
    display_order: 6
    payload:
      statement: MPE should accept supplemental community funding to retain positions, where legally permitted.

bulletins:
  - body: |
      Welcome to the MPE Spring 2026 pilot. Your code is anonymous; it
      ties to nothing about you personally. …
    posted_by: cervator
```

Notes:

- **Idempotent.** Re-running `ting seed` updates proposals/questions in
  place by slug; cohort row is upserted by name. Bulletins append.
- **Removing a question between runs** doesn't delete its responses — it
  sets `display_order = null` so it stops appearing in the survey. Data
  stays.
- **Validation.** `ting seed --dry-run` validates against the schema and
  reports errors without writing. Run before applying.
- **Symmetric NPS coverage is a content requirement.** Seeds must include
  the BoE, the union, the PTA, and this site itself — asymmetric
  coverage would read as adversarial.

## 14. Timeline

Today is **2026-05-10 (Sunday)**. PTA meeting **Wednesday 5/13**. Three
days of build, half a day of polish, evening demo.

| When | Goal | Concrete deliverables |
|---|---|---|
| **Day 0 — Sun 5/10** (partial) | Skeleton up | Repo scaffolded; FastAPI returns 200 on `/`; Alembic baseline; `docker-compose.yml` works; k8s `base/` manifests committed; Dockerfile builds |
| **Day 1 — Mon 5/11** | Auth + survey engine | Code redemption flow live; all three question types render; `POST /respond` upserts; unit tests for Borda/NPS/Likert pass; integration test for upsert + cohort retire blocks writes |
| **Day 2 — Tue 5/12** | Public face + localk8s validation | `/summary` endpoint with all widgets and grade filter; comments + endorsements; pledges UI + aggregation; GoatCounter conditional rendering; `/privacy` and `/about` placeholders; localk8s tier verified end-to-end |
| **Day 3 — Wed 5/13 AM** | Seed + print + cmdbee deploy | User authors real proposals/questions in seed YAML (1–2 hrs); `ting seed`; generate ~30 rehearsal codes; `codes export --format html`; print; smoke test pass; `ting.cmdbee.org` live |
| **Wed 5/13 PM** | **PTA meeting demo** | Printed code slips + big-QR sheet; walk room through scan → survey → summary; capture friction notes |
| **Days 4–9 — Thu 5/14 → Tue 5/19** | Hardening | Bugs from demo; ArgoCD wiring; frontstate overlay prep with prod cert; DNS for `ting.frontstate.org`; **write `/about` page with academic citations** for Borda + NPS + Likert |
| **Days 10–11 — Wed 5/20 → Thu 5/21** | Print run | Generate ~400 codes for MPE cohort; `codes export --base-url https://ting.frontstate.org`; print; fold-and-seal; count per class; deliver to principal |
| **Fri 5/22** | **Distribution day** | Backpacks home; principal email blast; Kuma uptime monitoring on |
| **5/23 → 6/14** | Iteration 1.5 | Monitor analytics; admin web UI for bulletin posting; draft BoE report content |
| **Sun 6/14** | BoE prep | `ting report --cohort MPE-2026-spring-pilot --out summary.html` → browser print to PDF; commit to schools repo; email to board ahead of meeting |
| **Mon 6/15** | **BoE meeting** | Tablet `/summary` + printed PDF in agenda packets |

## 15. Risks

- **DNS for `ting.cmdbee.org` not resolving.** Validated 2026-05-10:
  wildcard A record on cmdbee.org already points at 34.75.13.183.
  Subdomain works automatically.
- **Mimir Postgres Claim slow first-provision.** First-time `PostgreSQLInstance`
  Claims can take 5–15 min while Percona operator runs through its
  setup. Mitigation: build the rest of the app against the dev tier
  (Docker) in parallel; cut over to localk8s/cmdbee once the Claim
  reports Ready.
- **`/about` academic content slipping.** It's a 5/13–5/22 window task,
  not a Day 3 task, but is a credibility-shaping deliverable for the
  BoE. Named milestone in the timeline.
- **Demo data on 5/13 looks thin.** If <20 respondents by meeting-time,
  bar charts and NPS look anemic. Mitigation: have a separate
  "warmup demo" cohort with explicitly-labeled synthetic data for
  the visual demo only. Don't show synthetic numbers as real.
- **GHCR image pull permissions.** Public package = no imagePullSecret
  needed; verify package visibility is public after first push.
- **Comment "review existing first" gate fatigue.** If a proposal
  accumulates many comments, the gate becomes annoying. Acceptable for
  MVP scale (small pilot cohort); revisit at platform-wide scale.

## 16. Open questions (track for post-demo resolution)

- **District-acceptance legal question.** Can MPE accept earmarked private
  funding for specific staff positions? If not, pledges have to route
  through PTA/501(c)(3) for *programmatic* purpose (e.g., "fund a
  security-coordinator role under the PTA umbrella using school space").
  Affects every position-saving outcome the platform might surface.
  Reach out to a school finance attorney pro bono.
- **`/about` academic citations.** Borda count (Borda 1781; Saari 1985),
  NPS (Reichheld 2003), Likert (Likert 1932). Site needs plain-language
  framing of each plus citations for credibility with skeptical board
  members. Deliverable on/before 5/22.
- **PTA / platform boundary.** PTA is the natural fiscal sponsor and
  distribution channel for the pilot, but the platform must remain
  usable by anyone with a code, including non-members.
- **Updating `schools/next-year.md`.** Page promises "counter-offers and
  alternatives" which the MVP defers. Update post-5/13 to "later
  iteration" alongside any other reconciliation.

## 17. Future iterations

- **Iteration 1.5 (post-5/22, pre-6/15):** ArgoCD wiring; admin web UI
  for bulletin posting; Kuma Uptime monitoring with paging; frontstate
  cutover.
- **Iteration 2 (post-6/15):** Counter-offers as a comment subtype;
  sentiment-over-time / drift visualizations across cohorts; WebSocket-
  driven live `/summary`; BDD test layer.
- **Iteration 3:** Vouching mechanism for incident tracking (the
  "Outsourced Para Incident Tracking" item from `next-year.md`);
  OpenCollective hookup for pledged funds.
- **Iteration 4+:** Generalize to "Raised Topics platform" across
  schools; town-level instance; Keybase-style off-site identity
  vouching as opt-in soft proof.
- **Long-term comparison targets:** Decidim (Ruby on Rails, mature
  civic-tech platform — likely v2 migration target); Pol.is (consensus
  clustering — interesting for free-form opinion aggregation).

## 18. References

- [`schools/next-year.md`](https://github.com/SiliconSaga/schools/blob/main/next-year.md) — public-facing framing
- Pilot Design Notes in the local thalami hoard (`hoards/thalami-Cervator/rasmuss-mbp-2-thalamus.md`, gitignored per-machine file) — origin of the brainstorm; this design supersedes the notes in places, notes remain useful context
- [`nidavellir/demos/whoami/whoami.yaml`](https://github.com/SiliconSaga/nidavellir/blob/main/demos/whoami/whoami.yaml) — Gateway API + cert-manager reference pattern
- [`mimir/valkey/claim.yaml`](https://github.com/SiliconSaga/mimir/blob/main/valkey/claim.yaml) — ValkeyCluster Claim shape
- [`mimir/percona/PostgresSampleDB.yaml`](https://github.com/SiliconSaga/mimir/blob/main/percona/PostgresSampleDB.yaml) — PostgreSQLInstance Claim shape
- [`SiliconSaga/knarr`](https://github.com/SiliconSaga/knarr) — blueprint Python component (CLI wrapper, k8s layout, env setup, BDD pattern for later)
- WOPE budget survey — referenced by `next-year.md` as a structural precedent
- Decidim, Pol.is, Loomio, LiquidFeedback — civic-tech library landscape (not adopted; tracked as v2+ comparators)
