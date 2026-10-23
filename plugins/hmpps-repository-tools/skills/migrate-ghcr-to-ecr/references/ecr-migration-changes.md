# GHCR to ECR: required changes

Source: the changes made to the HMPPS templates when they moved to ECR
([hmpps-template-typescript](https://github.com/ministryofjustice/hmpps-template-typescript/compare/36866ab1a7b1748b0b21644d842348e437bd5b54...ec96a390b28cf738194bf0764eba7c1cf8cb1cf7),
[hmpps-template-kotlin](https://github.com/ministryofjustice/hmpps-template-kotlin/compare/c1c82736ec62b5fabc07cc7ef0f101e380959d53...fe1268f564f16907adac7769457a8a9928d25670)).
Where this document and the current template repositories disagree, the templates win; tell the developer.

## Prerequisites (repository level)

| Type     | Name                              |
| -------- | --------------------------------- |
| Variable | `CLOUD_PLATFORM_ECR_REGISTRY_URL` |
| Variable | `ECR_REGION`                      |
| Variable | `ECR_REPOSITORY`                  |
| Secret   | `ECR_ROLE_TO_ASSUME`              |

Only repository-level variables and secrets are checked. Organisation-level ones are implicit and are not checked.

## Shared workflow mapping

Shared workflows live in `ministryofjustice/hmpps-github-actions/.github/workflows/`. Keep the existing `@ref` and any trailing comment (for example `# WORKFLOW_VERSION`).

| Current                   | New                                                                  | Notes                                                       |
| ------------------------- | -------------------------------------------------------------------- | ----------------------------------------------------------- |
| `docker_build.yml`        | `docker_build_ecr.yml`                                               | Remove `docker_registry` and `registry_org`; add the secret |
| `docker_push.yml`         | `docker_push_ecr.yml`                                                | See "Separate build and push" below                         |
| `deploy_env.yml`          | `deploy_to_env.yml`                                                  | Wrapper around `deploy_env.yml`; needs `id-token: write`    |

`deploy_to_env.yml` is required, not optional. It wraps `deploy_env.yml` so existing callers keep working without `id-token`; the wrapper needs `id-token: write` for the `notify_on_deploy` job, which uses an octo-sts token to notify another workflow.

| `security_snyk_scan.yml`  | `security_snyk_scan_ecr.yml`                                         | Add `image_ref`, the secret and `id-token: write`           |

## Edits by workflow

### Build (`docker_build` to `docker_build_ecr`)

- Change the `uses:` file name.
- Delete `docker_registry: 'ghcr.io'` and `registry_org: ...` (the ECR workflow only retains them for compatibility).
- Keep all other inputs unchanged (`push`, `docker_multiplatform`, `additional_docker_tag`, `generate_sbom`, `attach_sbom_to_registry`, `sign_image`, `download_build_artifacts`, `file`, and so on).
- Add under the job:

  ```yaml
  secrets:
    ECR_ROLE_TO_ASSUME: ${{ secrets.ECR_ROLE_TO_ASSUME }}
  ```

- The calling job needs `id-token: write`. The templates use:

  ```yaml
  permissions:
    contents: read
    packages: write
    id-token: write
    attestations: write
  ```

### Separate build and push (`docker_push` to `docker_push_ecr`)

Some repositories build without pushing (`push: false`, `load: true`, `upload_image_artifact: true`), run tests such as end-to-end tests, then push the same image. For these:

- The build job moves to `docker_build_ecr.yml` as above, keeping `push: false`.
- The push job moves to `docker_push_ecr.yml`. Its inputs differ from `docker_push.yml`:
  - Remove `docker_registry` and `registry_org`.
  - Add `ecr_repository: ${{ vars.ECR_REPOSITORY }}` and `ecr_registry_url: ${{ vars.CLOUD_PLATFORM_ECR_REGISTRY_URL }}`. This mirrors how `docker_build_ecr.yml` calls `docker_push_ecr.yml` for multiplatform builds.
  - `aws_region` is optional and defaults to `eu-west-2`; add `aws_region: ${{ vars.ECR_REGION }}` only if the repository's `ECR_REGION` differs.
  - Pass the required secret: `ECR_ROLE_TO_ASSUME: ${{ secrets.ECR_ROLE_TO_ASSUME }}`.
  - Keep `app_version`, `tag_latest`, `additional_docker_tag` and `docker_multiplatform`.
- The push job needs `id-token: write`.
- Confirm the exact input names against the current `docker_push_ecr.yml` before editing; the file is the source of truth.

### Deploy (`deploy_env` to `deploy_to_env`)

For each deploy job (including commented-out preprod and prod jobs, so they stay correct when enabled):

- Change the `uses:` file name to `deploy_to_env.yml`.
- Add `helm_additional_args` to `with:`. If the job already sets `helm_additional_args`, append rather than overwrite:

  ```yaml
  helm_additional_args: '--set generic-service.image.repository=${{ vars.CLOUD_PLATFORM_ECR_REGISTRY_URL }}/${{ vars.ECR_REPOSITORY }}'
  ```

- Add job-level permissions (`deploy_to_env.yml` requires `id-token: write`):

  ```yaml
  permissions:
    contents: read
    id-token: write
  ```

- Keep `secrets: inherit`.

### Snyk scan (`security_snyk_scan` to `security_snyk_scan_ecr`)

- Change the `uses:` file name.
- Add `image_ref: '${{ vars.CLOUD_PLATFORM_ECR_REGISTRY_URL }}/${{ vars.ECR_REPOSITORY }}:latest'` to `with:`. Only relevant when `scan_type` is `image`.
- Add `id-token: write` to the job permissions.
- Add `ECR_ROLE_TO_ASSUME: ${{ secrets.ECR_ROLE_TO_ASSUME }}` to `secrets:`.

### Helm values

In `helm_deploy/<app>/values.yaml`, replace the hard-coded GHCR repository:

```yaml
image:
  repository: ecr_repository # override at deployment time
  tag: app_version # override at deployment time
```

The real repository is supplied at deploy time by `helm_additional_args`.

## Permissions and secrets: preserve existing behaviour

Granting `permissions:` on a job or workflow resets every permission not listed to `none`. A deployment that worked before can fail after the change if:

- the caller (job or top-level workflow) lacks `id-token: write` required by the called workflow;
- a job-level `permissions` block is added that omits something the job previously inherited from the top level (for example `actions: write`, `attestations: write`, `packages: write`);
- `secrets: inherit` is replaced by an explicit `secrets:` list that misses a secret, or vice versa.

For each changed job, work out the effective permissions before and after, and make sure nothing is lost. Add `id-token: write`; do not remove other permissions, even where the templates look tighter, as these have been kept for backwards compatibility.
