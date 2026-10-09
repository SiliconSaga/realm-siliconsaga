# Terasology realm helpers

Realm-side tooling for working the Terasology component. Lives here rather than in the engine repo because it is GDD-specific scaffolding — useful to someone running this workspace, noise to everyone else. Improvements that help every contributor belong upstream in Terasology itself.

## `clear-module-logback.sh`

Clears the untracked `src/test/resources/logback-test.xml` copies that the module build leaves in module working trees.

The engine's build-harness zip packages `templates/module.logback-test.xml` as `src/test/resources/logback-test.xml` (see `build.gradle.kts`), so any module a harness build touches gains a file it does not gitignore. On a full checkout that is around fifty modules reading as dirty at once, which trains everyone to skim past module dirt — and that is exactly how a real uncommitted change goes unnoticed.

```bash
bash realms/realm-siliconsaga/terasology/clear-module-logback.sh          # dry run
bash realms/realm-siliconsaga/terasology/clear-module-logback.sh --apply  # remove
```

A file is only removed when all three hold: untracked in its own repo, not gitignored there, and byte-identical to the engine's template. Everything else is classified and left alone, in three buckets worth knowing about:

- **already gitignored** — a couple of modules carry the `.gitignore` entry. That is the per-module fix, and those modules produce no noise.
- **committed by accident** — a couple of modules have the generated file tracked. Undoing that needs a PR to each module, not a working-tree sweep.
- **content differs** — someone edited it deliberately. Never touched.

Set `TERASOLOGY_DIR` if the engine is not at `components/terasology`.

This is a noise sweep, not a fix: the build writes the file again on the next harness build. The real fix is for the module build to stop writing into the source tree, or for the harness to gitignore what it writes — a module-build overhaul that wants its own design pass.

## Nested module targets

`adapters/terasology.yaml` declares `nested: ["modules/*", "libs/*"]`, which lets `ws` address module repos in place:

```bash
ws status --nested            # which nested repos are dirty
ws exec terasology/Health git log --oneline -5
ws commit terasology/Health .commits/fix.md
```

See [`docs/gdd/adapters.md`](../../../docs/gdd/adapters.md) for the full contract.

## naust: the PR-bay scripts

`../naust/terasology.yaml` is the naust profile for this component and `../naust/trust.yaml` the trust list; the `provision:` block in `../adapters/terasology.yaml` says how `ws bay` provisions and resets the tree. See the [design](../docs/plans/2026-10-08-naust-pr-bays-design.md). The profile points at three scripts here, all run by naust with the engine checkout as cwd and `NAUST_*` in the environment:

- `pr-seed.sh generate|restore` — the seed save that `--create-last-game` needs. `generate` runs once per bay and fills `seed-manifest.template.json` with the versions in the checkout, keeping the result in the bay's `.tmp/naust/seed/`; `restore` runs after every reset and puts it back under `saves/naust-seed/`.
- `pr-headless.sh` — boots the facade's `server` task and waits for `Server started`.
- `pr-smoke.sh` — boots `gradlew game --args="--create-last-game --no-splash --no-crash-report --no-save-games"`, waits for the renderer's `Initialising rendering class` line, settles, screenshots the primary display (`screenshot.ps1` on Windows) and stops the game. `pr-lib.sh` holds the marker wait, the stop and the screenshot.

Run them by hand from a bay's `components/terasology` with `NAUST_BAY_DIR` set to the bay and `NAUST_JOB_DIR` to any directory to see what a job sees. Tests: `bash realms/realm-siliconsaga/terasology/tests/run.sh`.
