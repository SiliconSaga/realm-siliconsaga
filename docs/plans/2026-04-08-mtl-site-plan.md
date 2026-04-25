# MTL Site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a static Jekyll site for Mountain Top League that converts soccer rules PDFs into focused, mobile-first web pages with stubs for other sports.

**Architecture:** Jekyll site with custom layouts (no theme dependency), YAML data files for structured age-group info, SCSS for MTL-branded styling with print support. All content in markdown, editable via GitHub's web editor.

**Tech Stack:** Jekyll (GitHub Pages native), SCSS, HTML5, Liquid templating, no JavaScript beyond nav toggle.

**Spec:** `docs/plans/2026-04-08-mtl-site-design.md`

**Working directory:** `components/mtl-site/` (repo: SiliconSaga/mtl-site)

---

### Task 1: Initialize Git repo and Jekyll config

**Files:**
- Create: `_config.yml`
- Create: `.gitignore`
- Create: `Gemfile`
- Move: `4v4 rules.pdf` → `_docs/archives/4v4-rules.pdf`
- Move: `7v7 and 9v9 rules .pdf` → `_docs/archives/7v7-9v9-rules.pdf`

- [ ] **Step 1: Initialize Git repo and set remote**

```bash
cd components/mtl-site
git init
git remote add siliconsaga https://github.com/SiliconSaga/mtl-site.git
```

- [ ] **Step 2: Create .gitignore**

```gitignore
_site/
.sass-cache/
.jekyll-cache/
.jekyll-metadata
.bundle/
vendor/
```

- [ ] **Step 3: Create Gemfile**

Minimal Gemfile for local development (optional — not needed for GitHub Pages, but useful if someone wants to preview locally):

```ruby
source "https://rubygems.org"
gem "github-pages", group: :jekyll_plugins
```

- [ ] **Step 4: Create _config.yml**

```yaml
title: Mountain Top League
description: >-
  The Mountain Top League is an all-volunteer organization which has served
  the children of West Orange, NJ since it was founded in 1959.
url: "https://siliconsaga.github.io"
baseurl: "/mtl-site"

permalink: pretty
markdown: kramdown

sass:
  sass_dir: _sass
  style: compressed

exclude:
  - Gemfile
  - Gemfile.lock
  - README.md
  - LICENSE
  - vendor

defaults:
  - scope:
      path: ""
    values:
      layout: page
```

- [ ] **Step 5: Archive original PDFs**

```bash
mkdir -p _docs/archives
mv "4v4 rules.pdf" _docs/archives/4v4-rules.pdf
mv "7v7 and 9v9 rules .pdf" _docs/archives/7v7-9v9-rules.pdf
```

- [ ] **Step 6: Commit**

```
feat: initialize Jekyll site with config and archived PDFs
```

Stage: `.gitignore`, `Gemfile`, `_config.yml`, `_docs/archives/4v4-rules.pdf`, `_docs/archives/7v7-9v9-rules.pdf`

Note: also `git rm` the old PDF filenames if git is tracking them.

---

### Task 2: Create data files

**Files:**
- Create: `_data/age_groups.yml`
- Create: `_data/sports.yml`
- Create: `_data/nav.yml`

- [ ] **Step 1: Create _data/age_groups.yml**

```yaml
little_kickers:
  label: "Little Kickers"
  slug: "little-kickers"
  ages: "4-5"
  grades: "Pre-K/K"
  format: "4v4"
  goalie: false
  ball_size: "3 or 4"
  field_length: "25-35 yards"
  field_width: "15-25 yards"
  goal_size: "4ft x 6ft"
  game_duration: "25 min practice + 25 min game"
  halves: null
  halftime: null
  referee: false
  heading_allowed: false
  throw_ins: false
  corner_kicks: false
  goal_kicks: false
  free_kicks: false
  offside: false
  score_tracked: false

first_second_grade:
  label: "1st/2nd Grade"
  slug: "4v4"
  ages: "6-8"
  grades: "1st-2nd"
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
  score_tracked: false

third_fourth_grade:
  label: "3rd/4th Grade"
  slug: "7v7-9v9"
  ages: "8-10"
  grades: "3rd-4th"
  format: "7v7"
  goalie: true
  ball_size: "4 or 5"
  field_length: "55-65 yards"
  field_width: "35-45 yards"
  goal_size: null
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
  score_tracked: true
  leagues: "Sunday 3/4 Grade Coed, Sunday 3/5 Grade Girls"

fifth_sixth_grade:
  label: "5th/6th Grade"
  slug: "7v7-9v9"
  ages: "10-12"
  grades: "5th-6th"
  format: "9v9"
  goalie: true
  ball_size: "4 or 5"
  field_length: "55-65 yards"
  field_width: "35-45 yards"
  goal_size: null
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
  score_tracked: true
  leagues: "Sunday 5/6 Grade COED"
```

- [ ] **Step 2: Create _data/sports.yml**

```yaml
- name: Baseball
  slug: baseball
  stub: true
  description: "MTL offers recreational baseball programs for youth in West Orange."
  mtl_url: "https://mountaintopleague.com/baseball/"

- name: Basketball
  slug: basketball
  stub: true
  description: "MTL offers recreational basketball programs for youth in West Orange."
  mtl_url: "https://mountaintopleague.com/basketball/"

- name: Hockey
  slug: hockey
  stub: true
  description: "MTL offers recreational hockey and street hockey programs for youth in West Orange."
  mtl_url: "https://mountaintopleague.com/hockey/"

- name: Soccer
  slug: soccer
  stub: false
  description: "MTL Soccer serves over 1,000 children across spring, summer, and fall seasons."
  mtl_url: "https://mountaintopleague.com/soccer/"

- name: Softball
  slug: softball
  stub: true
  description: "MTL offers recreational softball programs for youth in West Orange."
  mtl_url: "https://mountaintopleague.com/softball/"
```

- [ ] **Step 3: Create _data/nav.yml**

```yaml
- title: Home
  url: /

- title: About Us
  url: /about/

- title: Sports
  children:
    - title: Baseball
      url: /baseball/
    - title: Basketball
      url: /basketball/
    - title: Hockey
      url: /hockey/
    - title: Soccer
      url: /soccer/
    - title: Softball
      url: /softball/

- title: Contact Us
  url: /contact/
```

- [ ] **Step 4: Commit**

```
feat: add structured data files for age groups, sports, and navigation
```

Stage: `_data/age_groups.yml`, `_data/sports.yml`, `_data/nav.yml`

---

### Task 3: Create layouts and includes

**Files:**
- Create: `_layouts/default.html`
- Create: `_layouts/page.html`
- Create: `_layouts/rules.html`
- Create: `_layouts/stub.html`
- Create: `_includes/nav.html`
- Create: `_includes/footer.html`
- Create: `_includes/print-button.html`
- Create: `_includes/quick-ref.html`

- [ ] **Step 1: Create _layouts/default.html**

This is the base layout wrapping all pages.

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{% if page.title %}{{ page.title }} | {% endif %}{{ site.title }}</title>
  <meta name="description" content="{{ page.description | default: site.description }}">
  <link rel="stylesheet" href="{{ '/assets/css/style.css' | relative_url }}">
</head>
<body>
  <header class="site-header">
    <div class="container">
      <a href="{{ '/' | relative_url }}" class="site-title">
        <strong>Mountain Top League</strong>
      </a>
      <button class="nav-toggle" aria-label="Toggle navigation" onclick="document.querySelector('.site-nav').classList.toggle('open')">
        &#9776;
      </button>
      {% include nav.html %}
    </div>
  </header>

  <main class="container">
    {{ content }}
  </main>

  {% include footer.html %}
</body>
</html>
```

- [ ] **Step 2: Create _layouts/page.html**

```html
---
layout: default
---
<article class="page-content">
  <h1>{{ page.title }}</h1>
  {{ content }}
</article>
```

- [ ] **Step 3: Create _layouts/rules.html**

Rules layout adds a quick-reference card and print button. Front matter on each rules page specifies `age_group` key matching `_data/age_groups.yml`.

```html
---
layout: default
---
{% assign group = site.data.age_groups[page.age_group] %}

<article class="page-content rules-page">
  <div class="rules-header">
    <h1>{{ page.title }}</h1>
    <span class="age-badge">{{ group.label }} &middot; {{ group.format }}</span>
  </div>

  {% include print-button.html %}
  {% include quick-ref.html group=group %}

  {{ content }}

  <div class="rules-footer">
    <p>These rules are based on <a href="https://www.ussoccer.com/">US Soccer</a>
    small-sided games standards, modified for MTL Soccer.
    Questions? Email <a href="mailto:MTLsoccer@gmail.com">MTLsoccer@gmail.com</a>.</p>
  </div>
</article>
```

- [ ] **Step 4: Create _layouts/stub.html**

```html
---
layout: default
---
<article class="page-content stub-page">
  <h1>{{ page.title }}</h1>
  {{ content }}
  <div class="stub-notice">
    <p>For the latest information on {{ page.title }}, visit the
    <a href="{{ page.mtl_url }}">Mountain Top League website</a>.</p>
  </div>
</article>
```

- [ ] **Step 5: Create _includes/nav.html**

```html
<nav class="site-nav">
  <ul class="nav-list">
    {% for item in site.data.nav %}
      {% if item.children %}
        <li class="nav-item has-children">
          <span class="nav-link">{{ item.title }} &#9662;</span>
          <ul class="nav-children">
            {% for child in item.children %}
              <li><a href="{{ child.url | relative_url }}" class="nav-link">{{ child.title }}</a></li>
            {% endfor %}
          </ul>
        </li>
      {% else %}
        <li class="nav-item">
          <a href="{{ item.url | relative_url }}" class="nav-link">{{ item.title }}</a>
        </li>
      {% endif %}
    {% endfor %}
  </ul>
</nav>
```

- [ ] **Step 6: Create _includes/footer.html**

```html
<footer class="site-footer">
  <div class="container">
    <p>&copy; {{ 'now' | date: '%Y' }} Mountain Top League &middot; West Orange, NJ</p>
    <p>
      <a href="https://mountaintopleague.com">mountaintopleague.com</a> &middot;
      <a href="mailto:MTLsoccer@gmail.com">MTLsoccer@gmail.com</a>
    </p>
  </div>
</footer>
```

- [ ] **Step 7: Create _includes/print-button.html**

```html
<div class="print-only-hide">
  <button class="print-btn" onclick="window.print()">Print this page</button>
</div>
```

- [ ] **Step 8: Create _includes/quick-ref.html**

This renders the quick-reference card at the top of each rules page. Accepts a `group` parameter.

```html
{% assign g = include.group %}
<div class="quick-ref">
  <h3>Quick Reference</h3>
  <table class="quick-ref-table">
    <tr><th>Format</th><td>{{ g.format }}{% if g.goalie %} (includes goalie){% else %} (no goalie){% endif %}</td></tr>
    <tr><th>Ball Size</th><td>{{ g.ball_size }}</td></tr>
    <tr><th>Field</th><td>{{ g.field_length }} &times; {{ g.field_width }}</td></tr>
    {% if g.goal_size %}<tr><th>Goals</th><td>{{ g.goal_size }}</td></tr>{% endif %}
    <tr><th>Game</th><td>{{ g.game_duration }}</td></tr>
    {% if g.halftime %}<tr><th>Halftime</th><td>{{ g.halftime }}</td></tr>{% endif %}
    <tr><th>Referee</th><td>{% if g.referee %}Yes{% else %}No{% endif %}</td></tr>
    <tr><th>Shin Guards</th><td>Required</td></tr>
  </table>
</div>
```

- [ ] **Step 9: Commit**

```
feat: add layouts (default, page, rules, stub) and includes (nav, footer, quick-ref)
```

Stage: `_layouts/default.html`, `_layouts/page.html`, `_layouts/rules.html`, `_layouts/stub.html`, `_includes/nav.html`, `_includes/footer.html`, `_includes/print-button.html`, `_includes/quick-ref.html`

---

### Task 4: Create stylesheets

**Files:**
- Create: `_sass/_base.scss`
- Create: `_sass/_nav.scss`
- Create: `_sass/_print.scss`
- Create: `assets/css/style.scss`

- [ ] **Step 1: Create _sass/_base.scss**

MTL blue palette — navy header, clean content area. These colors approximate the MTL branding; adjust hex values if the board provides official brand colors.

```scss
// MTL Color Palette
$mtl-navy: #1b3a5c;
$mtl-blue: #2a5a8c;
$mtl-light: #e8eef4;
$mtl-white: #ffffff;
$mtl-text: #2d2d2d;
$mtl-gray: #6b7280;
$mtl-border: #d1d5db;

// Typography — system font stack
$font-stack: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
  "Helvetica Neue", Arial, sans-serif;

* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

html {
  font-size: 16px;
}

body {
  font-family: $font-stack;
  color: $mtl-text;
  line-height: 1.6;
  background: $mtl-white;
}

.container {
  max-width: 800px;
  margin: 0 auto;
  padding: 0 1rem;
}

h1, h2, h3, h4 {
  line-height: 1.3;
  margin-top: 1.5rem;
  margin-bottom: 0.5rem;
}

h1 { font-size: 1.75rem; }
h2 { font-size: 1.4rem; }
h3 { font-size: 1.15rem; }

a {
  color: $mtl-blue;
  text-decoration: none;
  &:hover { text-decoration: underline; }
}

ul, ol {
  padding-left: 1.5rem;
  margin-bottom: 1rem;
}

li {
  margin-bottom: 0.25rem;
}

p {
  margin-bottom: 1rem;
}

// Site header
.site-header {
  background: $mtl-navy;
  color: $mtl-white;
  padding: 0.75rem 0;

  .container {
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
  }
}

.site-title {
  color: $mtl-white;
  font-size: 1.25rem;
  text-decoration: none;
  &:hover { text-decoration: none; opacity: 0.9; }
}

// Main content
main.container {
  padding-top: 1.5rem;
  padding-bottom: 2rem;
}

// Page content
.page-content {
  h2 {
    border-bottom: 2px solid $mtl-light;
    padding-bottom: 0.25rem;
  }
}

// Quick reference card
.quick-ref {
  background: $mtl-light;
  border-left: 4px solid $mtl-navy;
  border-radius: 4px;
  padding: 1rem;
  margin-bottom: 1.5rem;

  h3 {
    margin-top: 0;
    margin-bottom: 0.5rem;
    color: $mtl-navy;
  }
}

.quick-ref-table {
  width: 100%;
  border-collapse: collapse;

  th {
    text-align: left;
    padding: 0.25rem 1rem 0.25rem 0;
    color: $mtl-gray;
    font-weight: 600;
    white-space: nowrap;
    width: 1%;
  }

  td {
    padding: 0.25rem 0;
  }
}

// Age badge
.rules-header {
  margin-bottom: 1rem;
}

.age-badge {
  display: inline-block;
  background: $mtl-navy;
  color: $mtl-white;
  padding: 0.2rem 0.75rem;
  border-radius: 12px;
  font-size: 0.85rem;
  font-weight: 600;
}

// Print button
.print-btn {
  background: $mtl-blue;
  color: $mtl-white;
  border: none;
  padding: 0.5rem 1rem;
  border-radius: 4px;
  cursor: pointer;
  font-size: 0.9rem;
  margin-bottom: 1rem;
  &:hover { background: $mtl-navy; }
}

// Rules footer
.rules-footer {
  margin-top: 2rem;
  padding-top: 1rem;
  border-top: 1px solid $mtl-border;
  font-size: 0.9rem;
  color: $mtl-gray;
}

// Stub page notice
.stub-notice {
  background: $mtl-light;
  border-radius: 4px;
  padding: 1rem;
  margin-top: 1.5rem;
}

// Picker cards (soccer overview)
.picker-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 1rem;
  margin: 1.5rem 0;
}

@media (min-width: 480px) {
  .picker-grid {
    grid-template-columns: 1fr 1fr;
  }
}

.picker-card {
  display: block;
  background: $mtl-light;
  border: 2px solid $mtl-border;
  border-radius: 8px;
  padding: 1.25rem;
  text-align: center;
  text-decoration: none;
  color: $mtl-text;
  font-weight: 600;
  font-size: 1.05rem;
  transition: border-color 0.15s;

  &:hover {
    border-color: $mtl-navy;
    text-decoration: none;
  }

  small {
    display: block;
    font-weight: 400;
    color: $mtl-gray;
    margin-top: 0.25rem;
    font-size: 0.85rem;
  }
}

// Sport cards (home page)
.sport-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 1rem;
  margin: 1.5rem 0;
}

.sport-card {
  display: block;
  background: $mtl-navy;
  color: $mtl-white;
  border-radius: 8px;
  padding: 1.25rem;
  text-align: center;
  text-decoration: none;
  font-weight: 600;
  font-size: 1.05rem;
  transition: background 0.15s;

  &:hover {
    background: $mtl-blue;
    text-decoration: none;
  }
}

// Footer
.site-footer {
  background: $mtl-navy;
  color: rgba($mtl-white, 0.8);
  padding: 1.5rem 0;
  margin-top: 2rem;
  font-size: 0.85rem;
  text-align: center;

  a {
    color: $mtl-white;
    &:hover { opacity: 0.8; }
  }

  p { margin-bottom: 0.25rem; }
}

// Field diagrams
.field-diagram {
  background: #4a8c3f;
  border: 2px solid #3a6f32;
  border-radius: 4px;
  padding: 1rem;
  margin: 1rem 0;
  position: relative;
  max-width: 300px;
  aspect-ratio: 3/4;
  display: grid;
  place-items: center;
  color: $mtl-white;
  font-weight: 600;
  font-size: 0.85rem;
}

.field-diagram .goal-top,
.field-diagram .goal-bottom {
  position: absolute;
  left: 50%;
  transform: translateX(-50%);
  background: rgba($mtl-white, 0.3);
  padding: 0.15rem 1rem;
  border-radius: 2px;
  font-size: 0.75rem;
}

.field-diagram .goal-top { top: 0; }
.field-diagram .goal-bottom { bottom: 0; }

.field-diagram .positions {
  display: grid;
  gap: 0.75rem;
  text-align: center;
  width: 100%;
  padding: 1.5rem 0.5rem;
}

.field-diagram .pos {
  background: rgba($mtl-white, 0.25);
  border-radius: 50%;
  width: 2rem;
  height: 2rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 0.7rem;
  margin: 0 auto;
}

.field-row {
  display: flex;
  justify-content: space-around;
  width: 100%;
}
```

- [ ] **Step 2: Create _sass/_nav.scss**

```scss
// Navigation
.nav-toggle {
  display: none;
  background: none;
  border: none;
  color: $mtl-white;
  font-size: 1.5rem;
  cursor: pointer;
  padding: 0.25rem;
}

.site-nav {
  .nav-list {
    display: flex;
    list-style: none;
    padding: 0;
    margin: 0;
    gap: 0.25rem;
  }

  .nav-item {
    position: relative;
  }

  .nav-link {
    color: rgba($mtl-white, 0.9);
    text-decoration: none;
    padding: 0.5rem 0.75rem;
    display: block;
    font-size: 0.9rem;
    cursor: pointer;

    &:hover {
      color: $mtl-white;
      text-decoration: none;
      background: rgba($mtl-white, 0.1);
      border-radius: 4px;
    }
  }

  // Dropdown
  .has-children {
    &:hover .nav-children,
    &:focus-within .nav-children {
      display: block;
    }
  }

  .nav-children {
    display: none;
    position: absolute;
    top: 100%;
    left: 0;
    background: $mtl-navy;
    border: 1px solid rgba($mtl-white, 0.15);
    border-radius: 4px;
    list-style: none;
    padding: 0.25rem 0;
    margin: 0;
    min-width: 160px;
    z-index: 100;

    .nav-link {
      padding: 0.4rem 1rem;
    }
  }
}

// Mobile nav
@media (max-width: 640px) {
  .nav-toggle {
    display: block;
  }

  .site-nav {
    display: none;
    width: 100%;
    order: 3;

    &.open {
      display: block;
    }

    .nav-list {
      flex-direction: column;
      padding-top: 0.5rem;
    }

    .nav-children {
      position: static;
      border: none;
      padding-left: 1rem;

      // Always show children in mobile view
      display: block;
    }

    .has-children:hover .nav-children {
      display: block;
    }
  }
}
```

- [ ] **Step 3: Create _sass/_print.scss**

```scss
@media print {
  .site-header,
  .site-footer,
  .print-only-hide,
  .nav-toggle {
    display: none !important;
  }

  body {
    font-size: 12pt;
    color: #000;
    background: #fff;
  }

  .container {
    max-width: 100%;
    padding: 0;
  }

  a {
    color: #000;
    text-decoration: underline;
  }

  .quick-ref {
    background: none;
    border: 1px solid #ccc;
  }

  .age-badge {
    background: none;
    color: #000;
    border: 1px solid #000;
  }

  .picker-card,
  .sport-card {
    border: 1px solid #ccc;
    background: none;
    color: #000;
  }

  .field-diagram {
    border: 2px solid #333;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }
}
```

- [ ] **Step 4: Create assets/css/style.scss**

The front matter dashes tell Jekyll to process this file.

```scss
---
---

@import "base";
@import "nav";
@import "print";
```

- [ ] **Step 5: Commit**

```
feat: add SCSS stylesheets — MTL blue branding, responsive nav, print support
```

Stage: `_sass/_base.scss`, `_sass/_nav.scss`, `_sass/_print.scss`, `assets/css/style.scss`

---

### Task 5: Create home page, about, and contact pages

**Files:**
- Create: `index.md`
- Create: `about.md`
- Create: `contact.md`

- [ ] **Step 1: Create index.md**

```markdown
---
layout: page
title: Mountain Top League
---

The Mountain Top League is an all-volunteer organization which has served the
children of West Orange, NJ since it was founded in 1959. We offer recreational
sports programs focused on sportsmanship, skill development, and fun.

## Our Sports

<div class="sport-grid">
{% for sport in site.data.sports %}
  <a href="{{ site.baseurl }}/{{ sport.slug }}/" class="sport-card">
    {{ sport.name }}
  </a>
{% endfor %}
</div>

## Soccer Season

MTL Soccer serves over 1,000 children across spring, summer, and fall seasons.
Our program emphasizes sportsmanship and fostering a love for the game through
volunteer coaches and commissioners.

[View Soccer Programs &rarr;]({{ site.baseurl }}/soccer/)

## Get Involved

MTL is run entirely by volunteers. If you're interested in coaching, refereeing,
or helping out, reach out at [MTLsoccer@gmail.com](mailto:MTLsoccer@gmail.com)
or visit our [Contact page]({{ site.baseurl }}/contact/).
```

- [ ] **Step 2: Create about.md**

```markdown
---
layout: page
title: About Us
permalink: /about/
---

The Mountain Top League (MTL) is an all-volunteer organization which has served
the children of West Orange, NJ since it was founded in 1959.

## Our Mission

MTL provides recreational sports programs that focus on:

- **Sportsmanship** — learning to play fair, win graciously, and lose with dignity
- **Skill development** — age-appropriate coaching to build fundamentals
- **Fun** — every child should enjoy their time on the field

## Sports We Offer

- **Baseball** — spring and summer programs
- **Basketball** — winter programs
- **Hockey** — including street hockey
- **Soccer** — spring, summer, and fall seasons serving 1,000+ children
- **Softball** — spring and summer programs

## Volunteer Organization

MTL is run entirely by volunteer coaches, referees, commissioners, and trustees.
We welcome new volunteers — no prior coaching experience required.

For more information, visit [mountaintopleague.com](https://mountaintopleague.com/)
or email [MTLsoccer@gmail.com](mailto:MTLsoccer@gmail.com).
```

- [ ] **Step 3: Create contact.md**

```markdown
---
layout: page
title: Contact Us
permalink: /contact/
---

## Soccer Program

For questions about soccer — registration, rules, coaching, fields, or
game-day logistics:

**Email:** [MTLsoccer@gmail.com](mailto:MTLsoccer@gmail.com)

## Reporting Issues

Issues with fields, parents, coaches, players, and/or referees must be reported
to the trustees through the [MTLsoccer@gmail.com](mailto:MTLsoccer@gmail.com)
mailbox.

## Main Website

For the latest on registration, schedules, and all MTL sports:

[mountaintopleague.com](https://mountaintopleague.com/)

## Social Media

Follow MTL on [Facebook](https://www.facebook.com/) and
[Instagram](https://www.instagram.com/) for announcements and updates.
```

- [ ] **Step 4: Commit**

```
feat: add home, about, and contact pages
```

Stage: `index.md`, `about.md`, `contact.md`

---

### Task 6: Create soccer overview and rules pages

**Files:**
- Create: `soccer/index.md`
- Create: `soccer/little-kickers.md`
- Create: `soccer/4v4.md`
- Create: `soccer/7v7-9v9.md`

- [ ] **Step 1: Create soccer/index.md — the age-group picker**

```markdown
---
layout: page
title: Soccer
permalink: /soccer/
---

MTL Soccer serves over 1,000 children in West Orange across spring, summer, and
fall seasons. Our recreational program emphasizes sportsmanship and fostering a
love for the game through volunteer coaches and commissioners.

## Find Your Program

<div class="picker-grid">
  <a href="{{ site.baseurl }}/soccer/little-kickers/" class="picker-card">
    Little Kickers
    <small>Ages 4-5 &middot; 4v4</small>
  </a>
  <a href="{{ site.baseurl }}/soccer/4v4/" class="picker-card">
    1st/2nd Grade
    <small>Ages 6-8 &middot; 4v4</small>
  </a>
  <a href="{{ site.baseurl }}/soccer/7v7-9v9/" class="picker-card">
    3rd-6th Grade
    <small>Ages 8-12 &middot; 7v7 / 9v9</small>
  </a>
  <a href="{{ site.baseurl }}/soccer/referee-guide/" class="picker-card">
    Referee Guide
    <small>All age groups</small>
  </a>
  <a href="{{ site.baseurl }}/soccer/game-day/" class="picker-card">
    Game Day Guide
    <small>For parents &amp; coaches</small>
  </a>
  <a href="{{ site.baseurl }}/soccer/formations/" class="picker-card">
    Formations
    <small>4v4 position diagrams</small>
  </a>
</div>

## Registration

For registration information and pricing, visit the
[Mountain Top League website](https://mountaintopleague.com/soccer/).

## Contact

Questions about the soccer program? Email
[MTLsoccer@gmail.com](mailto:MTLsoccer@gmail.com).
```

- [ ] **Step 2: Create soccer/little-kickers.md**

```markdown
---
layout: rules
title: "Little Kickers Rules"
permalink: /soccer/little-kickers/
age_group: little_kickers
---

## Overview

Little Kickers is MTL's introductory soccer program for ages 4-5. Each session
is **25 minutes of practice followed by a 25-minute game**. The focus is on
having fun and getting comfortable with the ball.

## Players

- **4 players per side** — no goalie
- Shin guards are **required**
- Cleats are encouraged but not required
- To limit kids sitting out, coaches may agree to play with a 5th player each

## Ball In and Out of Play

The Little Kickers format is simplified to keep the game moving:

- **Kick-offs** are used to start play
- **No corner kicks, goal kicks, free kicks, or throw-ins**
- If the ball goes out of bounds, restart with a **kick-in or dribble-in**

## Scoring

- After a goal, the opposing team restarts at midfield
- Opponents should be at least **10 feet away** from the ball on restarts

## Important Rules

- **No goalies** — players who stand in front of their own goal should be
  encouraged to move around the field
- **No offside** — but players who camp in front of the opposing goal should be
  gently encouraged to move
- **No score is kept** — the emphasis is on fun and learning

## Coaches & Parents

Together, coaches and parents are expected to create and promote a **fun and
safe environment** for the players. This is an introduction to the sport —
keep it positive and encouraging.
```

- [ ] **Step 3: Create soccer/4v4.md**

```markdown
---
layout: rules
title: "1st/2nd Grade Rules (4v4)"
permalink: /soccer/4v4/
age_group: first_second_grade
---

## Overview

The 1st/2nd Grade program plays 4v4 with an appointed referee. Games consist
of **two 20-minute halves** with a 3-minute halftime.

## Players

- **4 players per side** — no goalie
- Shin guards are **required**
- Cleats are encouraged but not required
- To limit kids sitting out, coaches may agree to play with a 5th player each
- Substitutions are **unlimited** and can occur at any time

## Ball In and Out of Play

- **Kick-offs, free kicks, goal kicks, and corner kicks** are used to start or
  restart play
- **Kick-ins and/or dribble-ins** are also acceptable — **no throw-ins**
- Goal kicks and corner kicks should be taken in the **general vicinity** of the
  respective goal or corner
- All free kicks are **indirect** — the ball must be passed to another player
  before a shot on goal

## Restarts After a Goal

- Opposing team starts with the ball at **midfield**
- Opponents must be at least **10 feet away** from the ball on the restart

## Goal Kicks

- Opposing team should line up on **their side of the field** (behind the
  midfield line) on all goal kicks
- Coaches and referees need to enforce this on every occasion

## Important Rules

- **No goalies** — players who stand in front of their own goal should be
  encouraged to move. Coaches and referees should actively enforce this.
- **No offside** — but players who stand in front of the opposing goal should be
  encouraged to move. Coaches and referees should actively enforce this.
- **No penalty kicks**
- **No heading** — the ball should not be played with the head

## Positions

At this age group, players should start to understand the general principles of
positions. See the [Formations page]({{ site.baseurl }}/soccer/formations/) for
recommended 4v4 lineups.

Players should not be rigidly restricted to positions, but we want them to start
learning the difference between offensive and defensive roles.

## Coaches & Parents

Together, coaches and parents are expected to create and promote a **fun and
safe environment** for the players.

Issues with fields, parents, coaches, players, and/or referees must be reported
to the trustees at [MTLsoccer@gmail.com](mailto:MTLsoccer@gmail.com).
```

- [ ] **Step 4: Create soccer/7v7-9v9.md**

```markdown
---
layout: rules
title: "3rd-6th Grade Rules (7v7 / 9v9)"
permalink: /soccer/7v7-9v9/
age_group: third_fourth_grade
---

## Overview

Older age groups play on larger fields with goalies. The format depends on the
age group:

| Age Group | Format | Leagues |
|---|---|---|
| **3rd/4th Grade** | 7v7 (6 + goalie) | Sunday Coed, Sunday 3/5 Girls |
| **5th/6th Grade** | 9v9 (8 + goalie) | Sunday Coed |

Games are **two 25-minute halves** with a 3-minute halftime.

A larger or smaller number of players can be used if agreed upon by both coaches
and the referee. The referee has the deciding vote.

## Players

- Shin guards are **required**
- Cleats are encouraged but not required
- Substitutions are **unlimited** and can occur at any stoppage

## Ball In and Out of Play

- **Kick-offs, free kicks, goal kicks, and corner kicks** are used to start or
  restart play
- **Throw-ins** are used when the ball goes out over the sideline
  - In the **first two weeks** of the season, incorrect throw-ins are
    **repeatable** — coaches and referees should provide guidance
- Goal kicks and corner kicks should be taken in the general vicinity of the
  respective goal or corner if field lines are not apparent

## Restarts

- Opponents must be at least **10 feet away** from the ball on all restarts
  (except goal kicks)
- On **goal kicks**, the opposing team must return to **their side of the field**
  (behind the midfield line) — coaches and referees need to enforce this on
  every occasion

## Heading

**Players may not head the ball.** Heading results in an **indirect free kick**
for the opposing team. Coaches and referees need to enforce this on every
occasion.

## Important Rules

- **No penalty kicks** are mentioned in the standards
- **No offside** is mentioned in the standards

## After the Game

- Teams and coaches **must shake hands** with the other players, coaches, and
  referees after the game
- The referee tracks the score and confirms the final result with each coach
- Final scores are reported to
  [MTLsoccer@gmail.com](mailto:MTLsoccer@gmail.com) by Sunday evening

## Field Safety

- Fields are lined by the town; dimensions may vary slightly from the
  recommended 55-65 × 35-45 yards
- Corner flags are not required
- **Goals must be anchored** by sand bags (provided by the town)
- Referees and coaches are responsible for ensuring a safe playing field before
  kick-off

## Coaches & Parents

Together, coaches and parents are expected to create and promote a **fun and
safe environment** for the players.

Inappropriate conduct on or off the field will be addressed by MTL Trustees and
board members. Issues must be reported to
[MTLsoccer@gmail.com](mailto:MTLsoccer@gmail.com).
```

- [ ] **Step 5: Commit**

```
feat: add soccer overview picker and rules pages (Little Kickers, 4v4, 7v7/9v9)
```

Stage: `soccer/index.md`, `soccer/little-kickers.md`, `soccer/4v4.md`, `soccer/7v7-9v9.md`

---

### Task 7: Create referee guide, formations, and game day placeholder

**Files:**
- Create: `soccer/referee-guide.md`
- Create: `soccer/formations.md`
- Create: `soccer/game-day.md`

- [ ] **Step 1: Create soccer/referee-guide.md**

```markdown
---
layout: page
title: "Referee Guide"
permalink: /soccer/referee-guide/
---

This guide covers referee responsibilities across all MTL Soccer age groups.

## Before the Game

- **Arrive early** — minimum 10 minutes before the start of the game
- **Check the field** — ensure it is playable and clear of garbage, sticks,
  rocks, or other hazards
- **Check the goals** — ensure goal nets are fastened and goals are anchored
  (7v7/9v9 fields use sand bags provided by the town)
- **Introduce yourself** to both coaches
- **Check each player** for shin guards and appropriate footwear (cleats are
  not required)

## During the Game

- **Follow the play** — stay close to the action
- **Project your voice** — explain to the players what they need to do and why
  - Many players may not know the difference between a goal kick and a
    corner kick — be patient and teach as you go
- **Keep track of time**

### Rules to Enforce

| Rule | Little Kickers | 1st/2nd Grade | 3rd-6th Grade |
|---|---|---|---|
| **No goalies** | Enforce — encourage players to move | Enforce — encourage players to move | N/A — goalies are used |
| **Goal kick positioning** | N/A — no goal kicks | Opposing team behind midfield | Opposing team behind midfield |
| **No heading** | Enforce | Enforce | Enforce — indirect FK to opponents |
| **Throw-ins** | N/A — use kick/dribble-ins | N/A — use kick/dribble-ins | Allow re-dos in first 2 weeks |
| **Positions** | Gently encourage movement | Ensure kids line up in positions | Standard play |

### Score Tracking (7v7 / 9v9 only)

- Keep track of the score during the game
- Confirm the final result with each coach after the game
- Report the final score to
  [MTLsoccer@gmail.com](mailto:MTLsoccer@gmail.com) by Sunday evening

## After the Game

- Report any injuries, player issues, or coach issues to
  [MTLsoccer@gmail.com](mailto:MTLsoccer@gmail.com)

## Key Principles

- **Be patient** — these are kids learning the game
- **Be educational** — explain calls, don't just make them
- **Be consistent** — enforce the same rules every game
- Create a **fun and safe environment** for all players
```

- [ ] **Step 2: Create soccer/formations.md**

```markdown
---
layout: page
title: "Formations & Positions"
permalink: /soccer/formations/
---

Below are two recommended formations for **4v4 games** (1st/2nd Grade). Players
should not be rigidly restricted to these positions — the goal is to start
learning the difference between offensive and defensive roles.

## Formation 1: Diamond (1-2-1)

<div class="field-diagram">
  <div class="goal-top">Goal</div>
  <div class="positions">
    <div class="field-row"><span class="pos">D</span></div>
    <div class="field-row"><span class="pos">W</span><span class="pos">W</span></div>
    <div class="field-row"><span class="pos">O</span></div>
  </div>
  <div class="goal-bottom">Goal</div>
</div>

- **D** — Defensive player (near your own goal)
- **W** — Wing/midfielder (covers both sides of the field)
- **O** — Offensive player (near the opposing goal)

Best for: Teams that have one strong defender and one strong attacker, with
two players who like to run.

## Formation 2: Box (2-2)

<div class="field-diagram">
  <div class="goal-top">Goal</div>
  <div class="positions">
    <div class="field-row"><span class="pos">D</span><span class="pos">D</span></div>
    <div class="field-row"><span class="pos">O</span><span class="pos">O</span></div>
  </div>
  <div class="goal-bottom">Goal</div>
</div>

- **D** — Defensive players (stay closer to your own goal)
- **O** — Offensive players (push toward the opposing goal)

Best for: Balanced teams where players pair up naturally. Simpler for younger
players to understand.

## Position Key

| Position | Role | Responsibility |
|---|---|---|
| **D** (Defense) | Protect your goal | Stay between the ball and your goal |
| **W** (Wing) | Cover the sides | Help on both offense and defense |
| **O** (Offense) | Score goals | Stay near the opposing goal |

## Tips for Coaches

- **Rotate positions** — every player should try different roles
- **Don't over-coach positioning** — at this age, chasing the ball in a swarm
  is normal and expected
- **Praise effort** over results — "great job getting back on defense!" matters
  more than the score
```

- [ ] **Step 3: Create soccer/game-day.md**

```markdown
---
layout: page
title: "Game Day Guide"
permalink: /soccer/game-day/
---

A practical guide for parents and coaches on what to expect and what to bring
on game day.

## What to Bring

- **Shin guards** — required for all players
- **Cleats** — recommended but not required; sneakers are fine
- **Water bottle** — staying hydrated is important
- **Weather-appropriate clothing** — dress in layers for cooler days
- **Soccer ball** — the right size for your age group (see below)

## Ball Sizes by Age Group

| Age Group | Ball Size |
|---|---|
| Little Kickers (ages 4-5) | Size 3 or 4 |
| 1st/2nd Grade (ages 6-8) | Size 3 or 4 |
| 3rd-6th Grade (ages 8-12) | Size 4 or 5 |

## More Details Coming Soon

Additional game-day information — including uniform distribution, field
locations, and season schedules — will be added here as it becomes available.

For questions, email [MTLsoccer@gmail.com](mailto:MTLsoccer@gmail.com).
```

- [ ] **Step 4: Commit**

```
feat: add referee guide, formations page, and game day placeholder
```

Stage: `soccer/referee-guide.md`, `soccer/formations.md`, `soccer/game-day.md`

---

### Task 8: Create sport stub pages

**Files:**
- Create: `baseball/index.md`
- Create: `basketball/index.md`
- Create: `hockey/index.md`
- Create: `softball/index.md`

- [ ] **Step 1: Create baseball/index.md**

```markdown
---
layout: stub
title: Baseball
permalink: /baseball/
mtl_url: "https://mountaintopleague.com/baseball/"
---

MTL offers recreational baseball programs for youth in West Orange, NJ.
```

- [ ] **Step 2: Create basketball/index.md**

```markdown
---
layout: stub
title: Basketball
permalink: /basketball/
mtl_url: "https://mountaintopleague.com/basketball/"
---

MTL offers recreational basketball programs for youth in West Orange, NJ.
```

- [ ] **Step 3: Create hockey/index.md**

```markdown
---
layout: stub
title: Hockey
permalink: /hockey/
mtl_url: "https://mountaintopleague.com/hockey/"
---

MTL offers recreational hockey and street hockey programs for youth in
West Orange, NJ.
```

- [ ] **Step 4: Create softball/index.md**

```markdown
---
layout: stub
title: Softball
permalink: /softball/
mtl_url: "https://mountaintopleague.com/softball/"
---

MTL offers recreational softball programs for youth in West Orange, NJ.
```

- [ ] **Step 5: Commit**

```
feat: add sport stub pages for baseball, basketball, hockey, softball
```

Stage: `baseball/index.md`, `basketball/index.md`, `hockey/index.md`, `softball/index.md`

---

### Task 9: Enable GitHub Pages and verify deployment

- [ ] **Step 1: Create a README.md**

```markdown
# MTL Site

Static website for the Mountain Top League — a volunteer youth sports
organization in West Orange, NJ.

Built with Jekyll and hosted on GitHub Pages.

## Editing

All content is in Markdown files. Edit directly on GitHub or clone locally.

- **Soccer rules** are in `soccer/`
- **Sport stubs** are in `baseball/`, `basketball/`, `hockey/`, `softball/`
- **Structured data** (age groups, sports list) is in `_data/`
- **Non-published docs** (coaching notes, archives) are in `_docs/`

## Local Preview (optional)

```bash
bundle install
bundle exec jekyll serve
```

Then visit http://localhost:4000/mtl-site/
```

- [ ] **Step 2: Push to remote**

```bash
git push -u siliconsaga main
```

- [ ] **Step 3: Enable GitHub Pages**

```bash
gh api repos/SiliconSaga/mtl-site/pages -X POST -f source.branch=main -f source.path=/
```

Or manually: repo Settings → Pages → Source: Deploy from branch → main → / (root).

- [ ] **Step 4: Verify the site loads**

Visit `https://siliconsaga.github.io/mtl-site/` and verify:
- Home page renders with sport cards
- Navigation works (including mobile hamburger)
- Soccer picker page shows tappable cards
- At least one rules page renders with quick-reference card
- Print button triggers browser print dialog
- Stub pages show the "visit main site" notice

- [ ] **Step 5: Commit README**

```
docs: add README with editing and local preview instructions
```

Stage: `README.md`
