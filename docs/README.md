# status.bioconductor.org documentation

Maintainer documentation for the Bioconductor status page. The top-level
[`README.md`](../README.md) describes the page; these documents cover running
it, changing what it monitors and deploying it elsewhere.

## Quick facts

| | |
|---|---|
| Site | <https://dev.status.bioconductor.org> |
| Hosting | GitHub Pages, deployed by GitHub Actions on pushes to `main` |
| Checks | GitHub Actions, scheduled `*/5 * * * *`; runs typically arrive every 10 to 30 minutes |
| Site generator | Hugo, version pinned as `HUGO_VERSION` in `.github/workflows/hugo.yaml` |
| Theme | cState, pinned by the `themes/cstate` submodule |
| DNS | `dev.status.bioconductor.org` CNAME `bioconductor.github.io`, in the bioconductor.org zone on Cloudflare |
| State | This repository: `content/issues/` and `logs/` |
| Secrets | `PAT`, `SLACK_BOT_TOKEN`, `SLACK_CHANNEL_ID` |
| Notifications | Slack, one message per run in which an incident changed |

## Documents

| Document | Covers |
|---|---|
| [architecture.md](architecture.md) | Components, data flow, incident lifecycle, timing, known limitations |
| [checks.md](checks.md) | Adding, changing, renaming and removing checks; hand-written incidents |
| [deployment.md](deployment.md) | Deploying from scratch: secrets, Pages, custom domain, first run |
| [operations.md](operations.md) | Health checks, routine tasks, backups, repository growth |
| [updating.md](updating.md) | Update procedures and cadence: Bioconductor releases, Hugo, theme, Actions, runner image |
| [troubleshooting.md](troubleshooting.md) | Symptom, cause and fix |
| [security.md](security.md) | Trust boundaries, secrets, hardening, reporting a vulnerability |
| [examples/](examples/) | Monitoring a new service; announcing maintenance |

## Before changing checks

A check and its component are joined only by the system name. The name passed
to `web_check_and_report.sh`, the `name` in `config.yml` and the `affected:`
entries of incidents must match exactly, and a mismatch shows no error: the
component stays operational. [checks.md](checks.md) covers the rules.
`.github/scripts/verify_system_names.sh` compares the first two; it does not
read the `affected:` entries of hand-written incidents.
