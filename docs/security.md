# Security

The status page holds no private data. What needs protecting is the ability to
write to it: whoever can push to this repository decides what the page says
about Bioconductor's services.

## Trust boundaries

- Everything in the repository and on the site is public.
- The checks send unauthenticated GET requests to public URLs. No credential
  reaches a monitored service.
- Three things write: the checks workflow, pushing to `main` with `PAT`; people
  with write access to the repository; and the deploy workflow, whose
  `GITHUB_TOKEN` has `pages: write` and `id-token: write`.
- The Slack bot token can post to the notification channel.

## Secrets

All three are GitHub Actions repository secrets.

### `PAT`

**Grants:** whatever the token's owner and permissions allow. The checks need
only Contents read and write on this repository.

**Use:** a fine-grained personal access token limited to this repository with
Contents read and write, as described in
[deployment.md](deployment.md#pat). A classic token with the `repo` scope
grants write access to every repository its owner can write to.

**Owner:** the token acts as the person who created it. If that account loses
access to the organisation, the checks stop. A machine account owned by the
project avoids this.

**Expiry:** an expired token makes the checks fail and the page stop updating
while still showing its last state. Record the expiry date where the
maintainers will see it, and rotate before then:

1. Create the new token with the same settings.
2. Settings → Secrets and variables → Actions → `PAT` → update.
3. Actions → **Scheduled checks** → *Run workflow*, and confirm a new
   `Update website checks` commit on `main`.
4. Revoke the old token.

### `SLACK_BOT_TOKEN`

**Grants:** the scopes of the Slack app. The workflow needs only `chat:write`;
remove any other scope the app has. Use a bot token (`xoxb-`), never a user
token (`xoxp-`), which acts as a person.

**Rotation:** reissue the token from the Slack app's settings, update the
secret, and confirm the next notification arrives.

### `SLACK_CHANNEL_ID`

Not sensitive.

## Who can change the page

- Anyone who can push to `main`, or merge into it, can publish or resolve an
  incident. It appears on the page with the next deploy.
- Repository secrets are available to workflows on any branch. Anyone who can
  push a branch to this repository can run a workflow that reads `PAT` and
  `SLACK_BOT_TOKEN`.

Treat repository write access as access to both secrets, and review changes
under `.github/` as changes to how they are used.

Workflow triggers:

| Workflow | Triggers | Credentials |
|---|---|---|
| `checks.yaml` | `schedule`, `workflow_dispatch` | `PAT`, Slack secrets; read-only `GITHUB_TOKEN` |
| `hugo.yaml` | `push` to `main`, `workflow_dispatch` | `GITHUB_TOKEN` with Pages deployment rights |
| `verify.yaml` | `pull_request`, `workflow_dispatch` | Read-only `GITHUB_TOKEN`; no secrets |

Do not add `pull_request_target`, or a `pull_request` trigger to
`checks.yaml`: either would run pull request code with secrets in scope.

## Domain

`dev.status.bioconductor.org` is a CNAME to `bioconductor.github.io` and the
custom domain of this repository's Pages site, with HTTPS enforced. A DNS
record that points at a `github.io` host but is not the custom domain of any
Pages site can be claimed by another GitHub account's Pages site. Remove or
redirect such records, and verify the organisation's domains in its Pages
settings so only Bioconductor repositories can use them.

## The checks

- Unauthenticated probes see what a member of the public sees. A service that
  works for anonymous users and fails for signed-in users passes.
- `webcheck` follows redirects. A redirect changed by a DNS or proxy
  misconfiguration is followed, and a 200 from the new target passes.
- `statscheck` decides from the page's content. Point it only at pages
  Bioconductor controls.

## Incident content

Incident files are public and stay in the git history after they are edited
or deleted. Automated incidents contain a URL, a timestamp and the title from
`checks.yaml`. Hand-written incidents should not name software versions, hosts,
credentials or other details that help an attacker; write them as public
announcements.

## Dependencies

- The cState theme is a submodule pinned to a commit and changes only when
  the pointer is moved; see [updating.md](updating.md#cstate-theme).
- Actions published by GitHub (`actions/*`) are referenced by major-version
  tag. The checks job holds `PAT`: `actions/checkout` stores it in the job's
  git configuration, where every later step can read it, so the third-party
  actions in that job, `nick-fields/retry` and `slackapi/slack-github-action`,
  are pinned to commit SHAs.
- The deploy workflow downloads Hugo from its GitHub release by version and
  installs Dart Sass from the Snap Store without a version.

### Recommended changes

Not applied in this repository:

1. Verify the Hugo download against the release's checksum file, and remove
   the Dart Sass step, which the cState theme does not use.
2. Issue `PAT` from a machine account.

## Reporting a vulnerability

Do not open a public issue. Email the Bioconductor core team at
[bioconductorcoreteam@gmail.com](mailto:bioconductorcoreteam@gmail.com), the
contact published on [bioconductor.org/about](https://bioconductor.org/about/).
