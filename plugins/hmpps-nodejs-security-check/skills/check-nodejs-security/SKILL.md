

---
name: check-nodejs-security
description: >
  Audits a Node.js GitHub repository against HMPPS security standards.
  Use this skill when asked to: check security setup, audit the repo for security issues,
  verify security configuration, check if the project meets HMPPS security standards,
  or run a security compliance check.
---

# HMPPS Node.js Security Check Skill

This skill audits the current repository against HMPPS security standards for Node.js projects and offers to fix any issues found.

Scripts for this skill are located at `scripts/`.

---

## Step 0: Identify and validate the target repository

Before running checks, determine the target repository:

1. Use the current working directory from the environment context as the target repo path. Resolve the git root with:
   ```bash
   git -C <cwd> rev-parse --show-toplevel
   ```
   Use the output as `REPO_PATH` for all subsequent script calls.

2. Check whether the repo looks like a Node.js project by verifying that `package.json` exists in the repo root. If it doesn't exist, warn the user:
   > "This directory doesn't appear to be a Node.js project — `package.json` was not found. Security checks may not be meaningful here. Do you want to continue anyway?"

   If the user confirms, proceed. If the repo is clearly wrong (e.g. it's a plugin marketplace or documentation repo), stop and ask the user to navigate to the correct service repository first.

---

## Step 1: Run the security checks

Run the bundled check-security script with the resolved repo path:

```bash
node scripts/check-security.mjs --repo <REPO_PATH>
```

The script outputs a JSON array to stdout. Each entry has these fields:

- `id` — unique check identifier
- `label` — human-readable check name
- `status` — `"pass"`, `"fail"`, or `"warn"`
- `detail` — explanation of the result

The script exits with code `1` if any checks fail; this is expected — capture the output regardless of exit code.

---

## Step 2: Present the results

Display the results as a clear table or list. Use ✅ for `pass`, ❌ for `fail`, and ⚠️ for `warn`.

Example format:

```
Security audit results for /path/to/repo:

✅ .nvmrc file — Specifies Node.js version: 24
❌ package.json engines.npm — No engines.npm field in package.json.
✅ package.json engines.node — engines.node is set to ">=24.0.0".
✅ .npmrc file — .npmrc content matches the HMPPS template.
⚠️  GitHub Actions enabled — Could not check status (is gh CLI authenticated?).
❌ CodeQL actions scan workflow — security_codeql_actions_scan.yml not found in .github/workflows/.
✅ npm dependency scan workflow — security_npm_dependency.yml is present with a scheduled trigger.
❌ Veracode pipeline scan workflow — security_veracode_pipeline_scan.yml not found in .github/workflows/.
❌ Veracode policy scan workflow — security_veracode_policy_scan.yml not found in .github/workflows/.
✅ .gitignore excludes node_modules — node_modules is excluded in .gitignore.
✅ .gitignore excludes .env — .env files are excluded in .gitignore.

4 failures, 1 warning.
```

Summarise the total counts of passes, failures, and warnings.

---

## Step 3: Offer to fix failures

If there are any failures, offer to fix them automatically. Ask the user:

> "Would you like me to automatically fix all failures? I can fix everything except GitHub Actions enabled status, which requires a manual change in the repository settings."

If the user agrees, run the fix script:

```bash
node scripts/fix-security.mjs --repo <REPO_PATH>
```

The script outputs JSON with three fields:

- `fixed` — array of `{ id, action }` for checks that were successfully fixed
- `skipped` — array of `{ id, reason }` for checks that couldn't be auto-fixed (e.g. `actions-enabled`)
- `errors` — array of `{ id, message }` for any fixes that failed

Present a clear summary of what was fixed, what was skipped, and any errors.

To fix only specific issues, use `--checks` with a comma-separated list of check IDs:

```bash
node scripts/fix-security.mjs --repo <REPO_PATH> --checks nvmrc,engines-npm,engines-node
```

### What gets fixed automatically

| Check | Fix applied |
|-------|------------|
| `nvmrc` | Creates/overwrites `.nvmrc` with `24` |
| `engines-npm` | Updates `package.json` `engines.npm` to `>=11.10.0` |
| `engines-node` | Updates `package.json` `engines.node` to `>=24.0.0` |
| `npmrc` | Fetches canonical `.npmrc` from HMPPS template and writes it |
| `workflow-codeql` | Fetches `security_codeql_actions_scan.yml` from template and writes to `.github/workflows/` |
| `workflow-npm-dependency` | Fetches `security_npm_dependency.yml` from template |
| `workflow-veracode-pipeline` | Fetches `security_veracode_pipeline_scan.yml` from template |
| `workflow-veracode-policy` | Fetches `security_veracode_policy_scan.yml` from template |
| `gitignore-node-modules` | Appends `node_modules` to `.gitignore` |
| `gitignore-env` | Appends `.env` to `.gitignore` |

### What requires manual action

- **`actions-enabled`** — GitHub Actions must be enabled via the repository settings: **Settings > Actions > General > Allow all actions**.

### After workflow files are added

Note that the security workflow files use `${{ vars.SECURITY_ALERTS_SLACK_CHANNEL_ID || 'NO_SLACK' }}` for Slack notifications. Advise the user to set the `SECURITY_ALERTS_SLACK_CHANNEL_ID` repository variable in **Settings > Secrets and variables > Actions > Variables** if they want alerts sent to a Slack channel.

---

## Step 4: Re-run the check

After fixes are applied, re-run the security check to confirm all issues are resolved:

```bash
node scripts/check-security.mjs --repo <REPO_PATH>
```

Present the updated results. If everything passes, congratulate the user. If any issues remain (particularly `warn` items about GitHub Actions status that couldn't be verified automatically), explain what needs to be done manually.

---

## Notes and guidance

- **`warn` results** don't cause the script to exit with an error but should still be reviewed. They typically indicate checks that couldn't be completed automatically (e.g. `gh` CLI not authenticated).
- **GitHub Actions enabled status** requires the `gh` CLI to be authenticated. If it's not, the check is skipped with a warning. You can verify manually in the repository settings under **Actions > General**.
- **Veracode workflows** require Veracode credentials to be configured as GitHub repository secrets. The workflow files can be added without these secrets, but the scans won't run until the secrets are set up. Advise the user to contact their security team if needed.
- **Rate limiting:** The script makes unauthenticated GitHub API calls. If you hit a rate limit (HTTP 403/429), wait a minute and retry, or set the `GITHUB_TOKEN` environment variable.
- **Committing changes:** After fixes are applied, remind the user to review the diff with `git diff` and commit with an appropriate message, for example:
  ```
  chore: apply HMPPS security configuration standards
  ```
