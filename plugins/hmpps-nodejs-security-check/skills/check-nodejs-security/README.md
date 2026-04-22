# Security checks reference

This document lists all checks performed by the `check-nodejs-security` skill. Use it as a reference when reviewing a project manually or understanding what the automated tooling validates.

Run the checks against a repository with:

```bash
node scripts/check-security.mjs --repo <path>
```

Fix all failures automatically with:

```bash
node scripts/fix-security.mjs --repo <path>
```

To fix specific checks only, pass a comma-separated list of check IDs:

```bash
node scripts/fix-security.mjs --repo <path> --checks nvmrc,engines-npm
```

---

## Categories

- [Node.js version management](#nodejs-version-management)
- [Package management](#package-management)
- [Docker](#docker)
- [GitHub configuration](#github-configuration)
- [Security scanning workflows](#security-scanning-workflows)
- [Source control hygiene](#source-control-hygiene)

---

## Node.js version management

### `.nvmrc` file

| Field | Value |
|-------|-------|
| **Check ID** | `nvmrc` |
| **Severity** | Warning |
| **Auto-fix available** | ✅ Yes |

**Description:** Checks that a `.nvmrc` file exists in the repository root and that it specifies Node.js 24.

**Why it matters:** `.nvmrc` tells developer tooling (nvm, Volta, CI) which Node.js version to use. Without it, developers may run the project on mismatched versions, causing inconsistent behaviour. Pinning to Node.js 24 ensures everyone uses the same current LTS release.

**How to validate manually:**
1. Check the repository root for a `.nvmrc` file
2. Open it — it should contain `24` (or `v24.x.x`, `lts/jod`)
3. Verify your local Node.js version matches: `node --version`

---

### `package.json` engines.node

| Field | Value |
|-------|-------|
| **Check ID** | `engines-node` |
| **Severity** | Warning |
| **Auto-fix available** | ✅ Yes |

**Description:** Checks that `package.json` has an `engines.node` field targeting Node.js 24 (e.g. `">=24.0.0"`).

**Why it matters:** The `engines` field in `package.json` is the formal declaration of supported runtimes. Combined with `engine-strict = true` in `.npmrc`, npm will refuse to install dependencies if the wrong Node.js version is used. This prevents silent runtime failures caused by version mismatches.

**How to validate manually:**
1. Open `package.json`
2. Check that an `"engines"` block exists with a `"node"` entry targeting version 24, for example:
   ```json
   "engines": {
     "node": ">=24.0.0"
   }
   ```

---

## Package management

### `package.json` engines.npm

| Field | Value |
|-------|-------|
| **Check ID** | `engines-npm` |
| **Severity** | Critical |
| **Auto-fix available** | ✅ Yes |

**Description:** Checks that `package.json` has an `engines.npm` field requiring npm 11.10 or higher (e.g. `">=11.10.0"`).

**Why it matters:** npm 11.10 introduced important improvements to the `min-release-age` feature used in our `.npmrc`. Using an older version of npm may silently ignore that setting, allowing newly-published packages to be installed before they've had time to be scrutinised for supply-chain attacks.

**How to validate manually:**
1. Open `package.json`
2. Check that an `"engines"` block exists with an `"npm"` entry of `>=11.10.0` or higher:
   ```json
   "engines": {
     "npm": ">=11.10.0"
   }
   ```
3. Verify your local npm version: `npm --version`

---

### `.npmrc` file

| Field | Value |
|-------|-------|
| **Check ID** | `npmrc` |
| **Severity** | Critical |
| **Auto-fix available** | ✅ Yes |

**Description:** Checks that `.npmrc` exists in the repository root and that its content matches the [canonical HMPPS template](https://github.com/ministryofjustice/hmpps-template-typescript/blob/main/.npmrc).

**Why it matters:** The HMPPS `.npmrc` enables several supply-chain security controls:
- `ignore-scripts = true` — prevents install-time scripts from running (a common malware vector)
- `save-exact = true` — pins exact dependency versions to avoid unexpected updates
- `engine-strict = true` — enforces the Node.js and npm version requirements above
- `min-release-age = 7` — prevents installing packages published in the last 7 days, giving time for malicious packages to be discovered
- `allow-git = none` — blocks git dependencies, which bypass registry security checks

**How to validate manually:**
1. Open `.npmrc` in the repository root
2. Compare its contents to the [template `.npmrc`](https://github.com/ministryofjustice/hmpps-template-typescript/blob/main/.npmrc)
3. Ensure all settings are present and match

---

## Docker

### Dockerfile copies .npmrc

| Field | Value |
|-------|-------|
| **Check ID** | `dockerfile-npmrc` |
| **Severity** | Critical |
| **Auto-fix available** | ❌ No — requires manual Dockerfile edit |

**Description:** Finds all Dockerfiles in the repository root (`Dockerfile`, `Dockerfile.*`, `*.dockerfile`) and checks that any which run npm (`npm install`, `npm ci`, `npm run`) also copy `.npmrc` into the build stage.

**Why it matters:** The `.npmrc` security settings — `ignore-scripts`, `min-release-age`, `allow-git = none`, and others — must be present when `npm install` runs inside the Docker build. Without `.npmrc` in the container build context, dependencies are installed without any of those restrictions, completely bypassing your supply-chain security controls. Note that `.npmrc` only needs to be present in the build stage; it should **not** be copied into the final production image.

**How to validate manually:**
1. Open each `Dockerfile` in the repository
2. Find the stage that runs `npm install`, `npm ci`, or `npm run`
3. Confirm that the `COPY` instruction before the npm step includes `.npmrc`, for example:
   ```dockerfile
   COPY package*.json .npmrc ./
   RUN npm ci
   ```
4. Confirm `.npmrc` is **not** present in the final production stage (it contains no secrets, but it's good hygiene to keep the production image minimal)

**To fix manually:** In the Dockerfile, add `.npmrc` to the `COPY` instruction in your build stage, before the line that runs npm:

```dockerfile
# Before (missing .npmrc):
COPY package*.json ./
RUN npm ci --omit=dev

# After (correct):
COPY package*.json .npmrc ./
RUN npm ci --omit=dev
```

---

## GitHub configuration

### GitHub Actions enabled

| Field | Value |
|-------|-------|
| **Check ID** | `actions-enabled` |
| **Severity** | Critical |
| **Auto-fix available** | ❌ No — requires manual action in repository settings |

**Description:** Checks that GitHub Actions are enabled for the repository.

**Why it matters:** All security scanning workflows depend on GitHub Actions. If Actions are disabled, no scheduled security scans will run, leaving the repository unmonitored for vulnerabilities.

**How to validate manually:**
1. Go to the repository on GitHub
2. Navigate to **Settings > Actions > General**
3. Confirm that actions are set to **Allow all actions** or at minimum allow actions from trusted sources

**To fix manually:** In **Settings > Actions > General**, select **Allow all actions and reusable workflows** (or your organisation's approved policy) and save.

---

## Security scanning workflows

All four workflows below follow the same pattern: they run on a `schedule` (weekdays at at random time, or Mondays for the policy scan) and delegate to reusable workflows in [hmpps-github-actions](https://github.com/ministryofjustice/hmpps-github-actions). They optionally post alerts to a Slack channel via the `SECURITY_ALERTS_SLACK_CHANNEL_ID` repository variable.

### CodeQL actions scan workflow

| Field | Value |
|-------|-------|
| **Check ID** | `workflow-codeql` |
| **Severity** | Critical |
| **Auto-fix available** | ✅ Yes |

**Description:** Checks that `.github/workflows/security_codeql_actions_scan.yml` exists, references the `hmpps-github-actions` CodeQL reusable workflow, and has a scheduled cron trigger.

**Why it matters:** CodeQL scans GitHub Actions workflow files for security misconfigurations such as script injection vulnerabilities (e.g. unquoted `github.event` inputs used in `run:` steps). These vulnerabilities can allow attackers to execute arbitrary code in your CI pipeline.

**How to validate manually:**
1. Check that `.github/workflows/security_codeql_actions_scan.yml` exists
2. Open the file and confirm it contains a `schedule:` block with a `cron:` entry
3. Confirm it uses `ministryofjustice/hmpps-github-actions/.github/workflows/security_codeql_actions.yml@v2`
4. Check the workflow has run recently: go to **Actions** in the repository and look for "Security CodeQL actions scan"

---

### npm dependency scan workflow

| Field | Value |
|-------|-------|
| **Check ID** | `workflow-npm-dependency` |
| **Severity** | Critical |
| **Auto-fix available** | ✅ Yes |

**Description:** Checks that `.github/workflows/security_npm_dependency.yml` exists, references the `hmpps-github-actions` npm dependency reusable workflow, and has a scheduled cron trigger.

**Why it matters:** Runs `npm audit` on a schedule to surface known vulnerabilities in npm dependencies. Without this workflow, newly disclosed vulnerabilities in your dependencies won't be caught automatically.

**How to validate manually:**
1. Check that `.github/workflows/security_npm_dependency.yml` exists
2. Open the file and confirm it contains a `schedule:` block with a `cron:` entry
3. Confirm it uses `ministryofjustice/hmpps-github-actions/.github/workflows/security_npm_dependency.yml@v2`
4. Check the workflow has run recently under **Actions** in the repository

---

### Veracode pipeline scan workflow

| Field | Value |
|-------|-------|
| **Check ID** | `workflow-veracode-pipeline` |
| **Severity** | Warning |
| **Auto-fix available** | ✅ Yes |

**Description:** Checks that `.github/workflows/security_veracode_pipeline_scan.yml` exists, references the `hmpps-github-actions` Veracode pipeline scan reusable workflow, and has a scheduled cron trigger.

**Why it matters:** Veracode performs static application security testing (SAST) to identify security flaws in your application code, such as SQL injection, XSS, and insecure cryptography. The pipeline scan runs quickly and is suitable for regular scheduled scanning.

**How to validate manually:**
1. Check that `.github/workflows/security_veracode_pipeline_scan.yml` exists
2. Open the file and confirm it contains a `schedule:` block with a `cron:` entry
3. Confirm it uses `ministryofjustice/hmpps-github-actions/.github/workflows/security_veracode_pipeline_scan.yml@v2`
4. Confirm Veracode credentials are configured as repository secrets (contact your security team if unsure)

---

### Veracode policy scan workflow

| Field | Value |
|-------|-------|
| **Check ID** | `workflow-veracode-policy` |
| **Severity** | Warning |
| **Auto-fix available** | ✅ Yes |

**Description:** Checks that `.github/workflows/security_veracode_policy_scan.yml` exists, references the `hmpps-github-actions` Veracode policy scan reusable workflow, and has a scheduled cron trigger (Mondays).

**Why it matters:** The Veracode policy scan is a more thorough SAST scan that runs against the full Veracode security policy. It catches a broader range of issues than the pipeline scan and is required for HMPPS compliance. Running it weekly ensures findings are reviewed regularly.

**How to validate manually:**
1. Check that `.github/workflows/security_veracode_policy_scan.yml` exists
2. Open the file and confirm it contains a `schedule:` block with a `cron:` entry
3. Confirm it uses `ministryofjustice/hmpps-github-actions/.github/workflows/security_veracode_policy_scan.yml@v2`
4. Confirm Veracode credentials are configured as repository secrets (contact your security team if unsure)

---

## Source control hygiene

### `.gitignore` excludes node_modules

| Field | Value |
|-------|-------|
| **Check ID** | `gitignore-node-modules` |
| **Severity** | Warning |
| **Auto-fix available** | ✅ Yes |

**Description:** Checks that `.gitignore` contains an entry for `node_modules`.

**Why it matters:** Accidentally committing `node_modules` bloats the repository, slows down clones, and can expose lockfile inconsistencies. In rare cases, a compromised or manipulated `node_modules` directory committed to the repo could introduce malicious code that bypasses the registry security controls in `.npmrc`.

**How to validate manually:**
1. Open `.gitignore` in the repository root
2. Check that `node_modules` or `node_modules/` appears as a line entry

---

### `.gitignore` excludes .env

| Field | Value |
|-------|-------|
| **Check ID** | `gitignore-env` |
| **Severity** | Critical |
| **Auto-fix available** | ✅ Yes |

**Description:** Checks that `.gitignore` contains an entry for `.env` (or `.env*` / `*.env`).

**Why it matters:** `.env` files commonly contain secrets such as API keys, database passwords, and OAuth credentials. Committing them — even briefly — can expose sensitive credentials, especially in public repositories. Once committed, secrets are difficult to fully remove from git history.

**How to validate manually:**
1. Open `.gitignore` in the repository root
2. Check that `.env`, `.env*`, or `*.env` appears as a line entry
3. Confirm no `.env` files are tracked: `git ls-files | grep '\.env'` should return nothing
