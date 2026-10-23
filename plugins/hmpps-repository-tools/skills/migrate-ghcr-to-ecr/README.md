# migrate-ghcr-to-ecr

Helps migrate a repository's build, deploy and Snyk workflows from GitHub Container Registry (GHCR) to Amazon Elastic Container Registry (ECR). The agent makes the changes on a new branch and the developer reviews them.

## Why?

Public GitHub repositories push GHCR images that are public by default, so the Helm deployment process can pull them without authentication.

When a repository is switched to internal, its GHCR packages are expected to be made internal too (a manual process), so pulling the images for deployment needs authentication. The interim solution was to store a GitHub personal access token as a secret on the Cloud Platform namespace. This is not sustainable, because the tokens expire.

This migration supports the move to a curated public code presence.

## Moving to ECR

Cloud Platform offers ECR as a configurable module in its namespaces, and Kubernetes can already pull from it. Authentication is only needed when pushing the image.

Support for generating ECR credentials and storing them as repository variables and secrets is already built in. This skill moves a repository's workflows to use them.

## Before you start

The repository needs these set up (the skill checks for them and stops if they are missing):

- variables: `CLOUD_PLATFORM_ECR_REGISTRY_URL`, `ECR_REGION`, `ECR_REPOSITORY`
- secret: `ECR_ROLE_TO_ASSUME`
- the [GitHub CLI](https://cli.github.com) (`gh`) installed and authenticated
- Node.js, for the helper scripts

## What it does

1. Checks the prerequisites.
2. Pulls the default branch and creates `feat/migrate_build_deploy_to_ECR`.
3. Finds the build, push, deploy and Snyk workflows, and summarises them for you.
4. Switches them to the ECR shared workflows, adding the extra inputs, secrets and permissions needed, while keeping existing permissions working.
5. Updates the Helm image repository value.
6. Shows you the diff. It does not commit or push unless you ask.

The changes follow those made to
[hmpps-template-typescript](https://github.com/ministryofjustice/hmpps-template-typescript) and
[hmpps-template-kotlin](https://github.com/ministryofjustice/hmpps-template-kotlin). Repositories that differ from the templates are handled with your input.

## Usage

```bash
/hmpps-repository-tools:migrate-ghcr-to-ecr
```

Or ask Copilot in natural language, for example "migrate this repository from GHCR to ECR".

## Contents

| Path                                   | Purpose                                               |
| -------------------------------------- | ----------------------------------------------------- |
| `SKILL.md`                             | Instructions the agent follows                        |
| `references/ecr-migration-changes.md`  | Workflow mapping, inputs, permissions and secrets     |
| `scripts/preflight.mjs`                | Checks `gh`, authentication, ECR variables and secret |
| `scripts/prepare-branch.mjs`           | Pulls the default branch and creates the branch       |
| `scripts/find-workflows.mjs`           | Finds shared workflow calls and `ghcr.io` references  |

Scripts are plain Node.js with no dependencies. They print JSON to stdout and errors to stderr, and exit with code 1 on failure.
