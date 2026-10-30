---
name: build-datahub-report
description: >
  Guides building a report or data product on the HMPPS DataHub (formerly Digital Prison Reporting,
  "DPR"): exploring the Redshift datamart, writing and testing the SQL, authoring a data product
  definition (DPD) JSON file in hmpps-dpr-data-product-definitions, validating it and raising a PR.
  Also sets up a read-only, development-only Redshift MCP server and AWS SSO profile. Use when asked
  to: create a DataHub or DPR report, write a data product definition, query the DPR Redshift
  datamart, set up a Redshift MCP server, or work out which datamart tables hold some data.
argument-hint: 'Describe the report: the question it answers, who uses it, and the DPS service whose data it needs'
---

# Build a DataHub report

DataHub (previously called Digital Prison Reporting, abbreviated DPR) lets services publish reports and dashboards over data held in a Redshift datamart. A report is a **data product definition (DPD)**: a JSON file holding the SQL, the columns, the filters, the access policy and the layout. Authoring a report means writing good SQL against the datamart and wrapping it in a valid DPD.

The terms "DataHub", "Digital Prison Reporting" and "DPR" are interchangeable.

## When to use this skill

- Creating or changing a DataHub / DPR report, dashboard or DPD
- Exploring what data exists in the DPR Redshift datamart
- Setting up access (AWS SSO profile, Redshift MCP server) to do either of the above

Do not use it for changes to the DataHub platform itself (the reporting API, the UI library or the infrastructure).

## Key facts

| Item | Value |
| --- | --- |
| Definitions repo | `ministryofjustice/hmpps-dpr-data-product-definitions` (private) |
| Schema and format docs | `ministryofjustice/hmpps-digital-prison-reporting-data-product-definitions-schema` (README describes every DPD section) |
| AWS account for development | `digital-prison-reporting-development`, role `mp-reporting-operations` |
| AWS SSO start URL | `https://moj.awsapps.com/start` (region `eu-west-2`) |
| Redshift cluster (development) | `dpr-redshift-development`, database `datamart`, region `eu-west-2` |
| Cluster availability | Paused out of hours: resumes `07:30 UTC`, pauses `20:30 UTC`, daily |

The development account is wiped regularly and the cluster is shared, so treat everything in it as disposable and never rely on it for anything other than development.

## Data sensitivity

The development datamart may hold data derived from real prisoner records. Treat it as sensitive.

- Explore with metadata queries and aggregates first (counts, distinct values, `LIMIT` small).
- Do not copy real names, prison numbers or other personal data into DPD files, tests, commit messages, PR descriptions or chat summaries. Use invented values in examples.
- Never print or store database passwords or credentials.

## Workflow

### 1. Set up access (once per machine)

Follow [references/redshift-mcp-setup.md](references/redshift-mcp-setup.md) to create the AWS SSO profile and register the **read-only, development-only** Redshift MCP server. Confirm the MCP tools are available in the session. If the session started before the MCP config changed, ask the user to reload MCP or restart the session.

Be aware that the IAM-mapped database user usually has **no grants** by default, because the datamart's schemas and views are granted to service users and Redshift roles (such as `prisons_reader`), not to individual SSO roles. If queries return `permission denied`, follow the access options in the setup reference. Do not assume the MCP alone will be enough.

Check the cluster is `available` before querying. If it is `paused`, check the schedule (above) and wait for it, or ask the user before resuming it. Do not resume it unprompted.

### 2. Clarify the report

Before touching SQL, agree with the user:

- The question the report answers, and the exact definition of each business term (for example "active", "current").
- How edge cases count, for example whether an expired or inactive record still counts as "present", and whether two related flags should be treated as one category. Ask rather than guess.
- The audience, and so the access role and whether rows are limited by the user's caseload (prison).
- The filters the user needs and the columns to show.
- Which DPS service owns the source data.

### 3. Get the definitions repo

Clone `ministryofjustice/hmpps-dpr-data-product-definitions` next to the user's other repositories if it is not already there, and pull the latest `main`. Read the repository README for the folder layout, then read two or three existing DPDs that are similar to the new one, preferring those with `"datasource": [{"id": "datamart", ...}]`. Existing files are the best guide to current conventions. Also read the schema repository README for the full list of DPD features.

Layout, per environment folder (`dev`, `test`, `preprod`, `prod`):

```
<env>/definitions/prisons/orphanage/   reports without a DPS service home
<env>/definitions/prisons/dps/<service>/   reports owned by a DPS service team
<env>/definitions/probation/           probation reports (extra LAO policy rules apply)
```

New work goes in `dev` first. Promotion to later environments is a separate, deliberate change.

### 4. Explore the datamart

Use the Redshift MCP tools (`list_clusters`, `list_databases`, `list_schemas`, `list_tables`, `list_columns`, `execute_query`) against `dpr-redshift-development`, database `datamart`.

- Source data is exposed per domain in the `prisons` schema, and in the `probation` schema as probation databases are onboarded. Qualify tables with the schema, for example `prisons.activities_waiting_list`, and expect `probation.`-prefixed tables for probation data. Prisons tables are named `<service>_<table>`. Shared reference data sits in `datamart` tables such as `datamart.prisoner_prisoner`. Look at existing DPDs for the joins they use, and list the schemas first rather than assuming which exist.
- Probation reports live under `definitions/probation/` and need an `lao` policy. Check the schema README before writing one.
- Find tables by listing the schema and filtering names on the service or concept, then read the columns of the candidates. The MCP's `list_tables` and `information_schema` only show objects the database user can read, while `svv_all_tables` and `svv_all_columns` also show external (Glue-backed) tables whose metadata is visible but whose data may not be. Query those views with `execute_query` to browse the catalogue. External tables are exposed in the `prisons` schema.
- Seeing a table's metadata does not mean you can read it. If `SELECT` fails with `permission denied for schema`, the database user lacks `USAGE`/`SELECT`: stop and use the access options in the setup reference (ask for a grant, or use a stored secret only with the user's explicit approval). Do not fetch master or other users' credentials on your own initiative to get round it.
- Reports read from two layers. The external schemas (`prisons`, `probation`) hold the ingested source tables. A domain layer of views sits on top in local schemas such as `datamart`, `establishment`, `staff`, `person` and `prisoner`. `information_schema.columns` returns nothing for these late-binding views, so use `svv_columns` for their columns and `pg_get_viewdef('<schema>.<view>'::regclass, true)` to read their SQL.
- Prefer the lightest source that answers the question. Domain views such as `datamart.prisoner_prisoner` can be heavy (many joins, historic bookings included). For "who is currently in a prison", join the source booking and offender tables and filter on the active booking flag and in/out status, as existing NOMIS-based reports do. Look up prison names from `datamart.establishment_establishment` (`id`, `name`).
- Check how a prison or caseload is identified in each table (commonly a `prison_code` or `establishment_code` column) as the policy needs it.
- Check status or date columns that decide whether a row is "active", and look at the distinct values with a grouped count.
- The MCP runs queries read-only and returns at most 1000 rows. If a query is refused or times out, make it more selective rather than raising limits.

### 5. Develop and test the SQL

Redshift SQL is PostgreSQL-like but not identical. Prefer plain joins, `NOT EXISTS` and `LEFT JOIN ... IS NULL` over exotic syntax. Test against the real tables and check:

- Row counts against expectations, using an aggregate query.
- Edge cases: prisoners with no related rows, multiple rows per prisoner (avoid duplicates in the output), nulls.
- That each column in the `SELECT` has a name matching a `schema` field in the DPD.

Constraints worth knowing about, because the platform changes your query:

- DataHub wraps the dataset query in an outer query to apply row-level policies (for example the caseload filter). Recursive CTEs and anything else that cannot sit inside a wrapping query will fail at report run time, even if they run fine directly. Keep queries wrap-friendly and avoid a trailing semicolon.
- Test in the cluster with the policy condition written out by hand (for example `WHERE prison_code = '<code>'`), since the MCP does not apply DataHub policies.

### 6. Write the DPD

Create the JSON file in the right folder, following an existing datamart-based DPD. The main parts are:

- `id`, `name`, `description`, `metadata` (version and tags)
- `datasource`: for the datamart use `[{"id": "datamart", "name": "datamart"}]`
- `policy`: access by role, usually `ROLE_PRISONS_REPORTING_USER`, plus a row-level caseload rule such as `"action": ["(prison_code='${caseload}')"]` with condition `"exists": ["${caseload}"]`. By default no rows are shown unless a policy permits them, and the policy column must exist in the dataset.
- `dataset`: the query, with `"datasource": "datamart"` and a `schema` listing each column's `name`, `type` and `display` name. Add small extra datasets for filter options if needed.
- `report`: each variant has `render: "HTML"`, a `dataset` reference (`"$ref:<dataset-id>"`), and a `specification` with `template` (usually `list`) and `field` entries. Each field has `name` (`"$ref:<column>"`), `display`, `visible`, `sortable`, `defaultsort`, optional `filter` and optional `formula` (for example `make_url(...)` to link to the prisoner profile).

Presentation conventions that users expect:

- Show a human-readable name (for example the prison name) instead of a code. Keep the code in the dataset, hidden (`"visible": "false"`), if a row-level policy needs it. Filter on the display column and supply its options from a small filter dataset.
- Show people as one `Lastname, Firstname` column. Source names are usually upper case, so wrap each part in `INITCAP()`. It copes with hyphens and apostrophes but not names like "McDonald". Mention that limitation to the user.
- Leave out columns that aren't relevant to the question (cell, for example).
- Calculated columns are best done in the dataset SQL with `COALESCE(count, 0)` over a grouped subquery joined once, not one correlated subquery per column. Use the `long` type for counts.
- A link column works well as a constant label in the SQL (`'Manage contacts' AS contacts_link`) with a `make_url(...)` formula that builds the URL from other columns. Service hosts differ by environment (`-dev`, `-preprod`, and none for prod). Hard-code the host for the environment folder the DPD lives in and update it when copying the DPD to the next environment, unless an existing DPD shows a working `${env}` pattern for that host.

Use fresh unique IDs. Keep IDs and names unique across the repository because the uniqueness check enforces it. See [references/dpd-authoring.md](references/dpd-authoring.md) for further detail and gotchas.

### 7. Validate

In the definitions repo:

```bash
npm ci --ignore-scripts
npm run validate      # schema compliance (downloads the schema, see .github/workflows/pr-raised.yml)
npm run uniqueness    # IDs unique within and across DPDs
```

`validate` needs the `SCHEMA_LOCATION` environment variable pointing at a downloaded copy of the schema; read `.github/workflows/pr-raised.yml` for the exact download URL and variable. Fix every reported problem.

### 8. Raise a PR and publish

- Commit on a branch and raise a PR to `main`. The PR workflow validates the DPDs. Merging needs an approving review from a code owner (the DataHub team) and the `json-validation` check to pass, and the rules apply to admins.
- Publishing to DynamoDB is done by the `Publish` GitHub Actions workflow. Run it manually (`workflow_dispatch`) from any branch, choosing an environment (`dev`, `test`, `preprod`, `prod`) and a subfolder (for example `orphanage`, `dps/activities` or `probation`). It also runs when a PR is closed, with the defaults (`dev`, `orphanage`).
- Each environment is a GitHub environment that needs approval from the DataHub team before the deploy job runs, and `preprod` and `prod` are restricted to specific branches. Check the environment's protection rules (`gh api repos/<repo>/environments/<env>`) and whether `prevent_self_review` is set, to know whether the person running the workflow can approve their own deployment or needs someone else.
- The workflow assumes an AWS role through GitHub OIDC, so the person publishing does not need personal AWS access for it.
- Publishing replaces **every** DPD under the chosen folder, taken from the checked-out branch, including other people's. Run it from a branch that is up to date with `main`, and be aware that publishing a stale branch can overwrite newer definitions of other reports in the same folder.
- Before every publish, including a republish after edits, run `git fetch origin` and check that the branch is not behind `origin/main` (`git rev-list --left-right --count HEAD...origin/main` should show `0` on the right). If it is behind, merge or rebase `main` first and re-validate.
- Push the branch, then run `gh workflow run publish.yml --ref <branch> -f deployEnv=dev -f deployFolder=<folder>`. If the environment needs approval and the user is allowed to approve their own deployment, approve it with `gh api -X POST repos/<repo>/actions/runs/<run-id>/pending_deployments -F "environment_ids[]=<id>" -f state=approved -f comment=...` (get the ID from `.../pending_deployments`). Then wait for the run to complete.
- Ask the user before triggering any publish, and never publish to `test`, `preprod` or `prod` without explicit instruction.
- Reports are then visible in the DataHub UI for that environment (for development, `https://digital-prison-reporting-mi-ui-dev.hmpps.service.justice.gov.uk/`) to users who sign in through HMPPS Auth and hold the role named in the policy. Check the report there and confirm the caseload filtering behaves as expected.

## Reporting back

Summarise: the SQL logic and business definitions assumed, the tables used, row-count checks done, files created, validation results, and anything the user must confirm. Do not include real personal data.
