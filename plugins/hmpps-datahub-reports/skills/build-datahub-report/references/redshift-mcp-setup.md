# Redshift access setup (development, read-only)

Give agents direct query access to the DPR development Redshift cluster using the AWS Labs Redshift MCP server (`awslabs.redshift-mcp-server`), which talks to the Redshift Data API. This is far quicker than driving the AWS console query editor through a browser.

Rules for this setup:

- **Development account only.** Never configure the MCP for `test`, `preprod` or `prod` accounts.
- **Read-only.** Leave `ACCESS_MODE` as `read-only`. Never set `ACCESS_MODE=read-write` or `UNSAFE_SKIP_WRITE_CONFIRMATION`.
- The database user's privileges, not the MCP server, are the real security boundary. Never point the MCP at an admin or master user.

## Prerequisites

- AWS CLI v2 (`aws --version`)
- `uv` / `uvx` (`brew install uv`)
- Membership of the GitHub team that maps to the `reporting-operations` role in the DPR development account (ask the DataHub team if the account does not appear in the SSO portal)

## 1. AWS SSO profile

Sign in at `https://moj.awsapps.com/start`. Pick the `digital-prison-reporting-development` account; the role `mp-reporting-operations` is listed under it. The account ID is shown beside the account name.

Add a profile to `~/.aws/config` (do not remove existing profiles):

```ini
[profile dpr-development]
sso_start_url = https://moj.awsapps.com/start
sso_region = eu-west-2
sso_account_id = <digital-prison-reporting-development account ID>
sso_role_name = mp-reporting-operations
region = eu-west-2
```

Then ask the user to log in, as it is interactive:

```bash
aws sso login --profile dpr-development
AWS_PROFILE=dpr-development aws sts get-caller-identity --query Arn --output text
```

The ARN should contain `AWSReservedSSO_mp-reporting-operations`.

## 2. Check the cluster

```bash
export AWS_PROFILE=dpr-development
aws redshift describe-clusters --query 'Clusters[].[ClusterIdentifier,ClusterStatus,DBName]' --output text
aws redshift describe-scheduled-actions --query 'ScheduledActions[].[ScheduledActionName,Schedule,State]' --output text
```

The cluster `dpr-redshift-development` (database `datamart`) is paused out of hours by scheduled actions: resume at `cron(30 07 * * ? *)` and pause at `cron(30 20 * * ? *)` (UTC, daily). Queries only work while it is `available`. Do not resume it manually without asking the user, and do not change the schedule.

## 3. Register the MCP server

Add this entry under `mcpServers` in the Copilot CLI MCP config (`~/.copilot/mcp-config.json`). Keep a copy of the file first and preserve the other servers.

```json
"awslabs.redshift-mcp-server": {
  "type": "stdio",
  "command": "uvx",
  "args": ["awslabs.redshift-mcp-server@latest"],
  "env": {
    "AWS_PROFILE": "dpr-development",
    "AWS_REGION": "eu-west-2",
    "ACCESS_MODE": "read-only",
    "LOG_LEVEL": "WARNING"
  },
  "tools": ["*"]
}
```

Notes:

- The profile must be signed in whenever the MCP starts or its credentials expire. Re-run `aws sso login --profile dpr-development` and reload MCP if tools start returning authentication errors.
- Do not set `LOG_LEVEL=DEBUG`: statements, including their text, are written to the log.
- `MAX_RESULT_ROWS` (default 1000) caps result size. Keep the default.
- Reload MCP (or start a new session) after editing the config. Tools appear as `list_clusters`, `list_databases`, `list_schemas`, `list_tables`, `list_columns`, `execute_query` and `review_cluster`.

## 4. Verify

With the cluster `available`:

1. `list_clusters`: expect `dpr-redshift-development` as `provisioned`.
2. `list_databases` then `list_schemas` on database `datamart`.
3. `execute_query`: `SELECT current_user, current_database()`.

How the MCP authenticates: it uses the Redshift Data API as the signed-in IAM identity (`redshift:GetClusterCredentialsWithIAM`), not a named database user. If that is denied, or the IAM identity has no database privileges (for example `permission denied for schema`), do not work around it by retrieving the master password from Secrets Manager. Use one of the access options in the section below, only with the user's approval.

## Getting data access when the IAM user has no grants

The role may be able to see table metadata (`svv_all_tables`, `svv_all_columns`) but not read any data, because the datamart grants go to service users (such as `dpruser`) and Redshift roles, not to SSO roles. In order of preference:

1. **Ask for a grant.** Someone with admin rights grants an existing reader role to the IAM-mapped user, for example `GRANT ROLE prisons_reader TO "IAMR:AWSReservedSSO_mp-reporting-operations_<hash>"` (the user name is the `current_user` the MCP reports). The MCP then works as designed. Check the Flyway migrations in `digital-prison-reporting-transfer-component` for the current role names. Probation data uses a separate `probation_reader` role.
2. **Data API with a stored secret, with the user's explicit approval.** Secrets in AWS Secrets Manager hold database credentials. Pass the secret's ARN to `aws redshift-data execute-statement --secret-arn <arn>` so that the password never leaves AWS. Never read or print the secret value. Use `aws secretsmanager list-secrets`/`describe-secret` to find ARNs only. Run `SELECT` statements only, and keep results aggregate-first.
   - The secret's cluster must match `--cluster-identifier`. Secrets whose names mention SQL Workbench have been found pointing at a cluster that doesn't exist, or holding an out-of-date password (`password authentication failed`). Tell the user rather than trying other credentials.
   - The secret that the applications use (`dpr-redshift-secret-<env>`) was the one that worked. It is the master user, so only use it after the user has approved that specific secret.
3. **Draft SQL without running it**, from table and column metadata, and have it validated later.

A small shell helper makes the Data API easier to use: call `execute-statement`, poll `describe-statement` until `FINISHED` or `FAILED`, then read `get-statement-result`. Large views can take a minute or more, so allow time.

## Fallbacks

- **AWS CLI and Data API** (no MCP): `aws redshift-data execute-statement`, `describe-statement`, `get-statement-result` with `--cluster-identifier dpr-redshift-development --database datamart` and a database user or secret the user has explicitly approved.
- **AWS console query editor** driven through a browser session the user is already signed in to, only if the routes above are unavailable. Follow the user's browser-access safeguards: do not read cookies or tokens, and keep page reads targeted.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `Cluster is not available` or connection errors in the morning or evening | Cluster paused; check the schedule |
| `The SSO session associated with this profile has expired` | Run `aws sso login --profile dpr-development` and reload MCP |
| Tools missing from the session | MCP config edited after the session started; reload MCP |
| `AccessDenied` on `redshift-data:*` or `GetClusterCredentialsWithIAM` | Role lacks Data API permissions; ask the DataHub team |
| `permission denied for schema ...` | The IAM-mapped database user has no `USAGE` or `SELECT`; ask the DataHub team |
