---
name: migrate-ghcr-to-ecr
description: >
  Migrates an HMPPS repository's GitHub Actions build, push, deploy and Snyk scan workflows from
  GHCR (ghcr.io) to AWS ECR, keeping permissions and secrets working. Use when asked to: migrate
  to ECR, move from GHCR to ECR, make a repository internal, or update docker_build, docker_push,
  deploy_env or security_snyk_scan workflows to their ECR equivalents.
---

# Migrate a repository from GHCR to ECR

Your goal is to update the current repository's GitHub Actions workflows (and Helm values) so images are built, pushed, deployed and scanned using ECR instead of GHCR, on a new branch, without breaking permissions or secrets. The developer makes the final decision on every ambiguous change.

## When to use this skill

Trigger phrases: "migrate to ECR", "move from GHCR to ECR", "switch docker_build to docker_build_ecr", "make this repo internal", "update the Snyk scan for ECR".

## Guardrails

- Run from the root of a clone of the repository being migrated.
- Do not edit workflows that do not call the shared workflows listed in [references/ecr-migration-changes.md](references/ecr-migration-changes.md).
- Do not commit, push or open a pull request unless the developer explicitly asks.
- Do not guess. If a workflow does not match the patterns in the reference, show it to the developer and ask.
- Never remove existing permissions or secrets; only add what ECR needs.
- Make the minimum edit to each file; preserve comments, formatting and the `@ref` on `uses:` lines.

## Steps

Track progress with this checklist:

- [ ] 1. Preflight
- [ ] 2. Prepare branch
- [ ] 3. Discover and summarise
- [ ] 4. Apply changes
- [ ] 5. Validate
- [ ] 6. Review with developer

### 1. Preflight

Run `node scripts/preflight.mjs` (path relative to this skill's folder). It checks that `gh` is installed and authenticated, and that the ECR repository variables and secret exist.

If it exits non-zero, stop. Report each failed check and tell the developer the ECR variables and secret must be provisioned first (the Cloud Platform ECR module). Do not continue.

Only repository-level variables and secrets are checked; organisation-level ones are implicit. If only the secret check failed because `gh` lacked permission to list secrets, ask the developer to confirm `ECR_ROLE_TO_ASSUME` exists, then continue.

### 2. Prepare branch

Run `node scripts/prepare-branch.mjs`. It pulls the default branch and creates `feat/migrate_build_deploy_to_ECR`. If it fails (uncommitted changes, branch already exists), report why and ask the developer how to proceed.

### 3. Discover and summarise

Run `node scripts/find-workflows.mjs`. It returns every call to the relevant shared workflows (including commented-out ones) and every remaining `ghcr.io` reference.

Read each workflow file it identifies in full, then present a summary **before editing**:

- which files are build, push, deploy and Snyk workflows;
- whether build and push are combined (`docker_build` with `push: true`) or separate (a `docker_push` job after tests);
- whether the repository uses multiplatform builds, matrices, or reusable local workflows that wrap the shared ones;
- each `ghcr.io` reference and whether it is in scope (for example `helm_deploy/*/values.yaml` is; documentation is not);
- anything unusual that does not fit the reference.

Then **stop and wait for the developer's explicit confirmation**. Do not edit any file until they reply, even when the plan looks straightforward and matches the reference. Resolve any ambiguity in that conversation.

### 4. Apply changes

Follow [references/ecr-migration-changes.md](references/ecr-migration-changes.md) for the workflow mapping, inputs, secrets and permissions. For every changed job:

1. Work out the effective permissions and secrets **before** the change.
2. Make the edits.
3. Confirm the effective permissions and secrets **after** are a superset, including `id-token: write` where ECR needs it.

Look for jobs that depend on the build output or registry details, such as other jobs using `ghcr.io` image names, `docker pull`, `needs.<job>.outputs`, or custom Helm arguments, and report them rather than silently changing them.

### 5. Validate

- Run `git diff` and check every `uses:` points at an existing shared workflow file.
- Check the edited YAML is valid: run `actionlint` if installed, otherwise re-read each edited file for indentation and syntax errors. State plainly in the final report which of these you did; never say `actionlint` passed unless you ran it.
- Re-run `node scripts/find-workflows.mjs` and confirm no in-scope `ghcr.io` references remain, or explain each one left.
- Flag any Dockerfile `FROM ghcr.io/...` base image to the developer. Leave it unchanged (it is not where this app's image is pushed), but note that the build will need authentication to pull it if that package is ever made internal.

### 6. Review with developer

Show the diff summary file by file. List every judgement call you made and every item you left unchanged and why. Remind the developer that the pipeline can only be proven by running it on the branch (for example via a pull request), and offer to commit and push, but wait to be asked.

## Gotchas

- Always switch `deploy_env.yml` to `deploy_to_env.yml`. It is a wrapper that keeps `deploy_env.yml` backwards compatible, and requires `id-token: write` on the calling job for its `notify_on_deploy` job (octo-sts).
- A called workflow cannot hold more permissions than its caller. If a reusable workflow in the same repository wraps the shared one (for example `deploy_to_env.yml`), `id-token: write` must be granted all the way up the chain, including a top-level `permissions` block if the entry-point workflow has one. This top-level grant is broader than ideal but is necessary; mention the trade-off rather than treating it as unnecessary.
- Adding a job-level `permissions` block resets all unlisted permissions to `none`. This is the most common cause of a previously working deployment failing.
- Commented-out deploy jobs (preprod, prod) still need updating, so that enabling them later does not reintroduce GHCR.
- Separate build/push pipelines use `docker_push_ecr.yml`, which has different inputs from `docker_push.yml`. Verify against the live file.
