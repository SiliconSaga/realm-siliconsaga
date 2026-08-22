# Agent Documentation Layering

How agent-facing documentation relates to a project's own documentation, when the project is not AI-first and should not be made to carry agent configuration.

Written for Terasology, but nothing here is Terasology-specific.

## The problem

An agent needs orientation a project's docs do not provide: which doc answers which task, which commands exist, what will silently mislead it. The lazy fix is to write an agent-flavoured copy of the project's documentation in a place we control. That produces two corpora that drift, and the copy is always the one that rots, because only the original gets read by the people changing the code.

## Rule 1 — Placement

For any fact, ask: would a contributor who has never heard of GDD benefit from this sentence, and does it avoid mentioning agents or `ws`?

Both yes → **upstream**, written plainly, in the project's own docs. Otherwise → **realm**.

Most facts pass. That a build task writes into the repository root, that the toolchain is a given version, that an API's documented signature is backwards — every contributor needs these and none of them mention AI tooling. The realm layer stays small by design, and the project gets better docs as a side effect.

## Rule 2 — Route, don't copy

The skill layer points at documentation. It never inlines doc prose. One source, both audiences.

A skill that starts explaining the thing it links to has become a second copy, and the link is now decoration.

## Rule 3 — Corrections are dated annotations, never shadow docs

When an upstream doc is wrong, record **what** is wrong and **when** it was checked, as metadata beside the pointer. Never write a corrected copy.

An annotation is a claim about a document. A corrected copy is a competing document. The first deletes itself when the upstream fix lands; the second survives, unnoticed, and eventually contradicts reality on its own.

## Rule 4 — Examples live in code that rebuilds

Prefer pointing at tutorial repositories, sample modules, or tests that compile against the real thing. They break visibly when the code drifts. Documentation snippets do not — they rot silently and stay plausible.

Where a snippet is genuinely needed, keep it tiny and generic.

## What this does not solve

Pointer checking catches dead paths. Nothing mechanical catches a doc that is still present and now wrong. Currency is a periodic review, and the review's date is part of the record.
