# status.bioconductor.org

The Bioconductor status page: **<https://dev.status.bioconductor.org>**

Scheduled checks in GitHub Actions probe Bioconductor's public services. When
a check fails, it writes an incident into this repository and the page, a
[Hugo](https://gohugo.io) site using the [cState](https://github.com/cstate/cstate)
theme, is rebuilt to show it. When the service recovers, the check resolves the
incident. Maintainers get a Slack message whenever an incident changes.

The page has no server or database: the checks run in GitHub Actions, the
incidents and check history are files in this repository, and GitHub Pages
serves the site.

## How it works

```
GitHub Actions schedule
  ├─ probe each monitored URL
  ├─ open, escalate, de-escalate or resolve content/issues/<timestamp>_<System>.md
  ├─ add a row to logs/<System>.csv
  ├─ commit and push to main
  └─ post to Slack if an incident changed

push to main that changes anything outside logs/
  └─ Hugo build → GitHub Pages → dev.status.bioconductor.org
```

## Repository layout

| Path | Contents |
|---|---|
| `.github/workflows/checks.yaml` | Check schedule and the list of monitored URLs |
| `.github/workflows/hugo.yaml` | Site build and deployment to GitHub Pages |
| `.github/workflows/verify.yaml` | Pull request check of system names |
| `.github/scripts/web_check_and_report.sh` | One check: probe, incident update, log row, notification flag |
| `.github/scripts/verify_system_names.sh` | Reports checks whose system name `config.yml` does not declare |
| `.github/templates/incident.md` | Template for incidents the checks create |
| `config.yml` | cState configuration, including the components under `systems:` |
| `content/issues/` | Every incident, one file each |
| `logs/` | Check history, one CSV file per system; not read by the site |
| `legacy-logs/` | Combined check history up to January 2026 |
| `themes/cstate` | The cState theme, as a git submodule |
| `layouts/`, `static/` | Template overrides (none) and static files such as the logo |
| `vercel.json` | CORS headers for a Vercel deployment |

## Documentation

Maintainer documentation is in [docs/](docs/README.md):

- [Architecture](docs/architecture.md)
- [Adding, changing and removing checks](docs/checks.md)
- [Deployment](docs/deployment.md)
- [Operations](docs/operations.md)
- [Updating](docs/updating.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Security](docs/security.md)
- [Examples](docs/examples/README.md)

A check and its component are joined by the system name, which must match
exactly in `checks.yaml` and `config.yml`; a mismatch shows no error on the
page. The **Verify configuration** workflow reports it in pull requests. Read
[docs/checks.md](docs/checks.md) before changing either file.

## Building locally

```bash
git clone --recursive https://github.com/Bioconductor/status.bioconductor.org
cd status.bioconductor.org
hugo serve
```

In a clone made without `--recursive`, fetch the theme first:

```bash
git submodule update --init --recursive
```

Every check run adds a commit, so a full clone is large; see
[repository growth](docs/operations.md#repository-growth).

## Upstream

Built on [cState](https://github.com/cstate/cstate) and based on
[cstate/example](https://github.com/cstate/example); the files under
`.github/` are Bioconductor's.

## License

cState and the files from cstate/example: MIT © Mantas Vilčinskas.
