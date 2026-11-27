# Huginn — a local policy bridge between agents and Thunderbird: design

**Status:** Draft for review. No code exists yet.
**Date:** 2026-11-27
**Owner:** Rasmus Praestholm
**Arc:** `pkm-life-organization` on the Dionysus thalamus
**Related:** the [Muninn design](2026-11-27-muninn-design.md) (the Thunderbird extension on the other end; read it first for the outcome and the permission list) · the [Knarr design](2026-04-02-knarr-design.md) · [naust](https://github.com/SiliconSaga/naust) (the scheduled-run pattern the first callers follow)

## The outcome

Any agent, script or person on the owner's machine reaches Thunderbird's mail through one small local service with a token, a policy file and a log. The caller needs no mail credentials and no knowledge of Thunderbird's extension interfaces, and is not tied to one AI vendor: the interface is plain HTTP and JSON.

Muninn sets the hard limit on what can happen at all (no sending, no deleting). Huginn sets the adjustable limit on what a given caller may do today, and records what was done.

## Vocabulary

| Term | Meaning |
|---|---|
| **Huginn** | The bridge process. Thunderbird starts it; it speaks native messaging to Muninn on one side and HTTP on localhost to callers on the other. |
| **Native messaging** | The browser-extension mechanism where the host application launches a registered local program and exchanges length-prefixed JSON with it over standard input and output. |
| **Policy** | A file the owner edits that says which accounts, folders and operations each token may use, and the size limits on a request. |
| **Read token, write token** | Two bearer tokens. The read token can only search and read. The write token can also file, tag and save drafts. |

## Scope

In scope for the first version:

1. The native-messaging host: framing, request and answer matching, timeouts.
2. An HTTP interface on `127.0.0.1` with bearer-token authentication.
3. Policy checks before any request reaches Muninn.
4. An append-only audit log of every write request and its result.
5. A small command-line client, so a shell script or a person can call it without writing HTTP.
6. Install and uninstall of the native-messaging registration on Windows and Linux.

Out of scope:

- Listening on any interface other than loopback. A caller on another machine is not supported; the caller runs beside Thunderbird.
- Holding or reading mail credentials, or reading the Thunderbird profile from disk.
- Any AI. Huginn calls no model and has no notion of a prompt.
- An MCP server. One can be a thin caller of the HTTP interface later, as its own piece.
- Calendar and tasks, for the reason given in the Muninn design.

## Shape

```text
 scheduled run ─┐
 script ────────┼─▶ HTTP 127.0.0.1 ─▶ ┌────────── Huginn ──────────┐ ─stdin/stdout─▶ Muninn (in Thunderbird)
 huginn CLI ────┘    bearer token     │ auth ▶ policy ▶ forward    │
                                      │            └▶ audit log    │
                                      └────────────────────────────┘
```

Thunderbird launches Huginn when Muninn opens its port, and Huginn exits when the port closes. So Huginn is available exactly while Thunderbird is running, and a caller that finds nothing listening reports "Thunderbird is not running" and stops; it does not start Thunderbird itself.

## The HTTP interface

One endpoint per operation in the Muninn design, under a version prefix, for example `POST /v1/messages/search`. Request and answer bodies are JSON. A few fixed rules:

- **Authentication** is a bearer token on every request. Unauthenticated requests get `401` and are counted in the log.
- **Errors** carry a stable `code` (`policy_denied`, `not_found`, `thunderbird_error`, `timeout`, `too_large`) and a human-readable `message`.
- **Paging** is by an opaque cursor returned with each page of search results.
- **Dry run.** Every write endpoint accepts `dry_run: true`, which runs the policy check and returns what would be done without forwarding it.
- **Idempotency.** Write requests may carry an `idempotency_key`; a repeat with the same key inside a day returns the first result and does nothing more. Scheduled runs retry, and a draft saved twice is the kind of noise this prevents.
- **`GET /v1/health`** reports Huginn's version, Muninn's version and granted permissions, and whether the policy file loaded. It needs the read token.

On start Huginn asks Muninn for its granted permissions and refuses to serve if the list contains a send or delete permission. The pair is meant to be send-proof, and a build that is not should fail loudly, not quietly work.

## Policy

A file in the owner's configuration directory, re-read when it changes. Illustrative shape:

```yaml
tokens:
  read:
    accounts: ["*"]
    ops: [info, accounts.list, folders.list, messages.search, messages.get]
  write:
    accounts: ["personal", "club"]
    ops: [messages.move, messages.copy, messages.update, drafts.save]
    move_targets:
      allow: ["Triage/*", "Newsletters", "Archive/*"]
limits:
  max_messages_per_request: 200
  max_body_bytes: 200000
  max_writes_per_hour: 500
```

Rules that are not configurable:

- A move or copy whose target is a Trash or Junk folder is refused. Muninn has no delete permission, and a move to Trash is deletion by another name.
- There is no separate archive operation. Thunderbird's own archive call picks its destination from the account's settings at the moment it runs, so a destination checked beforehand could differ from the one used. Archiving is a `messages.move` to a folder the policy names, which keeps the checked folder and the used folder the same.
- Anything not allowed is denied. An absent policy file means read-only for the read token and nothing for the write token.
- Policy is checked before forwarding, and a denial is logged with the caller's token name and the request.

## Tokens and secrets

- Tokens are generated at install and stored in files readable only by the owner's user account. They are never written to the log or to the policy file.
- Tokens are bearer secrets for processes on the same machine. Any process running as the owner can read them, so they separate roles and guard against accidents; they are not a defence against malware already running as that user. The defence there is Muninn's permission list, which no token can widen.
- Rotating a token is one command and takes effect immediately.

## Audit log

One JSON line per write request and per denied request: time, token name, operation, account, message ids, target, result, idempotency key. Message bodies and subjects are not logged. The log lives beside the policy file and rotates by size. A scheduled run can quote its own lines in its report, which is how the owner sees what was filed without opening the log.

## Mail content is untrusted

Huginn passes message bodies through as data, in a field named so a caller cannot mistake it for instructions, with the truncation flag from Muninn. The service's own behaviour never depends on message content. What a misled caller can do is bounded by the write token's policy and, beyond that, by Muninn's permissions.

## Native-messaging registration

Thunderbird finds a native host through a small manifest file that names the program and the one extension id allowed to start it. On Windows the manifest is pointed to by a registry key under the current user; on Linux it sits in a per-user directory. The exact key and directory Thunderbird reads (as opposed to Firefox) are to be confirmed from Thunderbird's documentation during implementation.

`huginn install` writes the manifest and the registration for the current user and generates the tokens; `huginn uninstall` removes them. Neither needs administrator rights.

## Implementation choices

- **Repository and licence:** its own repository, separate from Muninn's, under the Apache 2.0 licence.
- **Language:** Python, standard library only. The owner's other services of this size are Python, and a bridge with no third-party dependencies is easy to audit. On Windows the registered program is a one-line launcher script that starts the interpreter.
- **Concurrency:** one native-messaging port, requests matched to answers by id, a per-request timeout. HTTP handling is threaded; writes are forwarded one at a time so the log order is the order things happened.
- **Platforms:** Windows 10 first, where the first testing happens without containers; Linux next, for a homelab virtual machine that will host Thunderbird and the callers.

## Testing

- Unit tests cover framing, policy decisions (a table of request, policy and expected outcome), idempotency and the refuse-to-serve check.
- An integration test runs Huginn against a fake Muninn: a small program speaking the same native-messaging protocol from a script of canned answers. This exercises the whole path without Thunderbird.
- The manual smoke checklist in the Muninn design covers the real pair.

## Phases

Matched to Muninn's, one change request each:

1. **Read-only.** Native host, HTTP, read token, health, the command-line client, install.
2. **Filing.** Write token, policy, audit log, dry run, limits.
3. **Drafts.** `drafts.save` with idempotency.

## Open questions

1. **Lifetime.** If Thunderbird's background script cannot hold the port open for a whole session, Huginn becomes a long-running service and the native host a thin relay to it. Decided by the first spike.
2. **Per-caller tokens.** Two role tokens to start; a token per scheduled job would make the audit log name the job. Worth it once there is more than one writer.
3. **Windows launcher.** A launcher script is the simplest registered program; a packaged executable avoids depending on the interpreter's location. Start with the script.
4. **Confirming writes.** Whether filing should wait for the mail server to confirm, or return once Thunderbird accepts the request and report failures on a later status call.
