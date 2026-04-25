# MTL Site Design — Static GitHub Pages for Mountain Top League

**Date:** 2026-04-08
**Component:** `mtl-site` (SiliconSaga/mtl-site)
**Status:** Draft

## Overview

A static Jekyll site hosted on GitHub Pages that serves as a clean, mobile-friendly
facade for Mountain Top League (MTL) — an all-volunteer youth sports organization
in West Orange, NJ, founded in 1959. The site replaces poorly organized PDF rules
documents with focused, per-age-group pages optimized for coaches and parents
reading on their phones at the field.

### Goals

1. Convert existing soccer rules PDFs into focused, mobile-first web pages
2. Provide a clean alternative frontend to the existing TeamSnap-powered WordPress
   site at mountaintopleague.com
3. Make rules instantly accessible by age group — one tap to exactly what you need
4. Support printable output via CSS print stylesheet
5. Stub out non-soccer sports with links to the existing site
6. Use the Git repo as a documentation hub beyond what's published

### Non-Goals

- No blog or news system (TeamSnap handles announcements)
- No registration integration (link out to TeamSnap)
- No search (site is small enough for navigation)
- No schedules or score reporting
- No JavaScript beyond a mobile nav toggle

## Hosting & URLs

- **Repo:** SiliconSaga/mtl-site
- **Published URL:** siliconsaga.github.io/mtl-site
- **Build:** GitHub Pages native Jekyll — no GitHub Actions, no local tooling required
- **Editing:** Markdown files editable directly in GitHub's web editor

This is initially a proposal/prototype. If adopted by the MTL board, the repo could
transfer to an MTL org and map to a custom domain.

## Site Structure & Navigation

Mirrors the current mountaintopleague.com navigation:

```
Home
About Us
Sports ▾
  Baseball (stub)
  Basketball (stub)
  Hockey (stub)
  Soccer
    Overview (program info, age-group picker)
    Rules: Little Kickers
    Rules: 1st/2nd Grade (4v4)
    Rules: 3rd-6th Grade (7v7/9v9)
    Referee Guide
    Game Day Guide (parents/coaches)
    Formations & Positions
  Softball (stub)
Contact Us
```

### Soccer Overview as a Picker

The soccer overview page acts as a quick-reference hub with large tappable
cards/buttons:

- "I'm coaching Little Kickers" → /soccer/little-kickers/
- "I'm coaching 1st/2nd Grade" → /soccer/4v4/
- "I'm coaching 3rd-6th Grade" → /soccer/7v7-9v9/
- "I'm a referee" → /soccer/referee-guide/
- "I'm a parent" → /soccer/game-day/

## Jekyll File Structure

```
mtl-site/
  _config.yml              # Site config, title, baseurl: /mtl-site, nav
  _layouts/
    default.html           # Header, nav, footer wrapper
    page.html              # Standard content page
    rules.html             # Rules page with age-group badge, print button
    stub.html              # Stub sport page with link to main MTL site
  _includes/
    nav.html               # Navigation (mirrors MTL structure)
    footer.html            # Footer with MTL branding
    print-button.html      # "Print this page" snippet
  _data/
    sports.yml             # Sport names, links, stub vs. active
    age_groups.yml         # Age groups with metadata (ball size, field dims, etc.)
  _sass/
    _base.scss             # Typography, colors (MTL blue palette)
    _nav.scss              # Navigation styles including mobile hamburger
    _print.scss            # @media print — clean single-page output
  assets/
    css/style.scss         # Main stylesheet entry
    images/                # MTL logo, field diagrams
    pdf/                   # Future: manually generated PDFs if needed
  index.md                 # Home page
  about.md                 # About MTL
  contact.md               # Contact info + MTLsoccer@gmail.com
  soccer/
    index.md               # Soccer program overview (age-group picker)
    little-kickers.md      # Rules: Little Kickers (ages 4-5)
    4v4.md                 # Rules: 1st/2nd Grade
    7v7-9v9.md             # Rules: 3rd-6th Grade
    referee-guide.md       # Consolidated referee responsibilities
    game-day.md            # Parent/coach guide (placeholder for v1)
    formations.md          # Position diagrams (CSS/HTML)
  baseball/
    index.md               # Stub
  basketball/
    index.md               # Stub
  hockey/
    index.md               # Stub
  softball/
    index.md               # Stub
  _docs/                   # NOT published (underscore = Jekyll ignores it)
    coaching-notes/        # Personal coaching tips, drill ideas
    archives/              # Original PDFs for reference
```

## Styling & Branding

- **Primary color:** Dark navy blue (matching MTL's existing branding)
- **Text:** White on blue for header/nav, dark text on white/light-gray for content
- **Typography:** System font stack — no web font dependencies
- **Layout:** Single-column, max-width ~800px, sticky top nav
- **Mobile:** Responsive from the start, hamburger nav on small screens
- **No:** Hero images, carousels, animations, heavy JS

### Print Stylesheet

- Hides nav, footer, print button
- Removes background colors
- Sizes text for paper (12pt base)
- Each rules page produces a clean single-page printout
- If CSS print proves insufficient, PDFs can be generated using a PDF
  authoring tool and committed to `assets/pdf/` as downloadable links

## Content Model

### Structured Data: `_data/age_groups.yml`

Quick-reference facts live in a single YAML file and are pulled into rules
pages as a summary card at the top of each page:

```yaml
little_kickers:
  label: "Little Kickers"
  ages: "4-5"
  format: "4v4"
  goalie: false
  ball_size: "3 or 4"
  field_length: "25-35 yards"
  field_width: "15-25 yards"
  goal_size: "4ft x 6ft"
  game_duration: "25 min practice + 25 min game"
  halves: null
  referee: false
  heading_allowed: false
  throw_ins: false
  corner_kicks: false
  goal_kicks: false
  free_kicks: false
  offside: false

first_second_grade:
  label: "1st/2nd Grade"
  ages: "6-8"
  format: "4v4"
  goalie: false
  ball_size: "3 or 4"
  field_length: "25-35 yards"
  field_width: "15-25 yards"
  goal_size: "4ft x 6ft"
  game_duration: "Two 20-minute halves"
  halves: "20 min"
  halftime: "3 min"
  referee: true
  heading_allowed: false
  throw_ins: false
  corner_kicks: true
  goal_kicks: true
  free_kicks: true
  offside: false

third_fourth_grade:
  label: "3rd/4th Grade"
  ages: "8-10"
  format: "7v7"
  goalie: true
  ball_size: "4 or 5"
  field_length: "55-65 yards"
  field_width: "35-45 yards"
  game_duration: "Two 25-minute halves"
  halves: "25 min"
  halftime: "3 min"
  referee: true
  heading_allowed: false
  throw_ins: true
  corner_kicks: true
  goal_kicks: true
  free_kicks: true
  offside: false
  leagues: "Sunday 3/4 Grade Coed, Sunday 3/5 Grade Girls"

fifth_sixth_grade:
  label: "5th/6th Grade"
  ages: "10-12"
  format: "9v9"
  goalie: true
  ball_size: "4 or 5"
  field_length: "55-65 yards"
  field_width: "35-45 yards"
  game_duration: "Two 25-minute halves"
  halves: "25 min"
  halftime: "3 min"
  referee: true
  heading_allowed: false
  throw_ins: true
  corner_kicks: true
  goal_kicks: true
  free_kicks: true
  offside: false
  leagues: "Sunday 5/6 Grade COED"
```

### Content Mapping from PDFs

| Page | Source | Approach |
|---|---|---|
| Little Kickers | 4v4 PDF | Only LK-specific rules, simplified language, emphasize practice+game format |
| 1st/2nd Grade (4v4) | 4v4 PDF | Full 4v4 rules without LK callouts, includes formation diagrams |
| 3rd-6th Grade (7v7/9v9) | 7v7/9v9 PDF | Combined page with clear sections for 7v7 vs 9v9, heading ban, throw-in grace period |
| Referee Guide | Both PDFs | Merged and deduplicated into one checklist, noting per-age-group differences |
| Formations | 4v4 PDF page 2 | CSS/HTML field diagrams (responsive, maintainable) instead of ASCII art |
| Game Day Guide | Coach emails (TBD) | Placeholder page — content added when available |

### Stub Pages

Each non-soccer sport gets:
- Sport name as heading
- One-liner description (e.g., "MTL offers recreational baseball for grades K-8")
- Link to the corresponding page on mountaintopleague.com
- Uses the `stub` layout

## Key Rules Differences by Age Group

Captured here for reference during content authoring:

| Rule | Little Kickers | 1st/2nd (4v4) | 3rd/4th (7v7) | 5th/6th (9v9) |
|---|---|---|---|---|
| Goalie | No | No | Yes | Yes |
| Referee | No | Yes | Yes | Yes |
| Throw-ins | No (kick/dribble-in) | No (kick/dribble-in) | Yes (repeatable wk 1-2) | Yes (repeatable wk 1-2) |
| Corner kicks | No | Yes | Yes | Yes |
| Goal kicks | No | Yes | Yes | Yes |
| Free kicks | No | Yes (indirect only) | Yes | Yes |
| Heading | No | No | No (indirect FK penalty) | No (indirect FK penalty) |
| Offside | No | No | Not mentioned | Not mentioned |
| Penalty kicks | No | No | Not mentioned | Not mentioned |
| Score tracked | No | No | Yes (reported to email) | Yes (reported to email) |
| Handshakes | Not mentioned | Not mentioned | Yes (post-game) | Yes (post-game) |

## Repo as Documentation Hub

The `_docs/` directory at the repo root uses Jekyll's underscore convention
(directories starting with `_` are not published) so no `exclude` config is
needed. The content remains browsable on GitHub:

- `_docs/coaching-notes/` — personal coaching tips, drill ideas
- `_docs/archives/` — original PDF files for reference

This lets the repo serve as a living knowledge base beyond the public site.

## Contact & Reporting

All pages include or reference:
- **Email:** MTLsoccer@gmail.com (for issues with fields, parents, coaches, players, referees)
- **Main site:** mountaintopleague.com (for registration, schedules, news)
- **Rules source:** Based on US Soccer small-sided games rules, modified for MTL
