# Updating

What changes over time in this repository, how often to update it, how to
check that an update worked, and how to roll it back.

## What is pinned where

| Part | Pinned in | Show the current value |
|---|---|---|
| Hugo | `HUGO_VERSION` in `.github/workflows/hugo.yaml` | `grep HUGO_VERSION .github/workflows/hugo.yaml` |
| Dart Sass | Not pinned: `hugo.yaml` installs the current `dart-sass` snap on every deploy | The *Install Dart Sass* step log |
| cState theme | Commit of the `themes/cstate` submodule | `git submodule status` |
| GitHub Actions | `uses:` lines in `.github/workflows/*.yaml`: `actions/*` by major-version tag, the others by commit SHA | `grep -n 'uses:' .github/workflows/*.yaml` |
| Runner image | `runs-on: ubuntu-latest` in every workflow | Moves when GitHub moves the label |
| Tools used by the scripts | The runner image | See [Runner image and script tools](#runner-image-and-script-tools) |
| Monitored URLs | `checks.yaml` and `config.yml` | See [Bioconductor releases](#bioconductor-releases) |

## Cadence

| Part | When |
|---|---|
| Bioconductor release review | At each release, in spring and autumn |
| GitHub Actions | Every three months, and when GitHub announces the end of a runtime an action uses |
| Hugo | Every six months, and when a theme update needs a newer version |
| cState theme | Yearly |
| Runner image | When GitHub announces that `ubuntu-latest` moves to a new Ubuntu release |
| `PAT` | Before it expires; see [security.md](security.md#pat) |

## Procedure

Every update follows the same steps:

1. Make the change on a branch and open a pull request.
2. Run the local checks for that part, described below.
3. Merge; the merge starts **Deploy Hugo site to Pages**. Run **Scheduled
   checks** from the Actions tab if the change affects the checks, then go
   through [Verification](#verification).
4. If the result is wrong, [roll back](#rollback).

Change one part per pull request, so a rollback undoes only that part.

## Bioconductor releases

Bioconductor releases twice a year. At each release, review what the checks
probe.

1. **Versioned URLs.** List the checks whose URL contains a version:

   ```bash
   grep -n -E "/[0-9]+\.[0-9]+/" .github/workflows/checks.yaml
   ```

   `Archive` probes the archive's 3.17 index page; archived releases stay in
   the archive, so it changes only if the archive is reorganised. A check on a
   specific release, such as the webR check in
   [examples/add-a-check.md](examples/add-a-check.md), moves to the new release:
   change the URL in `checks.yaml` and the `description` or `link` in
   `config.yml` if they name the version.
2. **Package repositories.** For checks on the package repositories, use the
   `release` and `devel` aliases, for example
   `https://bioconductor.org/packages/release/bioc/src/contrib/PACKAGES`. They
   point at the new versions on release day without a change here. Name such
   components without the version and without characters that are invalid in
   file names, such as `*`; see
   [checks.md](checks.md#choosing-a-system-name).
3. **New and retired services.** Add checks for services launched with the
   release and remove checks for retired ones, as in [checks.md](checks.md).
4. **Probe every URL** the checks use:

   ```bash
   awk '{ if (sub(/\\[[:space:]]*$/, "")) { buf = buf $0; next } print buf $0; buf = "" }' \
       .github/workflows/checks.yaml \
     | grep -o "web_check_and_report.sh *'[a-z]*' *'[^']*'" \
     | awk -F"'" '{print $4}' \
     | while read -r url; do
         printf '%s\t%s\n' "$(curl -s -o /dev/null -L --max-time 30 \
           -w '%{http_code} %{url_effective}' "$url")" "$url"
       done
   ```

   Each line shows the final status, the final URL after redirects and the
   configured URL. Look for codes other than 200, and for redirects that end on
   a different host. For the `statscheck` URL (*Package Stats*) a 200 is not
   enough: the page's `Data as of` date must be less than 60 hours old; see
   [architecture.md](architecture.md#check-types).
5. Put the `config.yml` and `checks.yaml` changes in one pull request, so the
   **Verify configuration** workflow checks them together.

After merging, run **Scheduled checks** manually. Each new or changed check
adds an `ok` row to its `logs/<System>.csv` and opens no incident.

## Hugo

The deploy workflow installs `hugo_extended_<HUGO_VERSION>_linux-amd64.deb`
from the Hugo release on GitHub; the version must publish that file. Hugo
removes deprecated template functions over time, and the cState theme is
older than recent Hugo releases, so build the full content with the new
version before changing the pin.

1. Install the candidate version locally from
   <https://github.com/gohugoio/hugo/releases>.
2. Build:

   ```bash
   git submodule update --init --recursive
   hugo version
   hugo --gc --minify --destination "$(mktemp -d)" 2>&1 | tee /tmp/hugo-build.log
   grep -E 'WARN|ERROR' /tmp/hugo-build.log
   ```

   The build must finish without `ERROR`. Compare the `Pages` count in the
   summary with a build at the pinned version; the counts must match.
3. Set `HUGO_VERSION` in `hugo.yaml` to the new version and merge. The merge
   starts **Deploy Hugo site to Pages**; check that run.

Rollback: revert the `HUGO_VERSION` change.

## Dart Sass

`hugo.yaml` installs the current `dart-sass` snap on every deploy, without a
version. The cState theme has no Sass files and the build does not use it, so
there is nothing to update. If the *Install Dart Sass* step fails, remove the
step; see
[troubleshooting.md](troubleshooting.md#the-deploy-fails-at-install-dart-sass).

## cState theme

The theme supplies every template, including the logic that matches
incidents to components and the JSON API. cState 6 changes the configuration
file and the CSS and needs Hugo 0.110 or newer; moving from version 5 is a
migration, described in the
[v6.0.0 release notes](https://github.com/cstate/cstate/releases/tag/v6.0.0).

```bash
cd themes/cstate
git fetch --tags origin
git log --oneline HEAD..<tag>        # the changes being taken
git checkout <tag>
cd ../..
hugo --gc --minify --destination "$(mktemp -d)"
git add themes/cstate
git commit -m "Update cState to <tag>"
```

Before merging, compare the built site with the live one: component status
and categories, incident pages, `/affected/<slug>/` pages, and
`/index.json`, whose `cStateVersion` shows the theme version. Check that
`themes/cstate/layouts/partials/index/components.html` still matches
components with `affected` by exact name, and that
`.github/templates/incident.md` still has the front matter the theme expects.

Rollback: revert the commit and run `git submodule update` locally.

## GitHub Actions

| Action | Workflows | What depends on it |
|---|---|---|
| `actions/checkout` | all | `checks.yaml` pushes with the `PAT` it persists (`persist-credentials: true`); `hugo.yaml` needs `submodules: recursive` and `fetch-depth: 0` |
| `nick-fields/retry` | `checks.yaml` | Inputs `timeout_minutes`, `max_attempts`, `shell`, `command` |
| `slackapi/slack-github-action` | `checks.yaml` | Inputs `method`, `token`, `payload-file-path` |
| `actions/configure-pages`, `actions/upload-pages-artifact`, `actions/deploy-pages` | `hugo.yaml` | Update together; `upload-pages-artifact` leaves out hidden files unless `include-hidden-files` is set |

Find the latest release of an action:

```bash
gh api repos/actions/checkout/releases/latest --jq .tag_name
```

`nick-fields/retry` and `slackapi/slack-github-action` are pinned to a commit
SHA, with the version in a comment. Resolve the new tag to its commit, then
replace the SHA and the version comment:

```bash
gh api repos/<owner>/<action>/commits/<tag> --jq .sha
```

Read the release notes for removed or renamed inputs, change the `uses:` line
and open a pull request. The merge starts **Deploy Hugo site to Pages**; run
**Scheduled checks** manually and go through [Verification](#verification).
Slack notifications are sent only when an incident changes, so a Slack action
update is confirmed by the next real notification.

Rollback: revert the `uses:` change.

### Recommended changes

Not applied in this repository:

1. Add a `.github/dependabot.yml` for the `github-actions` ecosystem, so
   Dependabot opens a pull request when an action has a new release.

## Runner image and script tools

Every workflow runs on `ubuntu-latest`. The scripts depend on what that image
provides:

| Script | Needs |
|---|---|
| `web_check_and_report.sh` | `bash`, `curl`, `git`, GNU `sed -i`, `xargs -i`, `tac`, GNU `date -d`, `grep -P` |
| *Build Slack payload* step | `jq` |
| `verify_system_names.sh` | `bash`, `awk`, `sed`, `grep`, `sort`, `comm` |
| `hugo.yaml` | `wget`, `dpkg`, `snap` |

When GitHub moves `ubuntu-latest` to a new release, run **Scheduled checks**
and **Deploy Hugo site to Pages** manually and read the logs for
`command not found` or option errors. Each check must add a row to its log
file.

Rollback: set `runs-on` to the previous `ubuntu-<version>` label until the
scripts are fixed.

## Verification

After any update:

- [ ] `bash .github/scripts/verify_system_names.sh` ends with `OK`.
- [ ] The **Scheduled checks** log shows every check, ends with a successful
      `git push`, and has no `command not found`; `main` has a new
      `Update website checks` commit.
- [ ] **Deploy Hugo site to Pages** succeeds.
- [ ] <https://dev.status.bioconductor.org> shows every component in its
      category, and
      `curl -s https://dev.status.bioconductor.org/index.json | jq '.systems | length'`
      matches the number of components in `config.yml`.
- [ ] For a release review: no new incident from a changed URL.

## Rollback

Revert the commit on a branch and open a pull request, as in
[Procedure](#procedure):

```bash
git fetch origin
git switch -c revert-<topic> origin/main
git revert <commit>
git push -u origin revert-<topic>
```

A revert of a workflow, configuration or theme change touches files outside
`logs/`, so it starts a deploy. If a wrong URL opened an incident, close it by
hand as in [operations.md](operations.md#closing-an-incident-by-hand).
