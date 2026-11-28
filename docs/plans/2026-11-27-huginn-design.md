# Huginn — a local interface for agents to personal content: design

**Status:** Draft for review. No code exists yet.
**Date:** 2026-11-27
**Owner:** Rasmus Praestholm
**Arc:** `pkm-life-organization` on the Dionysus thalamus
**Related:** the [Muninn design](2026-11-27-muninn-design.md) (the Thunderbird extension behind the mail adapter) · the [Knarr design](2026-04-02-knarr-design.md) (chat, social content and notifying the owner) · [naust](https://github.com/SiliconSaga/naust) (the scheduled-run pattern the first callers follow)

## The outcome

Any agent, script or person on the owner's machine reaches the owner's personal content (mail, tasks, later calendar and more) through one small local service. The caller needs no credentials for the sources behind it and no knowledge of how each one is reached, and is not tied to one AI vendor: the interface is plain HTTP and JSON.

Huginn runs on its own, started at login or by hand the way a naust watch is. Each kind of content sits behind an **adapter**. Adapters differ in how they reach their source; callers see one interface, one pair of tokens and one audit log.

Huginn contains no AI and does nothing on its own initiative. A long-running agent or a scheduled job calls it or polls it.

## Vocabulary

| Term | Meaning |
|---|---|
| **Huginn** | Old Norse, *thought*; one of Odin's two ravens. The local service. It shares its name with an unrelated automation project. |
| **Adapter** | The part of Huginn that reaches one source. Each has its own operations, its own narrow access and its own fixed rules. |
| **Muninn** | The Thunderbird extension the mail adapter talks to. A separate component with its own design. |
| **Relay** | A tiny program shipped with Huginn that Thunderbird starts on Muninn's behalf. It passes messages between Muninn and the running Huginn and does nothing else. |
| **Read token, write token** | Two bearer tokens. The read token can only list, search and read. The write token can also make the changes each adapter allows. |

## Adapters

| Adapter | Source | Reached through | Can change | Never | Phase |
|---|---|---|---|---|---|
| **Mail** | Every account Thunderbird syncs | Muninn, over the relay | Folder, tags, read and flagged state; save drafts | Send, delete, move to Trash or Junk | 1–3 |
| **Tasks** | Google Tasks | Google's Tasks API with a tasks-only permission | Create, edit and complete tasks | Delete tasks or lists | 2 |
| **Calendar** | Google Calendar | Google's Calendar API, read-only at first | Nothing at first | Edit or delete the owner's events | Later |
| **Knarr** | The owner's Matrix rooms and bridged chats | Knarr's HTTP entry point | Send a notification to the owner | Post anywhere else | Later |

The first two are designed here. The last two are sketched under *Later adapters* so the interface is shaped with them in mind.

## Shape

```text
 long-running agent ─┐
 scheduled job ──────┼─▶ HTTP 127.0.0.1 ─▶ ┌──────────── Huginn ────────────┐
 huginn CLI ─────────┘    bearer token     │ auth ▶ rules ▶ adapter         │
                                           │           └▶ audit log         │
                                           │  mail adapter ◀─ relay ◀─ Muninn (in Thunderbird) ─▶ IMAP
                                           │  tasks adapter ─▶ Google Tasks API
                                           └────────────────────────────────┘
```

### How the mail adapter meets Muninn

A Thunderbird extension cannot be reached from outside; it has to open the connection itself. Muninn does that through native messaging: when Thunderbird starts, Muninn asks for its registered native program, and Thunderbird launches the relay. The relay connects to the running Huginn over a local socket and passes messages both ways.

- Everything on the Thunderbird side is Muninn. The relay is a pipe with no logic, and exists only because native messaging is the one channel an extension can open without a network permission.
- Huginn does not depend on Thunderbird. With Thunderbird closed, the mail adapter reports `adapter_unavailable` and the other adapters work as usual.
- Start order does not matter. If Huginn is not running when Thunderbird starts, the relay exits at once and Muninn tries again: every 15 seconds for the first few minutes, then once a minute for as long as Thunderbird is open. The same retry reconnects after Huginn restarts.
- The relay socket is protected on its own; the HTTP tokens do not cover it. It is reachable only by the owner's account (an owner-only pipe on Windows, a socket file in an owner-only directory on Linux), and the relay and Huginn prove themselves to each other with a secret kept in an owner-only file before any request passes. A program that is not Huginn cannot pose as it to Muninn, and one that is not the relay cannot pose as Muninn to Huginn. This holds whichever socket type is chosen.

The alternative considered: Muninn connects straight to Huginn over a local WebSocket. It needs no relay and no registration, but it gives a mail-reading extension a network permission, which the Muninn design is built to avoid.

## The HTTP interface

Endpoints are grouped by adapter under a version prefix, for example `POST /v1/mail/messages/search` and `POST /v1/tasks/tasks/create`. Request and answer bodies are JSON. A few fixed rules:

- **Authentication** is a bearer token on every request.
- **Errors** carry a stable `code` (`denied`, `not_found`, `adapter_unavailable`, `source_error`, `timeout`, `too_large`) and a readable `message`.
- **Paging** is by an opaque cursor.
- **Polling.** What "new since last time" means depends on the adapter, and each says which it offers. Tasks accepts `updated_since` and reports every task changed after that moment, because Google records a change time. Mail accepts `received_since` and reports messages that arrived after that moment; Thunderbird records no change time, so a later tag or move on an old message is not reported, and a caller that needs that looks the message up again by id.
- **Dry run.** Every changing endpoint accepts `dry_run: true` and returns what would be done.
- **Idempotency.** Changing requests may carry an `idempotency_key`; a repeat with the same key inside a day returns the first result and does nothing more.
- **`GET /v1/health`** lists each adapter, whether it is available, and its version details.

Content from every adapter is returned as data in fields of its own. Message bodies, task titles and notes, and event descriptions can all contain text written to steer an agent, and Huginn's behaviour never depends on them.

## The mail adapter

Its operations are the ones in the Muninn design, passed through unchanged. Muninn's permission list is the hard limit, and Muninn itself refuses moves into Trash or Junk. On connecting, the adapter asks Muninn for its granted permissions and refuses to serve mail if the list contains a send or delete permission.

There is no archive operation: archiving is a move to a folder the caller names.

## The tasks adapter

Google Tasks is where the owner's voice-dictated reminders land, in the default list.

| Op | Does | Notes |
|---|---|---|
| `lists.list` | The owner's task lists | |
| `tasks.list` | Tasks in one list | Filter by open or completed, and by `updated_since` |
| `tasks.get` | One task | Title, notes, due date, status, parent, links |
| `tasks.create` | A new task in a named list | Returns the task id |
| `tasks.update` | Title, notes, due date | |
| `tasks.complete` | Mark done, or reopen | |

- **No delete.** The adapter has no operation that deletes a task or a list, although Google's permission would allow it. Completed tasks stay in Google's own history.
- **Due dates are dates.** Google's interface does not expose a time of day.
- **No knowledge of the caller's world.** How a task relates to a note in a vault, or which line it came from, is the caller's business. The adapter returns stable ids so a caller can keep that binding.
- **Access.** Huginn signs in as the owner once, through a browser, with a permission limited to Tasks, and keeps the resulting token in a file only the owner's account can read. It uses its own Google client registration; it does not borrow one from another application.

## Access rules, kept light

A small configuration file says which adapters are on, which mail accounts and task lists the write token may change, and nothing more:

```yaml
adapters:
  mail:
    write_accounts: ["personal"]
  tasks:
    write_lists: ["Agent test"]
```

- The read token may read everything an enabled adapter offers. The write token may also change what the file lists. Anything not listed is denied.
- Each adapter's "never" column above is fixed in code and cannot be configured away.
- That is the whole model for now. Richer policy (per-caller rules, limits, conditions) is deliberately absent: a general policy engine is the likely long-term answer, and a home-grown rule language would only have to be replaced.

## Tokens and secrets

- The two bearer tokens are generated at install and stored in files readable only by the owner's account. They are never logged.
- They separate roles and guard against accidents. Any process running as the owner can read them, so they are not a defence against malware already running as that user. The defences there are the narrow access each adapter has: Muninn's permission list for mail, a tasks-only permission for tasks.
- Huginn holds credentials only for the adapters that reach a source directly, such as the Google Tasks token. It never holds or reads mail credentials or the Thunderbird profile.

## Audit log

One JSON line per changing request and per denied request: time, token name, adapter, operation, the ids touched, the target, the result. Titles, subjects and bodies are not logged. A caller can quote its own lines in its report, which is how the owner sees what was done without opening the log.

## Later adapters

- **Calendar.** Read-only to begin with: list calendars and upcoming events. The use in mind is one place that reminds the owner, replacing separate reminder pop-ups on each computer that do not agree on what has been dismissed. A caller reads upcoming events from Huginn and sends reminders through Knarr to the owner's Matrix room, where dismissing one dismisses it everywhere. Writing comes later and only to a calendar the adapter created itself, which Google offers a narrow permission for; whether that permission is enforced as its name suggests is to be confirmed.
- **Knarr.** A way for a caller to notify the owner through the same interface it already uses, by passing the request to Knarr's HTTP entry point. Knarr stays the owner of chat content and delivery; this adapter is a client of it and holds no chat credentials.
- **Contacts** could follow the tasks pattern.

Thunderbird is not the route for calendar and tasks: an extension cannot use the Google sign-ins Thunderbird holds, and Thunderbird has no stable extension interface for either. The Muninn design tracks the upstream work that could change this.

## Running it

- `huginn serve` runs the service in the foreground. Starting it at login is a per-machine choice; the relay never starts it.
- `huginn install` writes the relay's native-messaging registration for the current user and generates the tokens; `huginn uninstall` removes them. Neither needs administrator rights. The exact registry key and directory Thunderbird reads for the registration are to be confirmed from Thunderbird's documentation.
- `huginn auth google` runs the one-time browser sign-in for the tasks adapter.
- A small command-line client covers every endpoint, so a shell script or a person can call it without writing HTTP.

## Implementation choices

- **Repository and licence:** its own repository, separate from Muninn's, under the Apache 2.0 licence.
- **Language:** Python. The core and the mail adapter use the standard library only; the tasks adapter may use Google's sign-in library if doing the sign-in by hand proves fragile.
- **Adapters are modules** with a common small interface (operations, health, fixed rules), so adding one does not touch the others.
- **Platforms:** Windows 10 first, where the first testing happens without containers; Linux next, for a homelab virtual machine that will host Thunderbird, Huginn and the callers.

## Testing

- Unit tests cover the access rules, idempotency, the relay framing and each adapter's fixed rules.
- The mail adapter is tested against a fake Muninn that speaks the same protocol from canned answers; the tasks adapter against a fake Google endpoint.
- Hands-on checks use a dedicated test mail account and a dedicated test task list before any real account or list is made writable.

## Phases

1. **Core and read-only mail.** The service, tokens, health, the relay, the command-line client, and mail reading with Muninn's first phase.
2. **Tasks.** The tasks adapter in full, with the audit log, dry run and the write token. This comes before mail filing because it is independent of Thunderbird and empties the owner's largest backlog.
3. **Mail filing and drafts,** following Muninn's phases.
4. **Calendar read, then the Knarr adapter,** once Knarr's HTTP entry point exists.

## Open questions

1. **Relay socket.** A named pipe on Windows and a Unix socket on Linux, or loopback TCP on both. The first is tidier; the second is one code path. Either carries the owner-only and shared-secret requirements above.
2. **Google sign-in lifetime.** A Google client left in testing status loses its authorization every seven days. A weekly browser confirmation is acceptable to start with; `health` reports the days left so a caller can remind the owner. A longer-lived arrangement is looked at only if that becomes a nuisance.
3. **Per-caller tokens.** Two role tokens to start; a token per job would make the audit log name the job.
4. **Policy engine.** Which engine to adopt when the light rules stop being enough, and whether it sits inside Huginn or in front of it.
