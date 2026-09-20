---
name: terasology-review
description: Use when reviewing or validating a Terasology pull request — engine, facade, or module — before writing any verdict. Six ordered checks; most wrong review conclusions came from doing them out of order.
---

# Terasology review procedure

Practice, not routing: the `terasology` skill routes to upstream docs, and this is the one procedure no upstream page covers. It leaves when one does. Read `docs/How-to-Work-on-a-PR-Efficiently.mediawiki` first for the community's own PR etiquette; `ws review terasology <cr#>` fetches the bot threads.

The order matters more than any single step.

1. **Establish the diff honestly.** `git diff develop` on a PR branch shows tip-to-tip drift, not the change — one PR read as 772 deletions that way against a true +15. Use three-dot (`develop...pr`) or `git log develop..pr`; GitHub already renders the merge-base diff correctly. To test against current `develop`, cherry-pick the PR's commits onto a scratch branch rather than testing an old base.

2. **Baseline against the unmodified base rather than deferring to CI.** Re-run the failing command on the base branch and compare. A clean base localises the failure to the change. An identical failure on the base proves only that it predates the PR — compare the failing test cases in both XML reports before excluding the change, since the PR can still touch the same path or add a failure with the same signature. Ten fresh-agent runs on a real case showed the instinct to blame the contributor does not appear — the failure signature gets read correctly on its own. What appeared instead was waiting for CI to decide: safe, slow, and it hands the question back to the maintainer who asked. The local baseline settles it in one command. It also catches what a known-failures list misses — a genuinely new failure hiding among familiar ones.

3. **Scope the run, and read the XML.** `ws test terasology <ClassName>` resolves the class on disk and scopes to one subproject; a name that does not resolve falls back to a root run across every module test task, so verify the class exists first. `engine-tests` has six test tasks, not one. And every test task exits 0 whatever the tests did (`ignoreFailures = true`, deliberate, so Jenkins can mark findings UNSTABLE) — the verdict is `engine-tests/build/test-results/<task>/TEST-*.xml`, never the exit code. See skill `terasology-testing`.

4. **Prove the code path was reached** before concluding "no error, therefore it works". A silent no-op and a working feature look identical from outside. Absence of a log line is not absence of behaviour either — check the level first, since a DEBUG line missing from an INFO run proves nothing.

5. **A green build is not a working game.** Nothing in CI launches the client, and MTE is headless, so a fully green pipeline is compatible with a game that cannot start. `./gradlew game` is the check that catches it, and it needs a human.

6. **Validate on a clean tree when the change touches generated or native files.** An additive change leaves the old artifacts in place, so every existing checkout keeps working and only a fresh one breaks — which reads as "works on my machine" on every machine that has one.

## Writing the verdict

The realm's register is `oss-wide` (`ws orient` prints it): neutral, concise, plain language, no judgement. Say what was observed and what decision it requires; do not say which way the decision should go, and do not close, merge, resolve or characterise the contribution. A module PR is addressed as `terasology/modules/<Name>` — `ws review`, `ws checkout`, `ws commit`, `ws push` and `ws cr` all take the nested form.
