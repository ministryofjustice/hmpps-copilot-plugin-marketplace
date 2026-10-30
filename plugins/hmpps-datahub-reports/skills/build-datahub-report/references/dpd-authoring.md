# DPD authoring notes

Supplements the schema README at `ministryofjustice/hmpps-digital-prison-reporting-data-product-definitions-schema`, which is the reference for every DPD section. These notes capture how the pieces fit together and the mistakes that cost the most time.

## How reports reach users

1. DPD JSON files live in `hmpps-dpr-data-product-definitions`, in a folder per environment (`dev`, `test`, `preprod`, `prod`).
2. The `Publish` workflow (manually triggered, taking `deployEnv` and `deployFolder`) writes the DPDs in a folder to the DynamoDB table `dpr-data-product-definition` for that environment. The folder path becomes the definition's `category`, for example `definitions/prisons/orphanage`.
3. The DataHub reporting API reads definitions by category and runs the dataset SQL. A UI service, either the shared DataHub UI or a team's own UI using the DataHub frontend library, shows the reports for its configured path.
4. The API applies policies: the role check decides whether a user can run the report, and row-level policies are added to the query so users only see rows for their caseload.

Consequences:

- Reports in `orphanage` appear in the shared DataHub UI. Reports in a team folder (`dps/<service>`) appear only in a UI configured with that path.
- A DPD is only available in an environment if it is in that environment's folder **and** has been published there.
- `dev` is for drafts and changes often. Teams usually build in `dev`, check in `test`, then promote.

## Datasources

| `datasource` | Meaning |
| --- | --- |
| `datamart` | The Redshift datamart. Use Redshift (PostgreSQL-like) SQL. Preferred for new reports. |
| `nomis` and similar federated sources | Passthrough queries to Oracle sources, used by migrated legacy reports. |

For a datamart report, set the top-level datasource to `{"id": "datamart", "name": "datamart"}` and set `"datasource": "datamart"` on each dataset.

## Datasets

- A **standard dataset** returns the rows shown in the report. Each column needs a `schema` entry with `name` (matching the SQL column name exactly, lower-case for Redshift), `type` (`string`, `date`, `datetime`, `int`, `long`, `double`, `boolean`, `time`; check the schema JSON for the current list) and a `display` label.
- A **filter option dataset** supplies options for a `select`, `radio`, `multiselect` or `autocomplete` filter. It is referenced from the field's `filter.dynamicoptions`.
- A **summary dataset** aggregates the standard dataset's result. It must use the `${tableId}` token for the standard dataset's result table.
- Datasets in `report` entries are referenced with `"$ref:<dataset-id>"`, and fields with `"$ref:<column-name>"`.

## Policies

- `type: access` with a role match controls who can run the report. Reports with no permitting policy return no rows.
- `type: row-level` adds a filter condition to the query. Common forms are `(prison_code='${caseload}')` (the user's active caseload) and `prison_code in (${caseloads})` (all of the user's caseloads). The named column must exist in the dataset's output.
- Probation DPDs need an `lao` policy as well (see the schema README).

## Filters

A field's `filter` has a `type` (`select`, `radio`, `multiselect`, `date`, `daterange`, `text`, `autocomplete`, `caseloads`, `granulardaterange`), and optionally `mandatory`, `pattern`, `default`, `staticoptions` or `dynamicoptions`.

- `caseloads` renders the user's caseloads as a multiselect and defaults to all of them. Use it for a "prison" filter limited to the user's access.
- Filter on columns in the dataset; filters are applied as extra SQL conditions on the dataset's result.

## Formulae

`formula` transforms a value for display, for example `format_date(${date_col}, 'dd/MM/yyyy')` or `make_url('https://prisoner${env}.digital.prison.service.justice.gov.uk/prisoner/${prisoner_number}', ${prisoner_number}, TRUE)`. Check the schema README for the supported functions and tokens.

## Publishing details

- The workflow finds every `*.json` under `dpd/<env>/definitions/prisons/<deployFolder>/` (for `probation`, `dpd/<env>/definitions/probation/`) and writes one DynamoDB item per file. The partition key is the DPD `id` and the sort key is `category`, which is `definitions/prisons/<deployFolder>` (or `definitions/probation`). The same `id` under a different category is stored as a separate item.
- Because the category comes from the `deployFolder` input, publishing a nested folder such as `orphanage/<name>` stores the DPD under a different category from `orphanage`, and the shared UI would not list it. Confirm how the category is matched before relying on nested draft folders.
- Publishing is by folder, not by file, so there is no way to publish a single DPD without also republishing its neighbours from the same branch.

## Gotchas

- The platform wraps dataset SQL in an outer query for security filtering. Recursive CTEs and a trailing semicolon cause failures at run time even when the SQL runs directly in Redshift.
- Query engine limits only show up by running the report. Test through the UI in `dev` before promoting.
- A sectioned report (`list-section`) can be downloaded; row ordering in the export differs from the on-screen order. Do not redesign a report because the test UI lacks a download button.
- Do not hard-code environment-specific values in SQL. Use `${env}` in URLs and rely on the caseload policy rather than hard-coded prison codes.
- Real data may appear in test and sample output. Keep personal data out of the repository.
- NOMIS-sourced tables often hold flags as `'Y'`/`'N'` strings and names in upper case, while newer service tables use real booleans. Check column types before writing conditions.
- Declare count columns as `long` in the dataset `schema`.
- A filter's field must be a visible report field, so filter on the display column (such as a prison name) rather than a hidden code column.
- Keep DPD IDs unique; `npm run uniqueness` fails on duplicates.
- If scheduled generation is needed, a dataset can carry a `schedule` (cron). Check the schema README and the existing scheduled DPDs first; scheduling is a platform feature that is still evolving.

## Test data

The repository includes a workflow and a Kotlin script (`.github/scripts/GenerateTestData.main.kts`, see `.github/scripts/LOCAL_RUN.md`) that generate test data and matching test DPDs for DPD definitions, for loading into a test Redshift. Use it when a DPD needs synthetic data to test against.
