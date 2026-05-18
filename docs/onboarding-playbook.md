# Onboarding Playbook: Centralized Scanning Service

This guide walks teams through adopting the org's centralized scanning service, which provides dependency management, GitHub Actions SAST, and secret scanning. It ships an **OSCAL component definition** covering CM-2, CM-3, CM-6, CM-7, IA-5, IA-9, RA-5, SA-10, SA-11, SA-22, SC-12, SC-28, SI-2, SI-7, SR-3, SR-4, and SR-11.

After onboarding, your system can import the component definition into its SSP and incorporate the provided control narratives directly into your system's own control documentation.

---

## Prerequisites

- Your repo must be in the GSA-TTS GitHub org

---

## Steps

### 1. Merge the Renovate onboarding PR

Renovate automatically creates an onboarding PR titled **"Enable centralized scanning service"** in every repo in the org.

- Review the PR — it adds a `renovate.json` that extends the org preset
- The PR body explains what Renovate will do once merged
- Merge it to activate dependency management for your repo

### 2. Review the initial "Pin Dependencies" PR

After merging the onboarding PR, Renovate creates a **Pin Dependencies** PR that converts mutable tag refs (e.g., `actions/checkout@v4`) to immutable SHA-pinned refs (e.g., `actions/checkout@<sha> # v4.x.x`) in your workflow files.

- Review the conversions — each line should show the correct SHA for the tagged version
- Confirm CI passes
- Merge

### 3. Delete `dependabot.yml`

Renovate replaces Dependabot version updates across all ecosystems. Remove `.github/dependabot.yml` entirely to avoid duplicate PRs.

### 4. Disable Dependabot security updates (NOT alerts)

In your repo's **Settings → Code security and analysis**, disable **Dependabot security updates** (the feature that creates automatic PRs for vulnerabilities). Renovate handles this with better grouping and scheduling.

**Do NOT disable Dependabot alerts.** The alerts populate your Security tab and feed into the centralized vulnerability SLA tracking.

### 5. Delete per-repo vulnerability SLA workflow (if present)

If your repo has a `vulnerability-sla-check.yml` or similar workflow, you can delete it. The org now provides centralized vulnerability SLA tracking that:

- Requires no per-repo configuration
- Creates a "Vulnerability SLA Tracker" issue in your repo with weekly status comments
- Tracks the GSA CIO 2100.1 / BOD 22-01 SLA timelines

### 6. Customize (optional)

Your repo's `renovate.json` can override any [Renovate setting](https://docs.renovatebot.com/config-overview/) from the org preset. Common customizations:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "local>GSA-TTS/scanning-service:default.json5"
  ],
  "schedule": ["before 7am on Monday"],
  "packageRules": [
    {
      "matchManagers": ["npm"],
      "matchUpdateTypes": ["patch"],
      "automerge": true
    }
  ]
}
```

- **Narrow the schedule** if you want updates only on certain days
- **Enable auto-merge** for low-risk updates if your test coverage warrants it (the org preset does NOT enable auto-merge centrally — teams opt in)
- **Ignore specific packages** if you need to pin to a particular version temporarily
- **Add custom grouping** for project-specific dependency sets

### 7. Add the dependency lint check to your CI (recommended)

Add the org's dependency lint as a PR check to catch any unpinned refs that slip in after onboarding. You have two options:

**Option A: Reusable workflow** — add a new workflow file:

```yaml
# .github/workflows/dependency-lint.yml
name: Dependency Lint
on: [pull_request]
jobs:
  lint:
    uses: GSA-TTS/scanning-service/.github/workflows/dependency-lint.yml@main
    with:
      fail-on-error: false  # advisory mode; set true to block PRs
```

**Option B: Composite action** — add a step to an existing workflow:

```yaml
- name: Dependency check
  uses: GSA-TTS/scanning-service/.github/actions/dependency-check@main
  with:
    fail-on-error: "false"
```

Both check for:
- Unpinned GitHub Actions `uses:` refs (via [zizmor](https://github.com/woodruffw/zizmor))
- Missing lockfiles (npm, pip, bundler, Go)
- Unpinned Docker `FROM` images

Results appear in the **Actions job summary** on each PR. Start with `fail-on-error: false` (advisory) and switch to `true` once your repo is clean.

> **Note:** The org also runs a centralized zizmor audit weekly across all repos — this PR check gives your team faster, per-PR feedback.

### 8. Add secret scanning to your CI (recommended)

Add the org's secret scanning as a PR check. Same two options as the dependency lint:

**Option A: Reusable workflow** — add a new workflow file:

```yaml
# .github/workflows/secret-scan.yml
name: Secret Scan
on: [pull_request]
jobs:
  scan:
    uses: GSA-TTS/scanning-service/.github/workflows/secret-scan.yml@main
    with:
      fail-on-error: false  # advisory mode; set true to block PRs
```

**Option B: Composite action** — add a step to an existing workflow:

```yaml
- name: Secret scan
  uses: GSA-TTS/scanning-service/.github/actions/secret-scan@main
  with:
    fail-on-error: "false"
```

Both use the org's centralized `.gitleaks.toml` config (fetched at runtime) to scan for leaked credentials, API keys, private keys, and cloud.gov service tokens. Results appear in the **Actions job summary** on each PR. Start with `fail-on-error: false` and switch to `true` once your repo is clean.

**Repo-local overrides:** If your repo has false positives specific to your codebase (e.g., BPMN element IDs, local-dev-only credentials, build artifacts), create a `.gitleaks.toml` in your repo root with just the additional allowlist entries:

```toml
[allowlist]
regexes = [
  '''CorrelationKey_[0-9a-z]+''',
]
paths = [
  '''build/dist/''',
]
```

The scanning tools **automatically merge** your repo's `paths` and `regexes` arrays into the org config at scan time. You do not need to reproduce the org-wide rules or allowlists — only add your repo-specific entries.

> **Note:** The org also runs a centralized gitleaks audit weekly across all repos — this PR check gives your team faster, per-PR feedback.

### 9. Handle exceptions

If your repo legitimately needs a mutable branch ref (e.g., `uses: org/action@main`):

1. Document the reason in your `renovate.json` via an `ignoreDeps` entry with a comment
2. Note the exception in your system's SSP under the relevant control (SI-7, SR-11)
3. Accept the risk — the dependency lint workflow will flag this as advisory

### 10. Add a pre-commit hook for secret scanning (recommended)

Catch secrets before they reach GitHub by running gitleaks locally on every commit.

First, [install gitleaks](https://github.com/gitleaks/gitleaks?tab=readme-ov-file#installing).  However, since Gitleaks does not yet support remote config files, you must download the org config to your project root:

```bash
curl -sfL "https://raw.githubusercontent.com/GSA-TTS/scanning-service/main/.gitleaks.toml" -o .gitleaks.toml
```

If using an altername name or location, you must use the `-c/--config` option for all subsequent pre-commit steps.

Next, set up a git pre-commit hook that points at the org config:

```bash
# .githooks/pre-commit
#!/usr/bin/env bash
gitleaks detect --staged 
```

Make it executable and activate:

```bash
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks
```

**With [mise](https://mise.jdx.dev/):** If you use mise for tool management, you can wire this up as a mise task and generate the hook:

```bash
# In your mise.toml, add a pre-commit task:
[tasks.pre-commit]
run = 'gitleaks detect --staged'

# Then generate the hook:
mise generate git-pre-commit --write --task=pre-commit
```

See [mise generate git-pre-commit](https://mise.jdx.dev/cli/generate/git-pre-commit.html) for details.

**With [pre-commit](https://pre-commit.com/):** You can also use the pre-commit framework:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.30.1
    hooks:
      - id: gitleaks
```

### 11. Verify SLA compliance

After onboarding, check that:

- A "Vulnerability SLA Tracker" issue appears in your repo (created automatically by the centralized workflow)
- Weekly status comments reflect your open Dependabot alerts
- Any overdue alerts are addressed within the SLA timeline

### 12. Import the OSCAL component definition (for SSP documentation)

If your system maintains an OSCAL-based SSP:

```bash
# Inside docker-trestle, from your system's docs/compliance directory:
copy-component -n org-dependency-management \
  -u https://raw.githubusercontent.com/GSA-TTS/scanning-service/refs/heads/main/docs/compliance/component-definitions/org-dependency-management/component-definition.json
```

Then add `org-dependency-management` to your `trestle-config.yaml` components list:

```yaml
components:
  - org-dependency-management
  # ... your other components
```

The next SSP assembly merges the component's control narratives alongside your system's own `### This System` sections.

### 13. Document controls in your SSP

For each of the 14 controls covered by this component, your SSP should describe how your system uses the scanning service. Example language:

> **CM-2 Baseline Configuration**
>
> This system uses the GSA-TTS centralized dependency management service, which establishes and enforces a documented, reviewable baseline for CI/CD pipeline dependencies. All dependency version changes go through SHA-pinned references and PR-based review. The system extends the org Renovate preset to maintain this baseline.
>
> **System-specific responsibilities:** The system team merges Renovate update PRs within the remediation SLA and documents any exceptions to the pinning standard.

---

## FAQ

**Q: What if Renovate and Dependabot create PRs for the same thing?**
A: Delete your `dependabot.yml` (Step 3) and disable Dependabot security updates (Step 4). This eliminates all Dependabot PRs. Dependabot *alerts* remain active — they're separate from PRs.

**Q: Will Renovate create a flood of PRs?**
A: No. The org preset limits to 5 concurrent PRs and 1 per hour. Related updates are grouped (e.g., all GitHub Actions patches in one PR). The schedule is weekday mornings only.

**Q: What about the 2-day cool-off period?**
A: `minimumReleaseAge: "2 days"` means Renovate waits 2 calendar days after an upstream release before creating a PR. This avoids retracted or quickly-patched releases. Security vulnerability PRs bypass this delay.

**Q: Can I enable auto-merge?**
A: Yes, in your repo's `renovate.json`. The org preset intentionally does NOT enable auto-merge centrally — each team decides based on their test coverage and risk tolerance.

**Q: What if a dependency is abandoned but has no replacement?**
A: Renovate's `abandonments:recommended` flags it. Your team should evaluate alternatives. If none exist and the component is essential, document the decision to maintain/fork it and accept the risk (SA-22b).

---

## Support

- **Usage or Compliance questions:** [#dev in Slack](https://gsa-tts.slack.com/archives/C02CD5VUQ)
- **Issues:** [GSA-TTS/scanning-service](https://github.com/GSA-TTS/scanning-service/issues)
