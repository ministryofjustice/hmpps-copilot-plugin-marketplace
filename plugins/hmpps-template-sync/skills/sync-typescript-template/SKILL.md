---
name: sync-typescript-template
description: >
  Helps apply changes from the hmpps-template-typescript shared template to this repository.
  Use this skill when asked to: sync template changes, apply upstream template updates, check
  what template changes are available, or apply a specific template PR to this repo.
---

# HMPPS Template Sync Skill

This skill helps you apply changes from the [hmpps-template-typescript](https://github.com/ministryofjustice/hmpps-template-typescript) shared template to the current repository.

The template maintainers publish a changelog at `https://raw.githubusercontent.com/ministryofjustice/hmpps-template-typescript/main/CHANGELOG.md`. Each entry links to the GitHub PR that introduced the change — this skill fetches those diffs and applies them using `git apply --3way`.

Scripts for this skill are located at `scripts/`.

---

## Step 0: Identify and validate the target repository

Before listing or applying changes, determine the target repository:

1. Use the current working directory from the environment context as the target repo path. Resolve the git root with:
   ```bash
   git -C <cwd> rev-parse --show-toplevel
   ```
   Use the output as `REPO_PATH` for all subsequent script calls.

2. Check whether the repo looks like it is based on hmpps-template-typescript by verifying that `package.json` exists in the repo root. If it doesn't exist, warn the user:
   > "This directory doesn't appear to be an hmpps-template-typescript-based project — `package.json` was not found. Template changes may not apply correctly. Do you want to continue anyway?"

   If the user confirms, proceed. If the repo is clearly wrong (e.g. it's a plugin marketplace or documentation repo), stop and ask the user to navigate to the correct service repository first.

---

## Step 1: List available template changes

Run the bundled list-changes script and display its output directly to the user:

```bash
node scripts/list-changes.mjs
```

The output is a list ready to display - just present the list as provided. Each entry includes the date, title, PR number(s), PR URL(s), and a one-line description hint.

To show only a subset, use `--limit` and `--from`:

```bash
# Show first 20 entries
node scripts/list-changes.mjs --limit 20

# Show entries 21 onwards
node scripts/list-changes.mjs --from 21
```

Ask the user which change(s) they'd like to apply or inspect. They can specify by the PR number (e.g. "apply #679"), or by describing the change.

---

## Step 2: Show details for a specific change

If the user asks to see more details about an entry before applying it, run the get-change-details script and display its output:

```bash
node scripts/get-change-details.mjs <pr-number>
```

For example:

```bash
node scripts/get-change-details.mjs 679
```

This outputs the PR title, URL, merge date, full description, and a list of all changed files with additions/deletions counts.

---

## Step 3: Apply a selected change

Once the user has selected a change, run the apply-change script with the PR number and the repo path resolved in Step 0:

```bash
node scripts/apply-change.mjs <pr-number> --repo <REPO_PATH>
```

For example, to apply PR #679:

```bash
node scripts/apply-change.mjs 679 --repo /path/to/repo
```

The script outputs JSON with these fields:

- `appliedFiles` — files patched cleanly
- `conflictFiles` — files that need manual conflict resolution (contain `<<<<<<<` markers)
- `skippedFiles` — files where the patch couldn't be applied at all (file missing or too diverged)
- `skippedFileDetails` — array of `{ filename, status }` for each skipped file, where `status` is `"added"`, `"modified"`, `"removed"`, or `"renamed"` as reported by GitHub
- `repoPath` — the resolved path that was targeted
- `success` — `true` if at least a partial apply succeeded
- `gitOutput` — raw output from git (if any errors occurred)

---

## Step 4: Report the outcome

After running apply-change, summarise the result clearly:

**If all files applied cleanly (`conflictFiles` and `skippedFiles` are empty):**

- List the files that were changed
- Remind the user to review the diff (`git diff`) and run the project's tests before committing
- Suggest a commit message, e.g. `chore: apply template change from hmpps-template-typescript PR #679`

**If there are conflict files:**

- Name each conflicting file
- Offer to open and help resolve each conflict by reading the file and suggesting how to merge the changes
- After resolution, remind them to run `git add <file>` before committing

**If there are skipped files:**

- Name each skipped file and its `status` from `skippedFileDetails`
- For files with `status: "added"` — the file doesn't exist in this repo yet. Fetch the file's content directly from the template using:
  ```
  https://raw.githubusercontent.com/ministryofjustice/hmpps-template-typescript/main/<filename>
  ```
  Then create it in the repo at the same path using the `edit` tool, and note any project-specific values (e.g. app names, URLs) that may need adjusting.
- For files with `status: "modified"` or `"renamed"` — the file exists in the template but is missing or too diverged in this repo. Run `get-change-details.mjs` to understand what the change does, inspect the diff, and apply the relevant parts manually using the `edit` tool.
- For files with `status: "removed"` — the template deleted this file. Check if the file exists in the repo and offer to delete it, but confirm with the user first as they may have intentionally kept it.
- After handling all skipped files, remind the user to review changes with `git diff` before committing.

**If `success` is `false`:**

- Show the `gitOutput` to help diagnose the problem

---

## Notes and guidance

- **Always run the project's validation steps after applying changes.** For this repo: `npm run typecheck && npm run lint && npm run test`.
- **The patch may not apply perfectly.** This repo has diverged from the template. Conflicts and skips are normal — the skill is a starting point, not a guarantee of a clean apply.
- **Rate limiting:** The scripts use unauthenticated GitHub API calls. If you hit a rate limit (HTTP 403/429), wait a minute and try again, or set the `GITHUB_TOKEN` environment variable to authenticate.
- **Not all template changes are relevant.** Some changes (e.g. switching to Playwright) may not apply to a repo that has already made different choices. Always review the change description before applying.
