# Backstage Community Coordination Design

Status: design reference
Date: 2026-06-19
Relationship: companion to `2026-06-09-backstage-devex-workspace-design.md`. That document covers how to stand up and work on Backstage as a developer platform. This one covers what to build on top of it for civic and community coordination, and why. Implement this once the base platform is ready.
Provenance: the "Product Shape" through "Fit Assessment" material here was extracted from the original DevEx design's "Community Resource and Volunteer Coordination" appendix and its "Community and Skill Exchange Lite" section, then expanded with thesis, constraints, stranded-asset, and sandbox sections. The civic argument is developed at length on the West Orange schools site (https://schools.frontstate.org) and in two companion blog posts; this doc is the platform-facing distillation, not the advocacy.

## Purpose

This document describes a non-software domain that can still benefit from the Backstage control-plane pattern: a local community platform for youth sports, school-support groups, PTAs, volunteer projects, mentoring, gear swaps, facility coordination, equipment sharing, and similar community operations. The point is not to pretend that cleats, sports fields, volunteer skills, and community groups are software components. The point is to reuse Backstage's strengths — identity, catalog metadata, ownership, docs, search, permissions, plugins, and admin workflows — while giving busy parents and volunteers a simpler purpose-built frontend for day-to-day interaction.

The target reader is an agent or engineer who has a working Backstage instance (per the DevEx design) and is deciding what the first community-facing slices should be, how to keep them grounded, and where to start.

## Why This Is a Separate Document

The DevEx design is about how to set up and work on Backstage: catalog, templates, CI, secrets, plugins, scorecards, auth. It should stay focused on that, because its audience is a platform engineer and its lifecycle is "stand up the base and keep it healthy."

This document is about what to point that base at, and the reasoning behind it. Its audience includes non-engineers (organizers, a skeptical PTA, a board member), its lifecycle is "build when the base is ready," and most of its content is judgment and philosophy rather than setup. Mixing the two made the original doc try to be two things at once. Splitting them lets each stay legible.

## Thesis: Two Kinds of Community Slack

A community under budget pressure is told it has two options: raise taxes or cut services. That is a false dichotomy born of a lack of operational imagination. There is a third path that does not require fixing society at large first, and it runs on slack the community already has but cannot currently coordinate.

There are two kinds of that slack, and the platform exists to put both to use.

### The coordination tax (fractional time)

Mutual aid, time-banking, and solidarity economies are not new. They have always existed and they have always collapsed under the same load: coordination overhead. A human coordinator burns out manually matching spreadsheets, chasing flakes, valuing disparate skills, and backfilling no-shows. Organizing fifty volunteers used to require a full-time, highly stressed person. Coase named the underlying thing decades ago — transaction costs — and they were the ceiling.

The single genuinely new variable, over roughly the last year, is that agentic tooling collapses that specific cost. A part-time organizer, backed by agents that parse messy inbound requests, match availability to need, send reminders, and detect uncovered slots, can run what used to take a full-time coordinator. The coordination tax drops. That is the core of it; it does not need wilder claims to stand.

### Stranded assets (space, equipment, gear)

Coordinating people better is only half of it. The other half is taking stock of what the community already owns and putting it to use instead of letting it sit idle.

- Spaces sit dark: school auditoriums and gyms most evenings and all summer, commercial kitchens sixteen hours a day, meeting rooms, storage closets, parking lots, a neighbor's large garage. Some of these could host events (sometimes paid, which funds the rest), potlucks, classes, or practices.
- Equipment sits in garages: a table saw, a pressure washer, a canopy, a utility trailer, even a small excavator. A neighbor-run heavy-equipment-sharing initiative is exactly this pattern — capital that one household bought and uses twice a year, made available to a block.
- Gear goes stale: outgrown cleats, shin guards, uniforms, and instruments get tossed, or donated into an opaque supply chain where bags and boxes ride trucks to a sorting facility and maybe get used somewhere far away. A direct local handoff — "size 2 cleats, free, pickup at Saturday's game" — keeps the value in the community and removes the middle layer entirely.

This is the Airbnb/Uber insight without the extractive intermediary: idle assets have value, but historically only VC-backed corporations captured it. A community can capture it for itself.

### Why now, and why not wait

The standard utopian script says automation will displace work, so eventually the state will hand everyone universal basic income. That is passive, deferred, and may never arrive at the scale that would matter. The counter-move is that a fractional version works today, with snippets of time, one neighborhood at a time. It does not require Trenton to act or a federal program to materialize; it requires a community to start removing the tolls from its own roads, one at a time.

The framing that makes this concrete is good deflation versus bad deflation. The same tools that let companies cut headcount (bad deflation: displacement into destitution) can let costs drop fast enough that people need less income to begin with (good deflation: freed time and capacity). Those of us whose work these tools are already transforming are positioned to be the starters — to reclaim a sliver of that productivity for where we live, rather than hand all of it upward. This is the Time Dividend: the freed hours that can go to a community not because people have to, but because they now can.

### Extraction removal and the Virtuous Spiral

The systemic diagnosis is developed on the schools site as the Shrinking Slice (the community's share of its own economic pie eroded by layers of rent-seeking that did not exist a generation ago) and the Void (a time-economy thought experiment showing the work was never the expensive part — the intermediaries were). The platform is, in effect, a tool for extraction removal: cutting the toll booths out of local exchange.

The payoff compounds. Unlike natural costs, extraction costs can be removed, and removals stack — what the schools site calls the Virtuous Spiral, or "snowballs, not silver bullets." The first season is grinding. The second is momentum. By the third, the community wonders why it ever accepted the old cost structure. The recipe is globally shareable; the cooking is always local.

## Limits and Constraints (What We Are Not Claiming)

This section matters as much as the thesis. A platform like this attracts utopian overclaiming, and the fastest way to lose a careful reader — or a responsible board — is to wave away the hard parts. The credibility of everything above depends on being clear about the limits below.

### Some cost is Baumol, not extraction

Not every rising line item is a toll. Baumol's cost disease is real: some work cannot be made more productive (a string quartet still takes four players the same hours it did in 1800), so its relative cost rises legitimately as the rest of the economy gets more efficient. Teacher salaries rising is largely this, and it is a thing that should happen. Do not confuse the rent layer with the Baumol layer. The platform targets extraction, not legitimate human-service cost.

### Some scarcity is real

Stripping out billing systems and intermediaries does not strip out genuine scarcity. A community can coordinate its own lawn care and run its own gear swap; it cannot manufacture a GLP-1 drug or a CT scanner. Some things are produced at a scale and complexity beyond local reach, and for those, trade with the outside world is correct and the markup conversation is different. The platform's domain is the large set of local exchanges where the overhead genuinely is the product — not a claim that coordination dissolves all cost.

### Additive and temporary, or it becomes a new extraction

This is the sharpest internal guardrail. The moment community capacity is framed as a substitute for paying people properly — "we have volunteers now, so we do not need to fund this position" — it becomes toxic, and it becomes a new form of extraction, this time of volunteer labor. The relief has to be strictly additive (it claws back margin from corporate vendors and hands it to public employees and the community) and explicitly temporary where it stands in for a real job (scaffolding that comes off once the building stands, not a permanent offload). The "exoskeleton" and "scaffolding" framing exists precisely to manage this: a support structure around the institution, not a replacement for it, and one designed to be removable.

### The open legal question

There is a genuine unresolved blocker: can a district legally accept supplemental community funding earmarked for specific positions, and can volunteers perform work adjacent to paid roles without triggering labor law? If the answer at the para level is no, part of the model has to route around it (see the cooperative-entity pattern below) rather than pretend it is solved. State it plainly in any pitch.

### Liability, FLSA, and the union boundary

The moment a volunteer drives produce for a school or chops a carrot in its kitchen, sovereign immunity, FLSA volunteer rules for public entities, and commercial insurance requirements all engage. These are not bugs to code around; they are hard constraints. The serious answer is to operate through an independent cooperative non-profit entity that contracts with the district, rather than having volunteers work for the district directly. And the union boundary must be explicit and respected: volunteer optimization exists to eliminate corporate vendor contracts (outsourced catering, staffing agencies), never to replace public union jobs. The goal is co-sovereignty — change the funding source, not the employment — and bringing union leadership in early as a coalition partner, not presenting them with a fait accompli.

### Coordination as accountability, not just labor savings

Volunteer programs fail less from lack of goodwill than from lack of reliability: nobody tracks who committed to what, so coverage silently collapses. The institution's recurring, legitimate question is "will people actually show up?" The strongest thing agentic coordination provides is not free labor but accountability infrastructure — commitment tracking, coverage dashboards, a visible volunteer SLA. The answer to the board becomes "here is the data," not "trust our enthusiasm." Design for this from the start; it is the difference between a hobby and something an institution can lean on.

## Product Shape

Use Backstage as the power-user and administrator surface, not necessarily as the only user interface.

- Backstage: admin and operator view for group metadata, activity definitions, resource catalogs, volunteer opportunity configuration, scorecards, audit trails, docs, and integrations.
- Mini-frontend: mobile-first parent and volunteer view for "I can help", "I need this", "I can offer this", "I want to learn", "I can mentor", "I can give/lend this item", and "I can sign up for this shift".
- Backend/API: shared service that owns dynamic data such as offers, needs, claims, reservations, messages, and moderation state.
- Catalog: stable index of groups, activities, programs, facilities, resource categories, and ownership, with links into the mini-frontend for live interactions.

The recommended strategy is a hybrid. Keep stable, owned, documented things in Backstage/catalog-friendly structures; keep volatile marketplace and signup data in an application database behind a custom backend plugin or companion API. A gear-swap listing or volunteer claim should not require editing YAML. Power users (organizers, admins) work inside Backstage; casual users (parents) interact through the lightweight front site, which is backed by the same data.

Backstage's Software Templates also earn their keep here: scaffolding new efforts (a new group, season, activity, or drive) from templates that encode existing practices encourages reuse across organizations, volunteer groups, and efforts rather than each one improvising from scratch.

## Design Principles

- Parent-first UX: assume users are busy, on phones, and not interested in Backstage terminology.
- Adult accounts only by default: avoid child accounts unless there is a deliberate legal/privacy review and a strong need.
- Minimal child data: model age group, grade band, team, season, or size when needed; avoid storing children's names, photos, precise schedules, medical details, or unnecessary education records.
- Private by default: offers, needs, and contact details should be visible only to the relevant group, approved volunteers, or moderators.
- Moderated exchange: gear swaps, facility access, and volunteer roles need moderation, report/flag workflows, and admin audit trails.
- No exact public locations: use managed pickup points, event handoff windows, or moderator-mediated contact rather than public home addresses.
- Time-boxed data: seasons end, children grow, needs expire, and offers get claimed. Every dynamic record should have an expiry or archival path.
- Community trust over gamification: recognition can help, but avoid leaderboards that shame volunteers or expose family circumstances. Note the tension with the accountability goal above — track coverage for reliability, but do not turn contribution into a public scoreboard.

## Architecture Options

| Option | Shape | Pros | Cons | Recommendation |
|---|---|---|---|---|
| Catalog-first | Define custom catalog kinds for groups, activities, resources, facilities, opportunities, and maybe offers/needs | Simple to inspect, easy for admins, strong ownership and docs, low app complexity | YAML is a bad fit for fast-moving inventory, claims, parent UX, privacy, and matching | Useful only for stable objects |
| App/database-first | Build a small community app with its own database and expose a Backstage plugin for admins | Best UX for parents, natural fit for offers/needs/signups, easier privacy controls | More product surface, requires schema/API work, less Backstage-native metadata unless integrated | Good if the community app is the real product |
| Hybrid | Catalog stable objects; database dynamic interactions; Backstage plugin administers both; mini-frontend serves parents | Balances Backstage strengths with real user needs, keeps volatile data out of YAML, supports simple frontend | Requires clear boundaries and integration discipline | Recommended |
| External-tools-first | Start with Google Forms/Sheets, Airtable, GitHub Issues, or a lightweight form tool, then import/index into Backstage | Very fast pilot, low engineering effort, easy to validate demand | Permission sprawl, data quality issues, privacy concerns, hard to scale matching/moderation | Good for discovery, not the long-term platform |
| Marketplace-first | Build gear/resource exchange first, then generalize to volunteering and mentoring | Tangible value, easy adoption before a season, clear workflows | Can overfit to inventory and miss broader community organization needs | Good first mini-frontend slice |
| Volunteer-exchange-first | Build Skill Exchange-style profiles and opportunities first | Aligns with mentoring/learning goals, supports PTAs and community groups | Harder to motivate without concrete activities, more privacy-sensitive | Better as the second slice |

## Suggested Domain Objects

Do not force these into Backstage's `Component` kind. Create domain-specific kinds or database tables with clear names.

| Object | Purpose | Stable or Dynamic | Backstage Fit |
|---|---|---|---|
| `CommunityGroup` | PTA, sports league, team, committee, booster group, local nonprofit, school-support group | Stable | Strong catalog fit |
| `Program` or `Season` | Soccer season, school year, fundraising drive, tournament, reading program | Stable-ish | Good catalog fit |
| `Activity` | Gear swap, volunteer day, field cleanup, tournament support, fundraiser, mentoring night, auditorium event | Stable-ish | Good catalog fit when activity has owners/docs |
| `Opportunity` | A need for help, mentoring, reviewing, coaching, setup, cleanup, translation, carpentry, grant writing, etc. | Dynamic or semi-stable | Hybrid |
| `VolunteerProfile` | Adult's skills, interests, availability, learning goals, mentoring offers, preferred groups | Dynamic and private | App database, Backstage admin summary |
| `Skill` or `Interest` | Controlled vocabulary for what volunteers can do, teach, or want to learn | Stable | Catalog/config fit |
| `ResourceType` | Cleats, shin guards, uniforms, cones, tents, tables, coolers, laptops, books, tools, facility access | Stable | Catalog/config fit |
| `ResourceOffer` | "I have size 2 cleats to give/lend" or "I can loan a canopy for Saturday" or "I have a table saw available" | Dynamic | App database |
| `ResourceNeed` | "Need size 3 cleats" or "Need two tables for the event" | Dynamic | App database |
| `Facility` | Sports field, gym, auditorium, meeting room, storage closet, concession stand, parking lot, garage | Stable | Catalog fit with access controls |
| `Reservation` | Time-boxed booking or claim for a facility, item, or volunteer shift | Dynamic | App database |
| `Transfer` | Matched handoff between an offer and a need | Dynamic and sensitive | App database with audit |
| `Policy` | Rules for eligibility, privacy, pickup, donations, facility use, background checks, and data retention | Stable | Docs/TechDocs fit |

## Activity Patterns

- Gear swap: parents list give-away or lendable items by category, size, condition, season, and pickup method; other parents request or claim; moderators can approve, hide, expire, or mark fulfilled.
- Volunteer signup: organizers publish shifts, roles, required skills, background-check requirements, and time windows; volunteers claim slots; admins see coverage gaps.
- Skill exchange: adults list skills they can teach, mentor, or contribute and skills they want to learn; opportunities can request skills without exposing private personal details broadly.
- Facility and equipment coordination: groups can request fields, rooms, auditoriums, storage, tables, tents, tools, or sports gear; admins can approve reservations or route requests to the right owner.
- Community project board: local groups publish project ideas and needed help, linked to GitHub Issues/Projects if the work is technical or to a simpler task board if it is operational.
- Donation and resource drives: organizers publish target resources, quantities, deadlines, accepted conditions, drop-off rules, and fulfillment status.
- Season readiness checks: a scorecard-like view can show whether a season has coaches, background checks, field reservations, gear coverage, emergency contacts, docs, and volunteer slots ready.

## Stranded Asset Utilization

This is the second pillar from the thesis, made operational. Beyond coordinating people, the platform takes inventory of underused physical capacity and matches it to need. Three sub-domains, increasing in difficulty:

### Gear (the cleat exchange — start here)

The simplest, most concrete entry point, and a natural first pilot. Outgrown soccer cleats, shin guards, uniforms, skates, and instruments cycle through families constantly. Today they go stale in a closet, get tossed, or get donated into an opaque supply chain. A dead-simple cleat exchange — a group chat plus a light inventory of `ResourceOffer`/`ResourceNeed` keyed on category, size, and season — captures that value locally. It is seasonal, legible to any sports parent, low-stakes, and privacy-light (no child names; "size 2 cleats for U8" not "Jimmy's cleats"). It is also the canonical first slice in the pilot section below.

### Equipment (lending, with care)

Higher-value, higher-trust: tables, tents, coolers, canopies, pressure washers, a table saw, a utility trailer, even a small excavator. A neighbor-run heavy-equipment-sharing effort already demonstrates the pattern. The platform models these as lendable `ResourceType`/`ResourceOffer` with `Reservation` windows. The added difficulty is real (liability for borrowed equipment, condition disputes, scheduling), so this should follow the gear-swap pilot, lean on moderator-mediated handoff, and stay opt-in.

### Spaces (the highest-value, highest-friction)

School auditoriums and gyms sit dark most evenings and all summer; a neighbor's large garage, a community room, a commercial kitchen. These can host events (sometimes paid, where the fee funds other community efforts), potlucks (for example at the Mountain Top League House), classes, practices, and meetings. Facility access is the most institutionally entangled (insurance, custodial cost, district policy, who is liable), so model it as `Facility` + `Reservation` behind admin approval, and treat externally-funded events on school facilities as a known existing pathway worth formalizing rather than inventing.

### Direct local handoff vs. the donation supply chain

A common thread across all three: a direct local match removes the middle layer. Bags of donated gear on a truck to a regional sorting facility, maybe used somewhere far away, is the extraction pattern applied to charity logistics — opaque, lossy, and disconnected from the people who gave. "Free, pickup at Saturday's game" keeps the value, the relationship, and the accountability inside the community. The platform should make the direct local path the path of least resistance.

## Skill and Opportunity Exchange

Spotify's Skill Exchange is commercial, but the idea is straightforward to pilot in open-source Backstage, and it serves two adjacent audiences with the same model:

- The volunteer-organizer case (this document's focus): adults offering "can mentor", "can help", "can coach", "want to learn", matched to community opportunities.
- The developer-community case (kept in the DevEx design as a Backstage plugin): contributors offering mentoring, pairing, reviewer-needed, plugin-maintainer-needed, linked to GitHub Issues/Projects.

Shared model:

- Define an `Opportunity` catalog kind or a custom plugin data model with fields for type, owner, skills offered/needed, time window, expected commitment, link to a work item, and status.
- Support types such as `mentoring`, `pairing`, `temporary-help`, `coaching`, `setup-cleanup`, `reviewer-needed`, and `translation`.
- Render opportunities on group pages, activity pages, and (for the dev case) team and user pages.
- Integrate with an existing work queue (GitHub Issues/Projects for technical work; a simple task board for operational work) instead of building a full task tracker.
- Add lightweight notifications through Backstage Notifications, chat, SMS, or email later.

This should be a second-phase slice, not part of the first bootstrap. Start with the gear swap, then add skill/opportunity exchange once the fields and trust have stabilized.

## Parent Mini-Frontend Ideas

The mini-frontend should not look or feel like Backstage. It should be a focused web app, probably installable/PWA-style, with a small number of flows.

- A landing screen with three actions: `Offer`, `Need`, and `Volunteer`.
- Fast filters for group, season, age/grade band, item size, activity date, location area, and pickup/drop-off method.
- "I have extra gear" flow with category, size, condition, photo optional, give/lend, preferred handoff, expiry date, and visibility.
- "I need gear" flow with category, size, needed-by date, acceptable condition, and whether a loan is acceptable.
- "I can help" flow with skills, availability, preferred groups, background-check status if applicable, and mentoring/learning interests.
- "I want to learn" flow for adults who want coaching, mentoring, first-aid training, scorekeeping, event organizing, grant writing, technical help, or other skills.
- Match suggestions that reveal only enough information to proceed, with contact details hidden until both sides opt in or a moderator approves.
- Moderator handoff mode for sensitive exchanges, where the system routes both parties to a public pickup point or event table instead of sharing direct contact details.
- Expiry nudges before a season starts: "these offers expire Friday", "these needs are still open", "this activity is short two volunteers".
- Meet people where they already are: a friendly SMS thread ("the league needs a hand moving cones to Field 3 tomorrow; you're scheduled there at 8:45 anyway — reply YES to claim") removes the onboarding barrier entirely. To the user it should feel like a highly organized neighbor, not a platform.

## Backstage Admin and Power-User Surface

Backstage should give organizers the richer view that ordinary parents do not need.

- Catalog pages for `CommunityGroup`, `Program`, `Activity`, `Facility`, and `ResourceType`.
- Entity cards showing open needs, available offers, volunteer coverage, upcoming events, stale listings, and moderation queue counts.
- Docs pages for rules, volunteer onboarding, background-check process, gear condition guidelines, facility use, and season playbooks.
- Search across groups, activities, facilities, docs, and public resource categories.
- Permission-controlled admin routes for approving groups, editing taxonomies, seeing reports, handling moderation, and exporting summaries.
- Backend scheduled tasks for expiring old offers/needs, sending reminders, detecting uncovered volunteer slots, and archiving completed seasons.
- Notifications for organizers when critical roles are unfilled or resource needs remain open near a deadline.
- Optional scorecards for readiness and coverage, framed as operational status rather than team judgment.

## Data and Privacy Notes

This domain involves children, schools, families, locations, volunteer eligibility, and potentially sensitive need signals. Treat privacy and safety as primary product requirements.

- Avoid collecting personal information from children. The FTC's COPPA guidance is relevant if an online service is directed to children under 13 or knowingly collects personal information from them.
- Avoid treating the system as a school records system. If the platform interacts with a school district or education records, FERPA and district policy may apply; keep the community app focused on adult volunteers and non-educational operational data unless reviewed.
- Keep child identity out of inventory exchange. Prefer "size 2 cleats needed for U8 soccer" over child names.
- Do not store home addresses by default. Prefer pickup sites, event handoff windows, or moderator-mediated exchange.
- Use role-based visibility: parent, organizer, group admin, district liaison, moderator, system admin.
- Keep audit logs for moderator/admin actions, claim state changes, and permission changes.
- Add abuse/reporting workflows before broad rollout, even if they are simple.
- Define data retention early: expire unclaimed gear offers, archive old seasons, delete stale personal preferences, and give adults a way to remove their profile.

## Matching Strategies

| Strategy | How it works | Pros | Cons |
|---|---|---|---|
| Manual browse | Users search/filter offers and needs themselves | Simple, transparent, low risk | Requires user effort, weak at scale |
| Moderator matching | Organizers see likely matches and coordinate handoff | Safer for sensitive communities, good for early trust | More admin work |
| Rule-based matching | Match category, size, group, season, location area, condition, and dates | Predictable, explainable, easy to test | Can miss nuanced cases |
| Preference-aware matching | Use volunteer interests, skills, availability, and learning goals | Better for Skill Exchange-style volunteering | More profile data and privacy surface |
| Recommendation engine | Rank opportunities/resources automatically | Powerful later | Too complex and potentially opaque for MVP |

Start with manual browse plus moderator matching. Add rule-based matching once the fields stabilize. Defer recommendation-style matching until there is enough usage and trust. Note that "the agents will optimize a multi-party value chain automatically" is the failure mode to avoid early — it is opaque, hard to trust, and overpromises; explainable rule-based matching earns trust first.

## First Pilot Slice

A useful first slice is a gear-swap MVP — concretely, the cleat exchange — because it is tangible, seasonal, low-stakes, and easy for families to understand.

1. Define `CommunityGroup`, `Program`, `Activity`, `ResourceType`, and `Facility` as stable catalog-backed concepts.
2. Build a small backend table/API for `ResourceOffer`, `ResourceNeed`, `Transfer`, and moderation state.
3. Build a parent mini-frontend with `Offer`, `Need`, browse, claim/request, and expiry.
4. Add a Backstage admin plugin page for open needs, offers, stale listings, moderation, and simple exports.
5. Keep identity adult-only through Keycloak/OIDC or another community identity source.
6. Run one season-bound gear swap with a few resource categories and explicit pickup rules.
7. After the pilot, decide whether the next slice is volunteer signup, skill/opportunity exchange, equipment lending, facility reservations, or community project boards.

## Sandbox-First: Why the Youth Sports League

Do not pitch this to a Board of Education or a formal PTA first. There you hit bureaucracy, sovereign liability, risk mitigation, and ego, and institutions structurally cannot grant permission to optimize themselves. So do not ask; build the efficiency on the outside until the institution chooses to absorb it.

The youth sports league is the ideal sandbox. Unlike the district it lacks both formal liability protection and a large taxpayer budget, but it runs on absolute parental burnout, the red tape is thin, and the pain is sharp: if equipment logistics break, the game does not happen. The stakes are low enough to experiment and high enough that people feel genuine relief when it works. The first micro-module is the gear/equipment and carpool mesh, with the cleat exchange as the warmest concrete entry. Show the league president a season-end dashboard ("this saved our families N driving hours and a few thousand dollars, and recirculated M pairs of cleats"), not an economic theory.

The mechanism is to wrap the community's messy reality rather than replace it: if the league lives in a chaotic group chat, a background agent ingests that noise, extracts intent ("need three parents for field prep Saturday"), and coordinates over SMS. The technology stays invisible. The ethical line to hold: invisible-and-accountable is good; invisible-and-unaccountable is how you coordinate people through a system they cannot see or question. Keep it legible and opt-in.

## Forward-Looking and Aspirational

These are deliberately beyond the MVP. Record them; do not build them first.

- Semantic orchestration of chaos: agents that turn fragmented, erratic human availability into reliable scheduled operations by parsing free-text channels and dynamically rerouting around no-shows. This is the long-term version of the coordination-tax-drop, and it is what distinguishes this moment from the DAO/tokenomics attempts that mistook financial incentives for operational capability.
- A negotiating agent per person: a personal agent that, with consent, knows your calendar and offers ("you have a free window and an empty trunk, and you are a mile from the farm — want to intercept this delivery?"). This is the most forward-looking capability and also the most privacy-sensitive — it reads your messages and schedule. Treat it as aspirational, opt-in, and eyes-open, never a default.
- SMS-first, zero-onboarding, invisible wrapper: no app to download, no password, no platform to learn; interaction through the channels people already use. The MVP version of this is dumb and that is fine.

## Later Expansion Ideas

- Volunteer skill profiles with "can mentor", "can help", and "want to learn" sections.
- Activity templates for gear swap, fundraiser, field cleanup, tournament support, PTA event, reading night, auditorium event, and community tech help.
- Facility calendar and request workflow for fields, gyms, auditoriums, rooms, and storage.
- Equipment-lending registry with reservation windows, condition tracking, and moderator-mediated handoff.
- Junior-coach pathway support: high-schoolers coaching the youth sport they grew up in, with community-service-hour tracking, background-check flags, and certification links.
- Background-check eligibility flags for roles that require it, stored minimally and visible only to authorized organizers.
- Resource kits for recurring activities, such as "soccer season starter kit", "field day kit", or "fundraiser table kit".
- Group playbooks in TechDocs, linked directly from activities and volunteer roles.
- Integration with GitHub Issues/Projects for technical community efforts, while nontechnical tasks remain in the simpler mini-frontend.
- Public read-only pages for approved activities and needs, with private details hidden.
- Lightweight impact reporting: fulfilled needs, volunteer slots covered, gear reused, estimated savings, dollars recirculated, and unresolved gaps.

## Fit Assessment

This design stretches Backstage beyond its original software-catalog center, but the fit is reasonable if Backstage is treated as the admin/control-plane and not forced to be the parent-facing marketplace UI. The strongest overlap is ownership, metadata, documentation, permissions, search, workflows, and extension points. The weakest overlap is high-churn human interaction: claims, messaging, handoffs, personal preferences, inventory state, and mobile-first UX. That weak area should be handled by a small custom frontend and database, with Backstage used to configure, inspect, and operate it.

## Relationship to Demicracy and the Broader Toolkit

The coordination engine described here is the platform foundation that the volunteering and advocacy work has been pointing toward — branded Demicracy, under the frontstate.org banner, with the civic argument hosted at https://schools.frontstate.org. The DevEx design (`2026-06-09-backstage-devex-workspace-design.md`) covers the Backstage base; this document covers the community content built on it; and the two companion blog posts (a technical and an accessible variant, dated 2026-06-19) carry the public-facing version of the argument. Keep the named tooling references light: the value here is the pattern, which is meant to be shareable, with the implementation always local.
