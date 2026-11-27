# Muninn — a send-proof Thunderbird extension for agents: design

**Status:** Draft for review. No code exists yet.
**Date:** 2026-11-27
**Owner:** Rasmus Praestholm
**Arc:** `pkm-life-organization` on the Dionysus thalamus
**Related:** the [Huginn design](2026-11-27-huginn-design.md) (the local bridge this extension talks to; the two are one system in two components) · the [Knarr design](2026-04-02-knarr-design.md) (the lane for chat and social content, and for notifying the owner) · the PKM v2 workflow design in the owner's private vault (the first user of both ravens)

## The outcome

An agent or script on the owner's machine can read, search, file and tag mail across every account Thunderbird already syncs, and can leave a reply as a draft for the owner to review. It cannot send mail and cannot permanently delete mail, and that limit is set by the permissions the extension asks Thunderbird for, not by the caller behaving well. A move into Trash or Junk is still a move, which the permission list allows; Huginn's policy is the guard against those.

Thunderbird already holds the credentials and the synced mail, so no new token is issued to any agent. This matters most for Gmail, where every permission that can create a draft or change a label can also send.

## Vocabulary

| Term | Meaning |
|---|---|
| **Muninn** | Old Norse, *memory*; one of Odin's two ravens. The Thunderbird extension. It holds no policy of its own beyond its permission list and does what Huginn asks within it. |
| **Huginn** | Old Norse, *thought*; the other raven. The local bridge process that Thunderbird starts and that callers reach. Its design is a separate document. It shares its name with an unrelated automation project. |
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
- Deleting messages or folders. Moves into Trash or Junk are refused by Huginn's policy; see that design.
- Reading attachment contents. A later version may add it with a size limit.
- Calendar and tasks. Thunderbird has no stable extension interface for either; see *Calendar and tasks* below.
- Creating or editing message filters. Thunderbird has no stable interface for it.

## Shape

```text
 caller ──HTTP, localhost, bearer token──▶ Huginn ──native messaging──▶ Muninn ──▶ Thunderbird ──IMAP──▶ mail servers
                                           (policy, audit log)          (permission floor)
```

Muninn opens the native-messaging port when Thunderbird starts, which makes Thunderbird launch Huginn. Requests then flow from Huginn to Muninn over that port and answers flow back. Muninn never listens on a network socket.

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
| `nativeMessaging` | Talk to Huginn |

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
| `messages.move` | Move a list of messages to a folder | |
| `messages.copy` | Copy a list of messages to a folder | |
| `messages.update` | Read and flagged state, tags | |
| `drafts.save` | Save a new message or a reply to a given message as a draft | Returns the draft's message id |

A folder move on an IMAP account is an operation on the mail server. Thunderbird's local folder files are a cache; nothing local is edited directly, and on Gmail a move into a folder applies that label.

## What Muninn does not decide

Muninn is deliberately thin. Which accounts a caller may touch, how many messages one request may move, whether Trash is an allowed target, and what gets logged are all Huginn's job. The split keeps the part that runs inside Thunderbird small enough to read in one sitting, and keeps the hard limit (the permission list) separate from the adjustable one (policy).

Muninn does enforce two things on its own, as a second line: it answers only on the native-messaging port it opened itself, and it rejects any `op` not in the table above.

## Mail content is untrusted

A message body can contain text written to steer an agent. Muninn returns bodies as data in a field of their own and never interprets them. Through Muninn, a misled caller can misfile mail, mis-tag it and leave unwanted drafts. Muninn itself cannot send, permanently delete or reach anything outside Thunderbird's mail store.

That limit covers Muninn only. A caller that also holds network or file tools can read a message through Muninn and pass it on through those, so what else a mail-reading job may use is a decision for whoever configures the job.

## Calendar and tasks

Not in Muninn for now. Thunderbird's extension interfaces for mail are stable; for calendar and tasks there is none yet. A calendars-and-items interface has a patch in review with no target version. The only route inside Thunderbird today is Experiment code, which the monthly release channel is set to stop accepting; the removal is postponed with no published replacement list.

So for the first users of this design: tasks are read through the Google Tasks API by a separate job with a tasks-only permission, and an agent-proposed calendar is a local `.ics` file Thunderbird subscribes to. Muninn takes calendar and tasks on when a stable interface ships.

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
- A manual smoke checklist against a throwaway mail account and a scratch folder comes before any real account is touched: search, read, move there and back, tag, save a draft, and confirm in Thunderbird's own add-on page that no send permission is listed.

## Phases

1. **Read-only.** `info`, `accounts.list`, `folders.list`, `messages.search`, `messages.get`. The manifest carries only the read permissions and `nativeMessaging`.
2. **Filing.** Move, copy, update, with the permissions they need.
3. **Drafts.** `drafts.save`, with the `messages.save` permission.

Each phase is a separate change request, so each widening of the permission list gets its own review.

## Open questions

1. **Background lifetime.** Whether a Manifest V3 background script with an open native-messaging port stays alive for the whole Thunderbird session, or needs a keep-alive. To be tested first, since the whole shape rests on it.
2. **Body format.** Plain text only, or also the HTML part for messages that have no plain-text part.
