# Troubleshooting

## The status page is stale

When the checks stop, the page keeps showing the last state it had. Start
from the workflows, not the site: Actions → **Scheduled checks**.

| Symptom | Cause | Fix |
|---|---|---|
| No runs for hours | The scheduled workflow is disabled (GitHub disables schedules in public repositories after 60 days without activity), or GitHub Actions has an incident | Actions → Scheduled checks → *Enable workflow*; check githubstatus.com |
| Runs fail in *Checkout repository* with an authentication error | `PAT` expired or was revoked | Issue a new token and update the secret; see [security.md](security.md#pat) |
| Runs are green but no new `Update website checks` commits appear on `main` | `git push` failed inside the check step, whose exit status ignores it: branch protection, a token without write access, or a concurrent push | Read the `git push` output in the *Check site accessibility and push results* log |
| Commits arrive but the page does not change | The deploy did not start, is queued, or failed | See the next section |
| Runs arrive every 10 to 30 minutes instead of 5, occasionally more than an hour apart | GitHub starts scheduled runs late under load | Nothing to fix |

## Commits arrive but the page does not change

1. A commit that only changes `logs/` does not start a deploy. Only commits
   that open, change or close an incident do.
2. Actions → **Deploy Hugo site to Pages**. A deploy takes about half an hour
   and only one runs at a time, so a new incident can wait behind a running
   deploy.
3. If the deploy failed, read its log; build failures are covered below.

## The Hugo build fails

Reproduce with the version in `HUGO_VERSION`:

```bash
git submodule update --init --recursive
hugo version
hugo --gc --minify --destination "$(mktemp -d)"
```

| Output | Cause |
|---|---|
| `WARN found no layout file …` and a site with no pages | The theme submodule is not checked out |
| Template errors naming a function, method or field | The Hugo version removed something the theme uses; set `HUGO_VERSION` back and see [updating.md](updating.md#hugo) |
| A front matter or YAML error naming a file in `content/issues/` | A malformed hand-written incident |

## The deploy fails at *Install Dart Sass*

`hugo.yaml` installs the current `dart-sass` snap on every deploy, without a
version, so a Snap Store outage or a broken release fails every deploy. The
cState theme has no Sass files and the build does not use Dart Sass: delete
the *Install Dart Sass* step from `hugo.yaml`.

## A component always shows operational

The component's `name` in `config.yml` differs from the name its check
reports. Find the mismatch:

```bash
bash .github/scripts/verify_system_names.sh

# Every name incidents have used, with counts
grep -h -A1 '^affected:' content/issues/*.md | grep '^  - ' | sort | uniq -c
```

On the site, the component's link goes to `/affected/<slug>/`; a 404 there for
a component with past outages confirms it. Fix it as in
[checks.md](checks.md#renaming-a-system).

## A component stays disrupted or down after the service recovers

- The check still fails. Run the probe as the check does:

  ```bash
  curl -s --head -L --request GET '<url>' | grep '^HTTP'
  ```

  If the URL itself is wrong, fix it in `checks.yaml`; the next passing runs
  close the incident.
- A `down` incident needs two passing runs to close, and a service that fails
  again in between goes back to `down`.
- Two incidents are open for the component; see the next section.

To close an incident without waiting, edit it by hand as in
[operations.md](operations.md#closing-an-incident-by-hand).

## Two incidents are open for one component

This happens when a hand-written `disrupted` or `down` incident whose file name
ends in `_<System>.md` is open at the same time as an automated one. The script
then reads both severities as one two-line value: failing runs change nothing
and send no notification, and passing runs match neither branch, change nothing,
and send a Slack notification on every run.

Find them and close one by hand:

```bash
grep -l 'resolved: false' content/issues/*_<System>.md
```

## Slack notifications do not arrive

1. **Secrets.** If `SLACK_BOT_TOKEN` or `SLACK_CHANNEL_ID` is empty, *Build
   Slack payload* and *Notify slack channel* show as skipped.
2. **Changes.** Notifications are sent only when an incident is opened,
   escalated, de-escalated or resolved. The check step's log shows
   `notify=yes` when one is due.
3. **Slack API errors.** *Notify slack channel* logs the Slack API response.
   Errors such as `not_in_channel`, `channel_not_found`, `invalid_auth` or
   `missing_scope` are logged without failing the step. Invite the bot to the
   channel, check the channel ID, or reissue the token with `chat:write`.

## A check fails but the service works

- The final response is not 200: a `204`, `206`, `403` or `405`, for example.
  `webcheck` passes on 200 only.
- The service blocks `curl`'s user agent or GitHub's runner addresses.
- The runner reaches the service over a different network path or IP version
  than you do.

Reproduce with the `curl` command above, and compare with the `NOTES` column
of `logs/<System>.csv`, which records the status line the runner saw.

## A check passes but the service is down

- The URL redirects to another host that answers 200, such as a plain-HTTP
  name redirecting to an unrelated site. Probe the `https://` URL the service is
  served from.
- A CDN answers from cache while the origin is down. Probe a path the CDN does
  not cache, if there is one.
- `statscheck` passes when the statistics page cannot be fetched or has no
  `Data as of` date; see
  [architecture.md](architecture.md#known-limitations).

## `statscheck` fails but the statistics page loads

The page's date is more than 60 hours old: the statistics stopped updating.
Check the date the page shows:

```bash
curl -s https://bioconductor.org/packages/stats/bioc/ | grep -o 'Data as of [^<]*'
```

The fix is in the pipeline that produces the statistics, not in this
repository.

## The check step times out or retries

`nick-fields/retry` starts a new attempt only when one exceeds 10 minutes,
usually because a monitored URL accepts the connection and never answers;
`curl` runs without a time limit. A new attempt runs every check again on top
of the interrupted attempt's changes, so an incident can move two steps in one
run. Find the slow URL in the step log, then fix or remove its check.

## `hugo serve` shows an empty or unstyled page

The theme submodule is not checked out:

```bash
git submodule update --init --recursive
```
