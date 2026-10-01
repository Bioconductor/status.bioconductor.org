# Example: announcing planned maintenance

Scenario: the main site will be unavailable from 09:00 to 11:00 UTC on
15 November 2026, and the page should announce it in advance.

## Write the notice

Create `content/issues/2026-11-15-09-00-00_Main_site.md`:

```markdown
---
title: Scheduled maintenance - main site
date: 2026-11-15 09:00:00
resolved: false
# resolvedWhen:
# Possible severity levels: down, disrupted, notice
severity: notice
affected:
  - Main site
section: issue
---

The main Bioconductor site will be unavailable from 09:00 to 11:00 UTC on
15 November for planned maintenance.
```

Commit and push it:

```bash
git add content/issues/2026-11-15-09-00-00_Main_site.md
git commit -m "Announce main site maintenance on 15 November"
git push
```

The push changes `content/`, so it starts a deploy. The notice is on the page
when the deploy finishes, about half an hour later.

From that deploy on, the page shows `Main site` as "Maintenance" and its header
reads "Please read announcement", whatever the notice's `date`. The notice
itself shows its start time until a deploy after that time changes it to "This
issue is not resolved yet". Check runs that change only `logs/` do not deploy,
so when the work starts, run **Deploy Hugo site to Pages** or push an update
to the notice.

## What each field does

- **`section: issue`** makes the file an incident. Without it the page does not
  list the file, and nothing reports an error.
- **`severity: notice`** shows `Main site` as "Maintenance" while the notice is
  open, and keeps the checks from changing it.
- **`affected:`** must match a `name` under `systems:` in `config.yml` exactly:
  `Main site`, not `Main Site`.
- **`date`** is in UTC. `config.yml` sets `buildFuture: true`, so a notice
  dated in the future is published with the next deploy, not on its date.

## Why `notice` and not `disrupted`

The `Main site` check runs on every scheduled run and takes over open
`disrupted` and `down` incidents whose file names end in `_Main_site.md`. A
`disrupted` announcement would be resolved by the next passing check, before
the maintenance starts.

A notice is left alone. If the site fails during the window, the check opens
its own `disrupted` incident next to the notice, and the page shows the
component as disrupted or down, not "Maintenance", until the site is back.

## Update the notice during the work

Edit the file and push. The incident keeps its URL, so links shared in
advance stay valid. Add updates at the end of the text:

```markdown
**Update 10:30 UTC:** maintenance complete; checking the site before
reopening it.
```

## Close the notice

Nothing closes a notice automatically. When the work is done, edit the front
matter:

```yaml
resolved: true
resolvedWhen: 2026-11-15 10:45:00
```

`resolvedWhen` replaces the commented `# resolvedWhen:` line and is in UTC.
Commit and push:

```bash
git commit -am "Close main site maintenance notice"
git push
```
