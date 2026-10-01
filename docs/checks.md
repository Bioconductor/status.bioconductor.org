# Adding, changing and removing checks

A monitored service is a component in `config.yml` plus a check in
`.github/workflows/checks.yaml`. The two are joined only by the system name,
compared as an exact string, and a mismatch produces no error.

## The three places a system name appears

| # | File | What it holds |
|---|---|---|
| 1 | `.github/workflows/checks.yaml` | The last argument to `web_check_and_report.sh` |
| 2 | `config.yml` | A `name:` under `systems:` |
| 3 | `content/issues/*.md` | The `affected:` list, written from #1 when the check opens an incident |

cState shows an incident on a component when #3 contains #2. If #1 and #2
differ, the check's incidents appear in the incident history but the component
stays operational.

## Choosing a system name

The name is the component's label, its URL slug (`Bioconductor Code Browser`
→ `/affected/bioconductor-code-browser/`) and, with spaces replaced by
underscores, part of its file names:

- `content/issues/<timestamp>_Bioconductor_Code_Browser.md`
- `logs/Bioconductor_Code_Browser.csv`

Use letters, digits, spaces and hyphens. Characters such as `*`, `/`, `:` or
`?` are not valid in file names on every platform, and the script passes the
log path to `git add` unquoted, so shell wildcards in a name are expanded.

No name may be the last words of another system's name. The script finds a
system's incidents with the pattern `content/issues/*_<System>.md`, so a check
named `Code Browser` would escalate and resolve the open incidents of
`Bioconductor Code Browser`, and a check named `site` those of `Main site`.
`verify_system_names.sh` does not detect this.

## Adding a check

### 1. Add the component to `config.yml`

```yaml
  systems:
    # ...
    - name: Package Build System
      description: Nightly package builds
      category: Websites
      link: https://bioconductor.org/checkResults/
```

`category` must be one of the `name` values under `categories:`; a component
with any other category is not shown. Components appear in the order they are
listed.

### 2. Add the check to `checks.yaml`

Inside the `command:` block, with the other checks:

```bash
bash .github/scripts/web_check_and_report.sh \
  'webcheck' \
  'https://bioconductor.org/checkResults/' \
  '(Auto-detected) Bioconductor Package Build System Down' \
  'disrupted' \
  'Package Build System'
```

| Position | Meaning | Notes |
|---|---|---|
| 1 | check type | `webcheck` or `statscheck` |
| 2 | URL | Probed with `curl -s --head -L --request GET` |
| 3 | incident title | Shown on the status page; existing checks start it with `(Auto-detected)` |
| 4 | initial severity | `disrupted` for every existing check; the second failing run sets `down` |
| 5 | system name | Must equal the `config.yml` name exactly |

Choosing the URL:

- Use the `https://` URL the service is served from. `webcheck` follows
  redirects and passes on any 200, so a plain-HTTP URL that redirects to
  another site reports that site's health.
- Probe a resource that shows the service is working, such as an index file
  of a current release, rather than a page a proxy can answer on its own.
- A URL that contains a Bioconductor version has to be reviewed at each
  release; see [updating.md](updating.md#bioconductor-releases).

### 3. Check the names

```bash
bash .github/scripts/verify_system_names.sh
```

The script lists the names used by checks and the components declared in
`config.yml`, and exits non-zero when a check uses a name that is not declared.
A component without a check, such as `GitHub`, is listed as a note. The
[Verify configuration](../.github/workflows/verify.yaml) workflow runs it on
every pull request that changes `config.yml`, `checks.yaml` or
`.github/scripts/`.

### 4. Probe the URL as the check does

```bash
curl -s --head -L --request GET 'https://bioconductor.org/checkResults/' | grep '^HTTP'
```

The check passes if one of the lines shows `200`. Fix a URL that fails before
merging; otherwise the first run opens an incident.

### 5. Build the site

```bash
hugo serve
```

The new component appears in its category as operational.

### 6. Merge

Open a pull request so the verify workflow runs, then merge. The next
scheduled run starts the check; *Run workflow* on **Scheduled checks** in the
Actions tab starts one immediately. The first run creates
`logs/Package_Build_System.csv`.

## Removing a check

1. Delete its `web_check_and_report.sh` line from `checks.yaml`.
2. Either keep the component in `config.yml`, where it shows as operational
   and links to its past incidents, or remove it. A removed component
   disappears from the component list; its incidents stay in the incident
   history.
3. Keep `logs/<System>.csv`; it is the check history.

## Renaming a system

The name is part of existing incident files, their file names and the log
file name. There are two ways to rename.

**Change `config.yml` to the name the check uses.** One line; existing
incidents attach to the component and no URL changes. The displayed name
becomes the check's name.

**Change the check and move the history to the new name.** Every past
incident gets a new URL.

```bash
OLD='Old name'; OLD_S=${OLD// /_}
NEW='New name'; NEW_S=${NEW// /_}

# 1. checks.yaml: change the fifth argument from "$OLD" to "$NEW"
# 2. Rewrite the affected: value in existing incidents (GNU sed)
sed -i "s/^  - ${OLD}\$/  - ${NEW}/" content/issues/*_${OLD_S}.md
# 3. Rename the incident files; this changes their public URLs
for f in content/issues/*_${OLD_S}.md; do
  git mv "$f" "${f%_${OLD_S}.md}_${NEW_S}.md"
done
# 4. Rename the log
git mv "logs/${OLD_S}.csv" "logs/${NEW_S}.csv"
# 5. config.yml: set the component's name to "$NEW", if it is not already
# 6. Check the names
bash .github/scripts/verify_system_names.sh
```

## Changing a monitored URL

Edit the second argument in `checks.yaml`. The URL is recorded in the log's
`NOTES` column and in Slack messages; it is not part of the system's identity.

Some URLs point at a single object: `Archive` probes the 3.17 index page of
the archive and `ExperimentHub` one `.gif` file. They show that the object
store serves files. If the object is removed upstream, the check fails without
an outage; replace the URL.

## Adding a check type

The script dispatches on its first argument:

```bash
if [ "$CHECKTYPE" == "webcheck" ]; then
  ...
elif [ "$CHECKTYPE" == "statscheck" ]; then
  ...
else
  echo "ERROR: UNKNOWN CHECK TYPE!!"
  exit 1
fi
```

A new branch writes `pass` or `fail` to `/tmp/check`; incident handling,
logging and notification are shared. `statscheck` is the model for a check on
content rather than reachability: it extracts a date with
`grep -oP "Data as of \K[^<]+"` and compares it with the current time. It uses
GNU `grep -P` and `date -d`, which the `ubuntu-latest` runners provide and
macOS does not.

## Opening or closing an incident by hand

Planned maintenance and outages the checks cannot see are announced with a
hand-written incident. Create a file in `content/issues/`, for example
`content/issues/2026-11-02-09-00-00_Main_site.md`:

```markdown
---
title: Scheduled maintenance - main site
date: 2026-11-02 09:00:00
resolved: false
# resolvedWhen:
# Possible severity levels: down, disrupted, notice
severity: notice
affected:
  - Main site
section: issue
---

The main site will be unavailable between 09:00 and 11:00 UTC for planned
maintenance.
```

Then commit and push to `main`.

- `section: issue` is required. cState lists only pages with that parameter;
  without it the file is published but appears nowhere on the page.
- `affected:` entries must match `name` values in `config.yml` exactly.
- `severity: notice` shows the component as "Maintenance". The checks never
  change a notice; if the service fails during the window they open a separate
  incident.
- An open incident with `severity: disrupted` or `down` whose file name ends
  in `_<System>.md` is taken over by that system's check: the next passing run
  resolves a `disrupted` incident and moves a `down` one to `disrupted`. Use
  `notice`, or a file name that does not end in the system name, for an
  incident the checks must leave alone.

To close an incident, set `resolved: true` and add
`resolvedWhen: <YYYY-MM-DD hh:mm:ss>` in UTC to its front matter, then commit
and push. Nothing closes a notice automatically.

[examples/maintenance-notice.md](examples/maintenance-notice.md) walks through
a full maintenance announcement.
