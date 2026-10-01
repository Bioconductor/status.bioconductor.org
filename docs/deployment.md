# Deployment

Deploying the status page from scratch, either as Bioconductor's page or as a
copy for another project. Everything runs on GitHub: a repository with Actions
and Pages, three secrets, and one DNS record.

## Prerequisites

- A GitHub repository. Pages for a private repository needs a paid GitHub
  plan; Bioconductor's repository is public.
- Hugo, to build locally. Use the version pinned as `HUGO_VERSION` in
  [`hugo.yaml`](../.github/workflows/hugo.yaml).
- For notifications, a Slack workspace where you can install an app.
- Access to the DNS zone of the domain the page will use.
- `git`, `curl`, `jq` and the GitHub CLI (`gh`, logged in), used by the
  commands in this documentation.

## 1. Get the code

For Bioconductor's page:

```bash
git clone --recursive https://github.com/Bioconductor/status.bioconductor.org
```

The cState theme is the `themes/cstate` submodule. Without it Hugo builds a site
with no templates and prints only `WARN` lines about missing layouts. In a
clone made without `--recursive`:

```bash
git submodule update --init --recursive
```

For another project, start a new repository with the same theme version and
copy the configuration and automation, without Bioconductor's incidents and
logs:

```bash
git init -b main my-status && cd my-status
git clone --depth 1 https://github.com/Bioconductor/status.bioconductor.org ../bioc-status
git submodule add https://github.com/cstate/cstate themes/cstate
git -C themes/cstate checkout "$(git -C ../bioc-status rev-parse HEAD:themes/cstate)"
cp -R ../bioc-status/.github ../bioc-status/config.yml ../bioc-status/static \
  ../bioc-status/layouts ../bioc-status/vercel.json .
mkdir -p content/issues && touch content/issues/.gitkeep
```

Commit `content/issues/.gitkeep` with the rest: the check script writes
incidents into `content/issues/` but does not create it, and git does not keep
empty directories. Hugo does not publish the file.

Then replace the Bioconductor-specific values:

| File | Values |
|---|---|
| `config.yml` | `title`, `baseURL`, `description`, `logo`, `brand` and the other colours, `categories:`, `systems:` |
| `static/` | The logo file named by `logo` |
| `.github/workflows/checks.yaml` | The list of checks |
| `.github/scripts/web_check_and_report.sh` | `https://dev.status.bioconductor.org/` and `https://github.com/Bioconductor/status.bioconductor.org/blob/main/`, used in Slack messages |

Commit, create an empty repository on GitHub, and push `main` to it;
`checks.yaml` and `hugo.yaml` expect the default branch to be `main`.

```bash
git add -A
git commit -m "Initial status page"
git remote add origin https://github.com/<owner>/<repository>.git
git push -u origin main
```

`git add -A` also records the theme commit checked out above. `config.yml` sets
`enableGitInfo: true`, so once `content/` holds an incident, Hugo builds only in
a repository with at least one commit. Workflow runs fail until the secrets and
Pages are set up in steps 3 and 4.

## 2. Configure components and checks

Each monitored service needs a component under `systems:` in `config.yml` and a
`web_check_and_report.sh` line in the `command:` block of `checks.yaml`, with
the same name in both. [checks.md](checks.md#adding-a-check) covers both
steps, the arguments and the naming rules. Check the names with:

```bash
bash .github/scripts/verify_system_names.sh
```

The schedule is the `cron` entry in `checks.yaml` (`*/5 * * * *`). GitHub
starts scheduled runs late under load, so a shorter interval does not give
proportionally faster detection.

## 3. Add the repository secrets

Settings → Secrets and variables → Actions:

| Secret | Required | Purpose |
|---|---|---|
| `PAT` | yes | Token the checks workflow uses to check out and push to `main` |
| `SLACK_BOT_TOKEN` | no | Slack bot token (`xoxb-…`) for notifications |
| `SLACK_CHANNEL_ID` | no | ID of the channel notifications go to |

### `PAT`

A push made with the workflow's own `GITHUB_TOKEN` does not start other
workflows. The deploy workflow has to start when the checks commit an
incident, so the checks push with a personal access token.

Create a fine-grained personal access token with:

- Resource owner: the organisation that owns the repository. The organisation
  must allow fine-grained tokens and may require an owner to approve the
  request.
- Repository access: only this repository.
- Permissions: Contents, read and write.
- An expiry date, recorded where the maintainers will see it; see
  [security.md](security.md#pat).

If `main` is protected, the token's owner must be allowed to push to it
directly.

### Slack

1. Create a Slack app with the `chat:write` bot scope and install it in the
   workspace.
2. Invite the bot to the channel.
3. Store the bot token as `SLACK_BOT_TOKEN` and the channel ID (channel
   details → About) as `SLACK_CHANNEL_ID`.

Without these secrets the notification steps are skipped and the rest of the
workflow runs normally.

## 4. Enable GitHub Pages

Settings → Pages → Build and deployment → Source: **GitHub Actions**.
`hugo.yaml` builds the site and deploys the result as a Pages artifact.

## 5. Custom domain

1. Create a DNS record `CNAME <host> <owner>.github.io`. For Bioconductor this is
   `dev.status.bioconductor.org` → `bioconductor.github.io`, in the
   bioconductor.org zone on Cloudflare, not proxied.
2. Settings → Pages → Custom domain: enter the host and save. GitHub issues a
   certificate for it.
3. When the certificate is issued, enable **Enforce HTTPS**.
4. Verify the domain in the organisation's Pages settings, so no other
   repository can claim it.

A Pages site has one custom domain. Another name pointed at
`<owner>.github.io` gets a 404 from GitHub and a certificate for
`*.github.io`. To serve a second name, redirect it to the custom domain at the
DNS or CDN provider.

The build takes its base URL from the Pages configuration, so the deployed site
follows the custom domain. Two places name the domain explicitly and must be
changed with it: `baseURL` in `config.yml`, used by local builds and builds on
[other hosts](#other-hosts), and the recovery link in `web_check_and_report.sh`.

## 6. First run

1. Actions → **Scheduled checks** → *Run workflow*. The run probes every URL,
   creates `logs/<System>.csv` for each check and pushes a commit to `main`.
2. Actions → **Deploy Hugo site to Pages** → *Run workflow*. A push that only
   changes `logs/` does not start a deploy, so the first deploy is manual.

Scheduled runs start on their own once the workflow file is on the default
branch.

## Other hosts

`vercel.json` and `static/_headers` set CORS headers for Vercel and Netlify.
On either host, set the build command to `hugo --gc --minify`, the output
directory to `public/`, the `HUGO_VERSION` environment variable to the value in
`hugo.yaml`, and `baseURL` in `config.yml` to the site's URL. The checks still
run in GitHub Actions; their pushes start the host's build when the repository
is connected to it.

## Verifying a deployment

Locally:

```bash
bash .github/scripts/verify_system_names.sh
hugo --gc --minify --destination "$(mktemp -d)"
```

Against the deployed site:

```bash
curl -sI https://dev.status.bioconductor.org/ | head -n 1
curl -s https://dev.status.bioconductor.org/index.json | jq '.systems[] | {name, status}'
```

- Every component appears in its category, and `/index.json` lists it.
- A component with past incidents links to an `/affected/<slug>/` page that
  exists. A 404 there means the component has never had an incident, or its
  name differs from the name its check uses.
- The latest **Scheduled checks** run shows each check in its log and a
  successful `git push`.
