# Muninn — a send-proof Thunderbird extension for agents: design

**Status:** Draft for review. No code exists yet.
**Date:** 2026-11-27
**Owner:** Rasmus Praestholm
**Arc:** `pkm-life-organization` on the Dionysus thalamus
**Related:** the [Huginn design](2026-11-27-huginn-design.md) (the local service agents call; Muninn is what stands behind its mail adapter) · the [Knarr design](2026-04-02-knarr-design.md) (the lane for chat and social content, and for notifying the owner) · the PKM v2 workflow design in the owner's private vault (the first user of both ravens)

## The outcome

An agent or script on the owner's machine can read, search, file and tag mail across every account Thunderbird already syncs, and can leave a reply as a draft for the owner to review. It cannot send mail and cannot permanently delete mail, and that limit is set by the permissions the extension asks Thunderbird for, not by the caller behaving well. A move into Trash or Junk is still a move, which the permission list allows; Muninn's own code refuses those.

Muninn does have write access to mail: filing a message into a folder, tagging it and saving a draft all change what is on the mail server. That is intended. What it lacks is the ability to send or to remove.

Thunderbird already holds the credentials and the synced mail, so no new token is issued to any agent. This matters most for Gmail, where every permission that can create a draft or change a label can also send.

## Vocabulary

| Term | Meaning |
|---|---|
| **Muninn** | Old Norse, *memory*; one of Odin's two ravens. The Thunderbird extension, and everything that runs on the Thunderbird side. It does what Huginn asks within its permission list and its two fixed rules. |
| **Huginn** | Old Norse, *thought*; the other raven. A local service that runs on its own and gives agents one interface to mail, tasks and more. Mail is one of its adapters, and Muninn is how that adapter reaches Thunderbird. Its design is a separate document. |
| **Relay** | A tiny program shipped with Huginn that Thunderbird starts when Muninn asks. It passes messages between Muninn and the running Huginn. |
| **Caller** | Anything that asks Huginn for something: a scheduled agent run, a script, a person at a terminal. |
| **Send-proof** | The extension's manifest does not request either permission that allows sending, so no code path in it can send, whatever it is asked. |

## Scope

In scope for the first version:

1. List accounts, identities and folders.
2. Search messages and read one message: headers, plain-text body, attachment names and sizes.
3. Move and copy messages between folders, add and remove tags, mark read or flagged. Archiving is a move to an archive folder, not a separate operation.
4. Save a new message or a reply as a draft in the account's Drafts folder.
5. Report its own version and granted permissions, so Huginn can refuse to run against a build that has more than it should.

Out of scope:

- Sending, in any form.
- Deleting messages or folders, and moving messages into Trash or Junk.
- Reading attachment contents. A later version may add it with a size limit.
- Calendar and tasks. Thunderbird has no stable extension interface for either; see *Calendar and tasks* below.
- Creating or editing message filters. Thunderbird has no stable interface for it.

## Shape

```text
 caller ──HTTP, localhost, bearer token──▶ Huginn ◀──relay◀──native messaging── Muninn ──▶ Thunderbird ──IMAP──▶ mail servers
                                           (tokens, audit log)                  (permission floor, fixed rules)
```

An extension cannot be reached from outside Thunderbird; it has to open the connection itself. When Thunderbird starts, Muninn opens a native-messaging port, which makes Thunderbird launch the relay, and the relay connects to the Huginn service that is already running. Requests then flow from Huginn to Muninn and answers flow back. If Huginn is not running, the relay exits and Muninn tries again at intervals.

Muninn never listens on a network socket and holds no network permission. Native messaging is the one channel an extension can open without one, which is why the relay exists.

## Permissions

The manifest requests exactly these, and the list is the security boundary:

| Permission | Why |
|---|---|
| `accountsRead` | List accounts, identities and folders |
| `messagesRead` | Search and read messages |
| `messagesMove` | Move and copy |
| `messagesUpdate` | Read and flagged state |
| `messagesTags` | Add and remove tags |
| `messages.save` | Save a draft in the background, through `messages.saveMessage` (also needs `messagesRead`) |
| `nativeMessaging` | Talk to Huginn through the relay |

Never requested: `messages.send`, `compose.send`, `compose` and `compose.save` (no compose window is ever opened), `messagesDelete`, `accountsFolders` (create, rename and delete folders), `messagesImport`, and any host permission. A test in the component reads the manifest and fails if the list grows without the test being changed in the same commit, so widening it is always a visible, reviewed act.

`messages.saveMessage` is available from Thunderbird 153, which sets the extension's minimum version.

One thing to confirm against Thunderbird's documentation during implementation: that no permission in the list above implies sending through another route.

## Operations

Every request is a JSON object with an `id`, an `op` and `params`; every answer carries the same `id` with either `result` or `error`. Huginn's design owns the wire format; this is the list Muninn implements.

| Op | Does | Notes |
|---|---|---|
| `info` | Version, Thunderbird version, granted permissions | Called first on every connection |
| `accounts.list` | Accounts with identities | No credentials are ever returned |
| `folders.list` | Folder tree for one account | Includes special-use flags (Inbox, Drafts, Trash, Junk) |
| `messages.search` | Query by folder, sender, subject, date range, tag, read state, text | Paged; returns headers only |
| `messages.get` | One message: headers, plain-text body, attachment list | Body is truncated at a size limit and says so |
| `messages.move` | Move a list of messages to a folder | Refused when the target is a Trash or Junk folder |
| `messages.copy` | Copy a list of messages to a folder | Same refusal |
| `messages.update` | Read and flagged state, tags | |
| `drafts.save` | Save a new message or a reply to a given message as a draft | Returns the draft's message id |

A folder move on an IMAP account is an operation on the mail server. Thunderbird's local folder files are a cache; nothing local is edited directly, and on Gmail a move into a folder applies that label.

## Fixed rules in Muninn

Two limits are enforced in Muninn's own code, beside the permission list:

- **No moves or copies into Trash or Junk.** Thunderbird marks those folders by type, so Muninn checks the target folder at the moment of the move and refuses. A move to Trash is deletion by another name, and refusing it here means no configuration elsewhere can allow it.
- **Only the listed operations.** Muninn answers only on the native-messaging port it opened itself and rejects any `op` not in the table above.

These are weaker than the permission list, since code can have bugs where a missing permission cannot, and a test covers each. One case to check during implementation: on Gmail, whether any ordinary folder move has the effect of trashing a message.

## What Muninn does not decide

Muninn is deliberately thin. Which accounts a caller may change and what gets logged are Huginn's job. The split keeps the part that runs inside Thunderbird small enough to read in one sitting.

## Mail content is untrusted

A message body can contain text written to steer an agent. Muninn returns bodies as data in a field of their own and never interprets them. Through Muninn, a misled caller can misfile mail, mis-tag it and leave unwanted drafts. Muninn itself cannot send, permanently delete or reach anything outside Thunderbird's mail store.

That limit covers Muninn only. A caller that also holds network or file tools can read a message through Muninn and pass it on through those, so what else a mail-reading job may use is a decision for whoever configures the job.

## Calendar and tasks

Not in Muninn for now. Thunderbird's extension interfaces for mail are stable; for calendar and tasks there is none yet. A calendars-and-items interface has a patch in review with no target version. The only route inside Thunderbird today is Experiment code, which the monthly release channel is set to stop accepting; the removal is postponed with no published replacement list.

An extension also cannot use the Google sign-ins Thunderbird holds for anything beyond what Thunderbird itself does with them, so Muninn is no shortcut to Google's own interfaces.

Tasks and calendar are therefore adapters in Huginn that go to Google directly; see that design. Muninn could take them on if a stable interface ships. Upstream work to check back on:

- [Bugzilla 2035321](https://bugzilla.mozilla.org/show_bug.cgi?id=2035321), a calendars-and-items extension interface, with patch [D296842](https://phabricator.services.mozilla.com/D296842) in review as of 2026-11-27 and no target version.
- [kewisch/gdata-provider#1123](https://github.com/kewisch/gdata-provider/pull/1123), the open change on the rewrite of Provider for Google Calendar, the add-on that shows Google calendars and task lists inside Thunderbird today through Experiment code.

## Prior art

- [`vitalio-sh/thunderbird-cli`](https://github.com/vitalio-sh/thunderbird-cli) (MIT) uses stable interfaces only and is the model for this design. It was read, not run.
- [`TKasperczyk/thunderbird-mcp`](https://github.com/TKasperczyk/thunderbird-mcp) is the most used of the agent-facing extensions and is built on Experiment code, which is the route this design avoids.
- Other projects read the Thunderbird profile from disk, and one decrypts stored credentials to do it. This design never reads the profile.

Writing our own is a choice for a short permission list we control and can test, not a claim that the existing projects are poor.

## Packaging and install

- Its own repository, separate from Huginn's, under the Apache 2.0 licence.
- Plain JavaScript, no build step, Manifest V3.
- Installed from a file (`.xpi`) or loaded temporarily while developing. Listing it on Thunderbird's add-on site is a later decision.
- The extension declares a minimum Thunderbird version matching what `drafts.save` needs.

## Testing

- Unit tests run the operation handlers against a faked `browser` object, including the manifest test described under *Permissions*.
- A smoke checklist against a dedicated test mail account comes before any real account is touched: search, read, move there and back, try a move to Trash and see it refused, tag, save a draft, and confirm in Thunderbird's own add-on page that no send permission is listed. The owner has a spare account set aside for this, so the checklist can later run automatically.

## Phases

1. **Read-only.** `info`, `accounts.list`, `folders.list`, `messages.search`, `messages.get`. The manifest carries only the read permissions and `nativeMessaging`.
2. **Filing.** Move, copy, update, with the permissions they need.
3. **Drafts.** `drafts.save`, with the `messages.save` permission.

Each phase is a separate change request, so each widening of the permission list gets its own review.

## Open questions

1. **Background lifetime.** Whether a Manifest V3 background script with an open native-messaging port stays alive for the whole Thunderbird session, or needs a keep-alive. To be tested first. Since Huginn runs on its own, a dropped port costs a reconnect, not the service.
2. **Body format.** Plain text only, or also the HTML part for messages that have no plain-text part.
