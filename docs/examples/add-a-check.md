# Example: monitoring a new service

Scenario: the webR binary repository at `https://webr.bioconductor.org` should
appear on the status page.

## 1. Choose the component name

The name is used verbatim in `config.yml` and `checks.yaml`. It becomes the
label on the page, the URL slug (`WebR Binaries` → `/affected/webr-binaries/`)
and part of the incident and log file names (`WebR_Binaries`). Use letters,
digits, spaces and hyphens. The name must not be the last words of an existing
system's name, and no existing name may be the last words of it; see
[checks.md](../checks.md#choosing-a-system-name).

This example uses **`WebR Binaries`**.

## 2. Add the component to `config.yml`

Under `systems:`, at the position it should be displayed:

```yaml
    - name: WebR Binaries
      description: WebAssembly builds of Bioconductor packages
      category: Websites
      link: https://webr.bioconductor.org
```

`category` must be one of the categories declared under `categories:`
(`Websites`, `BiocManager`, `External`, `Uncategorized`); a component with any
other category is not shown.

## 3. Add the check to `checks.yaml`

In the `command:` block, after the existing checks:

```bash
bash .github/scripts/web_check_and_report.sh \
  'webcheck' \
  'https://webr.bioconductor.org/3.23/index.html' \
  '(Auto-detected) Bioconductor WebR Binaries Down' \
  'disrupted' \
  'WebR Binaries'
```

- The root URL of `webr.bioconductor.org` returns 404, so the check probes the
  index page of a release, which is served only when the repository is.
- The URL contains a Bioconductor version. When that release's binaries are
  removed, the check fails without an outage; move it to the current release
  as part of the release review in
  [updating.md](../updating.md#bioconductor-releases).

## 4. Check the names

```bash
bash .github/scripts/verify_system_names.sh
```

`WebR Binaries` appears in both lists and the script ends with `OK`. `GitHub`
is listed as a component without a check, which is expected.

## 5. Probe the URL as the check does

```bash
curl -s --head -L --request GET 'https://webr.bioconductor.org/3.23/index.html' \
  | grep '^HTTP'
```

One of the lines shows `200`. If not, fix the URL before merging; otherwise
the first run opens an incident.

## 6. Build the site

```bash
hugo serve
```

`WebR Binaries` appears under *Websites* as operational.

## 7. Open a pull request

```bash
git switch -c monitor-webr
git add config.yml .github/workflows/checks.yaml
git commit -m "Monitor the webR binary repository"
git push -u origin monitor-webr
```

The **Verify configuration** workflow runs on the pull request. Merge when it
passes.

## 8. Confirm the first run

The next scheduled run includes the check; *Run workflow* on **Scheduled
checks** starts one immediately. In the run log, the new URL is probed, and
the commit adds `logs/WebR_Binaries.csv`.

On the site, the component is listed. Its `/affected/webr-binaries/` page
exists only after its first incident; until then the link returns 404, as it
does for `GitHub`, which has no check.

To stop monitoring the service later, follow
[checks.md](../checks.md#removing-a-check).
