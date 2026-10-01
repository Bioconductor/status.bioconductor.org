# Operations

Routine tasks, health checks, backups, and the repository's growth. Update
procedures are in [updating.md](updating.md).

## Health checks

The page is healthy when the checks commit regularly and the deploys succeed.
A stale page looks like a healthy one, so check the source rather than the
site.

```bash
# Latest check commit; expect "Update website checks …" within the last hour
gh api repos/Bioconductor/status.bioconductor.org/commits/main \
  --jq '.commit.committer.date + "  " + .commit.message'

# Recent runs of both workflows
gh run list -R Bioconductor/status.bioconductor.org -w checks.yaml -L 5
gh run list -R Bioconductor/status.bioconductor.org -w hugo.yaml -L 5

# What the page reports
curl -s https://dev.status.bioconductor.org/index.json \
  | jq -r '.systems[] | "\(.status)\t\(.name)"'
```

A green **Scheduled checks** run does not prove the push succeeded; see
[troubleshooting.md](troubleshooting.md#the-status-page-is-stale). The commit
history does.

A queued deploy is cancelled when a newer push arrives, so cancelled deploy
runs are expected. The most recent deploy should succeed.

GitHub issues and renews the Pages certificate for
`dev.status.bioconductor.org`. To see its state and expiry:

```bash
gh api repos/Bioconductor/status.bioconductor.org/pages --jq .https_certificate
```

## Routine tasks

| Task | When |
|---|---|
| Run the health checks above | Weekly, and when an outage is reported elsewhere |
| Review open incidents | Weekly |
| Close hand-written notices | When the announced work ends |
| Rotate `PAT` | Before it expires; see [security.md](security.md#pat) |
| Hugo, theme, Actions and release updates | See [updating.md](updating.md#cadence) |
| Review repository growth | Yearly |

### Open incidents

```bash
git pull
grep -l 'resolved: false' content/issues/*.md
```

An automated incident stays open until its check passes. One that stays open
while the service works usually means the check URL is wrong; fix the URL as in
[checks.md](checks.md#changing-a-monitored-url) and the next passing runs close
it.

### Closing an incident by hand

Edit the incident's front matter:

```yaml
resolved: true
resolvedWhen: 2026-10-01 14:05:00
```

`resolvedWhen` is in UTC and replaces the commented `# resolvedWhen:` line.
Commit and push to `main`; the deploy that follows updates the page.

### Announcing maintenance

Write a `severity: notice` incident as described in
[checks.md](checks.md#opening-or-closing-an-incident-by-hand), with a worked
example in [examples/maintenance-notice.md](examples/maintenance-notice.md).

## Backups and restore

The repository holds all the state: incidents, check logs and configuration.
The secrets are the only other configuration and are recreated rather than
restored. A bare clone holds every branch and tag:

```bash
git clone --bare https://github.com/Bioconductor/status.bioconductor.org
```

To restore into a new, empty repository:

```bash
git -C status.bioconductor.org.git push --mirror https://github.com/<owner>/<repository>
```

Then follow [deployment.md](deployment.md) from step 3: secrets, Pages, custom
domain and a first run. Incident URLs stay the same once the custom domain
points at the new repository's site.

If only the published site is lost, run **Deploy Hugo site to Pages** from the
Actions tab.

## Repository growth

Every check run commits a new row in each log file, about a hundred commits a
day. Each commit stores a new version of every `logs/*.csv` file, and those
versions are most of the repository's size; the incident files are a small
fraction of it. Measure with:

```bash
git rev-list --count origin/main
gh api repos/Bioconductor/status.bioconductor.org --jq .size   # KiB
```

The cost shows up in clone time. The deploy workflow clones full history
(`fetch-depth: 0`) and its checkout step takes about half an hour, which delays
every incident's appearance on the page by the same amount.

### Recommended changes

Not applied in this repository; each needs testing before adoption.

1. **Partial clone in the deploy workflow.** Hugo's git information needs
   commits and trees, not file contents. `filter: blob:none` on the
   `actions/checkout` step skips the log file versions.
2. **Rotate the logs.** Move each year's rows to `logs/<year>/` so the files
   rewritten on every run stay small.
3. **Commit logs less often.** Record a row only when a system's state changes,
   or keep the per-run rows outside the repository.
4. **Archive and truncate.** Push the full history to an archive repository and
   restart `main` from a single commit. This keeps incident URLs but drops the
   history `enableGitInfo` reads for last-modified dates.

## Testing changes to the check script

`web_check_and_report.sh` uses GNU `sed -i`, `xargs -i`, `tac`, `date -d` and
`grep -P`, and runs `git add`. Test it on Linux with `bash`, `curl`, `git` and
GNU coreutils, in a scratch clone so the working repository is not modified:

```bash
git clone --depth 1 https://github.com/Bioconductor/status.bioconductor.org /tmp/status-test
cd /tmp/status-test
```

To drive the state machine, put a `curl` stub first in `PATH` that returns a
chosen status:

```bash
mkdir -p /tmp/stub
printf '#!/bin/sh\necho "HTTP/2 ${STUB_STATUS:-200}"\n' > /tmp/stub/curl
chmod +x /tmp/stub/curl

run() {
  rm -f /tmp/webcheckflag-* /tmp/webchecknotify-msg*
  STUB_STATUS=$1 PATH=/tmp/stub:$PATH bash .github/scripts/web_check_and_report.sh \
    webcheck https://example.org '(Test) Main site down' disrupted 'Main site'
  grep -H -E '^(severity|resolved):' content/issues/*_Main_site.md | tail -n 2
  ls /tmp/webcheckflag-* 2>/dev/null
}

run 503; run 503; run 503; run 200; run 200; run 200
```

Compare each step with the table in
[architecture.md](architecture.md#incident-lifecycle): a new `disrupted`
incident, then `down`, no change and no flag, back to `disrupted`, resolved,
and no flag.
