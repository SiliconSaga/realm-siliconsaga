# Sweet Home 3D — Build & Asset Modernization Plans (future / Track C)

**Date:** 2026-05-25 · **Status:** Forward plan, not yet executed · Companion to `2026-05-25-sh3d-mirror-design.md`

## Guiding principle: mirror vs fork, source vs data

- **Mirror** (`components/sweethome3d`, `upstream` branch): a faithful copy of upstream *source*. The line is drawn by **concept, not size**: keep authored **source** (code, small text config, crafted test fixtures, vendored patched-source for forked deps); drop **data/content** (assets, demo homes, dependency jars/natives) and **build outputs** (installers). Written only by git-svn; not standalone-buildable.
- **Fork** (`main`): where modernization happens — deliberate, tracked changes in isolated files. This is where the build becomes buildable again (deps/natives/fixtures restored) and where everything below lives.

## Current build reality (verified in the mirror / upstream SVN, r9047)

- **Apache Ant** — one `build.xml` per module: `SweetHome3D`, `SweetHome3DJS`, `FurnitureLibraryEditor`, `TexturesLibraryEditor`. No Maven/Gradle.
- **Committed binary dependencies** — the classic pre-resolution `lib/` pattern:
  - **Jars: 549 MB across history (21% of blob bytes)** — dominated by the JSweet transpiler uber-jar (~300+ MB across versions) and Java3D/JOGL jars (~100+ MB).
  - **Native libs**: Java3D/JOGL platform natives (`.so`/`.dylib`/`.jnilib`/`.dll`) **plus an entire bundled yafaray ray-tracer** (core + ~40 render plugins × linux/macosx/windows). Hundreds of files.
- **Two deps are SH3D forks, not vanilla:** `freehep` (SVG export — 2 patched classes) and `sunflow` (the ray-tracer — ~71 patched source files + a build script) ship as `*-src-diff.zip` "source that differs from upstream." SH3D compiles these into its own freehep/sunflow jars. ~0.5 MB total, changed ~a couple times/year (2010–2022) for rendering/SVG fixes. **Kept** (maintained source) — but flags that those two deps can't come from Maven Central vanilla.
- Tests: Java JUnit under `SweetHome3D/test/`, JS under `SweetHome3DJS/test/` — **both kept**. Dependency jars and demo-home fixtures are restored (below); crafted fixtures stay in git.

## Mirror exclusion list (finalized — concept-based)

Via `git svn clone --ignore-paths` (same value reused on every fetch; lives in `sweethome3d/config.sh`):

- `3DModels/`, `Textures/` — bulky standalone asset libraries (content).
- `SweetHome3DJS/other/` — dead historical junk (no longer in current trunk).
- `SweetHome3DExample*.{sh3d,zip}` — realistic **demo/sample homes** (content). **Kept** (source, not content): crafted edge-case fixtures (`damagedHome*.sh3d`, `holes.sh3d`, `home1.sh3d`, `HomeTest.sh3d`, `cube.zip`) and the vendored patched-source for the forked `freehep`/`sunflow` deps (`*-src-diff.zip`).
- built installer binaries: `.exe`/`.dmg`/`.pkg`/`.msi` (build output).
- **all `*.jar`** — 549 MB of committed deps.
- **native libs `*.so`/`*.dll`/`*.dylib`/`*.jnilib`** — Java3D/JOGL + yafaray natives.

Regex: `(^|/)(3DModels|Textures)(/|$)|(^|/)SweetHome3DJS/other(/|$)|(^|/)SweetHome3DExample[^/]*\.(sh3d|zip)$|\.(exe|dmg|pkg|msi|jar|so|dll|dylib|jnilib)$`

Result: `upstream` carries faithful *source* only. The jars-only lean pass already hit 221 MB; stripping natives + demo homes trims further. Treated as a one-time-ever cleanup, hence the thoroughness.

## Dependencies, natives & fixtures — restored on the fork

The unified mechanism — nothing large or binary lives in git:

- **Plain jars** (batik, iText, jdom, json, …) → resolved from **Maven Central**.
- **Forked deps** (`freehep`, `sunflow`) → NOT on Maven vanilla. Either compile from the kept `*-src-diff.zip` source, or build once and publish the patched jars to **Artifactory**.
- **Natives / special bundles** → versioned **zip artifacts in Artifactory** (already run for Terasology). **Gradle resolves + unzips** them into `.gitignored` local dirs (`lib/`, `natives/`). Bump the version to update — zero git bloat. Ideal for Java3D/JOGL natives, the **yafaray** bundle, and the JSweet transpiler. (Terasology natives pattern.)
- **Demo-home fixtures** (`SweetHome3DExample*`) → same rail: an Artifactory zip (or `svn export`), unzipped to a `.gitignored` `test/fixtures/`, cached in CI.
- **Ant bridge (`resolve-libs`):** until Gradle lands, a `resolve-libs` Ant target (Ivy or `<get>`) fetches jars + natives into place (runtime **and** test: `lib/` + `libtest/` + `tools/JSweet/lib`). Lives on `main` in new files; the only upstream edit is a one-line `<import>` hook per `build.xml`.
- **Not** git submodules; **not** LFS on the mirror (history rewrite breaks git-svn sync).

## Testing & fixtures (source vs data)

- Test *code* is kept (Java `SweetHome3D/test/`, JS `SweetHome3DJS/test/`). Tests run on `main`/CI, never on the `upstream` mirror.
- **Crafted test fixtures** (`damagedHome*`, `holes`, `home1`, `HomeTest`, `cube`) are **test source** → kept in git. Purpose-built to exercise specific code paths (corrupt-file handling, geometry holes, minimal loads); can't be "fetched" as content. Long-term, the fork may *generate* such minimal fixtures in code.
- **Demo/sample homes** (`SweetHome3DExample*`) are **content** → stripped, re-supplied on demand (Artifactory zip / `svn export`, cached) for integration/demo tests.
- **Test dependencies** (jars) restored by the same resolution step as build deps.

## Modernization moves (fork-side, future)

1. **Ant → Gradle.** Unlocks dependency resolution, the Artifactory zip-artifact pattern, the Gestalt module system, and CI. The hinge for everything else; `resolve-libs` is the Ant-era bridge.
2. **Dependencies, natives & fixtures from repositories** (Maven Central + Artifactory zip artifacts), never git. Decide the freehep/sunflow forked-dep handling (compile-from-source vs published patched jar).
3. **Assets as content modules.** Terasology-style: lean core + small focused content modules carrying their own artwork in plain git. SH3D's `.sh3f`/`.sh3t` libraries and the `3DModels`/`Textures` trees become content modules. **Git LFS** only as a fallback for a module with genuinely large/churning binaries — never on core/mirror.
4. **Release binaries → GitHub Releases** via CI. Never committed.
5. **Java3D liability (flagged).** Dead upstream, vendored as platform-native jars + natives — the single biggest modernization risk. The Artifactory-natives pattern is near-term containment; revisit the backend (JOGL-direct, or another) when the build moves to Gradle. The bundled **yafaray** ray-tracer (also a forked, patched dep) is a second native backend in the same boat.
