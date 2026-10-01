# Architecture

The status page has no server of its own. GitHub Actions runs the checks, the
repository stores incidents and check history, Hugo renders the site with the
[cState](https://github.com/cstate/cstate) theme, and GitHub Pages serves it at
<https://dev.status.bioconductor.org>.

None of this shares infrastructure with the services it monitors, so the page
stays up during a Bioconductor outage. It does depend on GitHub; the `GitHub`
component links to githubstatus.com and has no check.

## Components

| Component | Path | Role |
|---|---|---|
| Scheduled checks | `.github/workflows/checks.yaml` | Runs every check, commits the results, sends Slack notifications |
| Check script | `.github/scripts/web_check_and_report.sh` | Probes one URL and updates that system's incident and log |
| Incident template | `.github/templates/incident.md` | Front matter for incidents the checks create |
| Site configuration | `config.yml` | Categories, components (`systems:`), colours, output formats |
| Incidents | `content/issues/` | One Markdown file per incident, automated or hand-written |
| Check history | `logs/<System>.csv` | One row per check run; the site does not read it |
| Theme | `themes/cstate` (git submodule) | Every template the site uses |
| Deploy workflow | `.github/workflows/hugo.yaml` | Builds the site and deploys it to GitHub Pages |
| Verify workflow | `.github/workflows/verify.yaml` | Checks pull requests for system names `config.yml` does not declare |

## External dependencies

| Dependency | Used for |
|---|---|
| GitHub Actions | Running the checks and the site build |
| GitHub Pages | Serving the site and its TLS certificate |
| bioconductor.org DNS (Cloudflare) | `dev.status.bioconductor.org` CNAME to `bioconductor.github.io` |
| Slack | Notifications; optional |

## Data flow

```
GitHub Actions schedule (*/5 * * * *)
  └─ checks.yaml
       ├─ git pull origin main
       ├─ web_check_and_report.sh, once per monitored URL
       │    ├─ probe the URL
       │    ├─ create, escalate, de-escalate or resolve
       │    │  content/issues/<timestamp>_<System>.md
       │    └─ add a row to logs/<System>.csv
       ├─ git commit, git push (PAT)
       └─ Slack chat.postMessage, when an incident changed

push to main that changes anything outside logs/
  └─ hugo.yaml: hugo build → upload artifact → deploy to GitHub Pages
```

The state is the repository: incidents are files under `content/issues/`, and
the site is rebuilt from them on every deploy.

## Check types

`web_check_and_report.sh` takes five arguments: check type, URL, incident
title, initial severity and system name.

- **`webcheck`** runs `curl -s --head -L --request GET <url>` and passes when
  an `HTTP` status line in the response, including those of followed
  redirects, contains `200`.
- **`statscheck`** fetches the page, reads the date after `Data as of`, and
  fails when that date is more than 60 hours old. It is used for
  <https://bioconductor.org/packages/stats/bioc/>, which keeps returning 200
  when the statistics stop updating.

A new type is a new branch of the `if`/`elif` at the top of the script. It must
write `pass` or `fail` to `/tmp/check`; incident handling, logging and
notification are shared.

## Incident lifecycle

The script looks for open incidents of the system by file name
(`content/issues/*_<System>.md`) with `resolved: false` and
`severity: disrupted` or `severity: down`. Incidents with `severity: notice`
are never changed by the checks.

| Open incident | Check fails | Check passes |
|---|---|---|
| none | create one with the initial severity (`disrupted` for every check); notify | log only |
| `disrupted` | set `severity: down`; notify | set `resolved: true` and `resolvedWhen`; notify |
| `down` | no change; no notification | set `severity: disrupted`; notify |

- An outage that lasts one run opens and closes an incident.
- An outage that lasts longer ends at `down` and needs two passing runs to
  resolve.
- A service that alternates between failing and passing opens a new incident
  on each failure, and the next pass resolves it. Once an incident has reached
  `down`, alternation moves it between `down` and `disrupted`. Every change
  sends a notification.

Incident file names use the run's time in `America/New_York`
(`2026-09-25-01-28-25_Main_site.md`). The `date` and `resolvedWhen` fields use
the runner's clock, which is UTC.

## Component status

cState sets each component's status in
`themes/cstate/layouts/partials/index/components.html`:

```go-html-template
{{ $activeComponentIssues := where $active "Params.affected" "intersect" (slice $system.name) }}
```

Open incidents whose `affected:` list contains the component's `name`, compared
as exact strings, decide the status: `down` if any is down, otherwise
`disrupted`, otherwise `notice` (shown as "Maintenance"), otherwise operational.
The checks write the system name argument into `affected:`, so a check whose
name differs from every `name` in `config.yml` produces incidents that no
component shows, and nothing reports the mismatch.
[checks.md](checks.md#the-three-places-a-system-name-appears) has the rules.

Each component links to `/affected/<slug>/`, where the slug is the name in
lower case with spaces replaced by hyphens. Hugo creates that page only after
the first incident naming the component.

## Logs

`logs/<System>.csv` holds one row per check run, newest first:

```csv
DATE,SERVICE,NOTES,STATUS
2026-10-01-07-33-19,Main_site,http://bioconductor.org HTTP/2 200,ok
```

`DATE` is `America/New_York` time, `NOTES` is the URL and the last status line,
and `STATUS` is `ok` or `down`. To keep the newest row first, every run
rewrites the whole file. `legacy-logs/checks.csv` is the earlier combined log,
oldest first, ending on 2026-01-31; nothing writes to it.

## Notifications

1. A check that changes an incident writes `/tmp/webcheckflag-<System>` and
   appends its details to `/tmp/webchecknotify-msg`.
2. After the push, any flag file sets the step output `notify=yes`.
3. *Build Slack payload* turns the message into a JSON payload with `jq`.
4. *Notify slack channel* posts it with `slackapi/slack-github-action` and
   `method: chat.postMessage`.

Both Slack steps are skipped when `SLACK_BOT_TOKEN` or `SLACK_CHANNEL_ID` is
empty, and the posting step is `continue-on-error`. A message lists, per
changed system, the monitored URL, a link to the incident and the severity
change.

## Site build and deployment

`hugo.yaml` runs on every push to `main` except pushes whose changed paths are
all under `logs/`, and on manual dispatch. It installs Hugo extended at
`HUGO_VERSION`, checks out the repository with the theme submodule and full
history (`fetch-depth: 0`, used by `enableGitInfo` in `config.yml` for
last-modified dates), builds with
`hugo --gc --minify --baseURL <Pages URL>` and deploys the `public/` artifact.
The deploy concurrency group is `pages`; a running deploy is never cancelled.

The full-history checkout takes most of the run, about half an hour; the Hugo
build itself takes under a minute. An incident therefore reaches the site
about half an hour after the check that opened it, longer when another deploy
is running; the Slack notification is sent by the check run itself.

## Published outputs

| Path | Content |
|---|---|
| `/` | Status page |
| `/issues/<file name in lower case>/` | One incident |
| `/affected/<slug>/` | One component and its incidents |
| `/index.json`, `/affected/<slug>/index.json` | cState read-only JSON API |
| `/index.xml`, `/issues/index.xml`, `/affected/<slug>/index.xml` | RSS feeds |
| `/index.svg`, `/affected/<slug>/index.svg` | Status badges |

GitHub Pages sends `Access-Control-Allow-Origin: *`, so other sites can read
the JSON API. `vercel.json` and `static/_headers` set the same header on Vercel
and Netlify.

## Timing

| | |
|---|---|
| Schedule | `*/5 * * * *`; GitHub starts scheduled runs late under load, and runs typically arrive every 10 to 30 minutes, occasionally more than an hour apart |
| Concurrency | group `webchecks`: one run at a time; a newer queued run replaces an older queued one |
| New incident | first failing run |
| `down` | second consecutive failing run |
| Resolution | one passing run from `disrupted`, two from `down` |
| `statscheck` threshold | 60 hours |
| Site update | one deploy run, about half an hour |

The page reports outages within minutes to an hour. It is not a paging system.

## Known limitations

- A passing `webcheck` means a response in the redirect chain returned 200,
  not that the expected host served it. A plain-HTTP URL that redirects to
  another site passes when that site is up.
- The `Slack app` check probes `http://slack.bioconductor.org`, which
  redirects to `https://git.bioconductor.org/`, so the component reports the
  health of git.bioconductor.org.
- `statscheck` passes when the page cannot be fetched or has no `Data as of`
  date: GNU `date -d ""` returns the start of the current day.
- The check step's exit status is that of its last command, so a failed
  `git push` leaves the run green while nothing is published.
  `nick-fields/retry` retries the step only when it exceeds its 10-minute
  timeout.
- Two open `disrupted` or `down` incidents for one system stop that system's
  state machine; see
  [troubleshooting.md](troubleshooting.md#two-incidents-are-open-for-one-component).
- Rewriting every log file on every run is the main source of repository
  growth; see [operations.md](operations.md#repository-growth).
