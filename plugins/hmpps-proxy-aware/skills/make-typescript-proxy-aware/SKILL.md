---
name: make-typescript-proxy-aware
description: >
  Helps TypeScript developers make applications proxy-aware in line with HMPPS patterns.
  Use this skill when asked to: configure proxy support, fix socket hang up errors after
  egress proxy rollout, migrate superagent or agentkeepalive clients, adopt hmpps-rest-client,
  hmpps-auth-clients, hmpps-monitoring, or hmpps-azure-telemetry, and apply Helm proxy env vars.
---

# Make TypeScript Proxy-Aware

This skill helps you make HMPPS TypeScript applications proxy-aware for Cloud Platform egress controls.

It focuses on proven HMPPS patterns from:

- `hmpps-template-typescript`
- `hmpps-typescript-lib`
- `hmpps-tech-docs/src/content/how-to-guides/retrofitting-egress-controls-with-envoy-proxy.md`

Use this skill when a service needs to route outbound HTTPS traffic through an Envoy forward proxy, especially when errors like `socket hang up` appear after proxy rollout.

---

## Outcome

By the end of this skill, the target app should:

- Use proxy-aware outbound HTTP client patterns
- Use current HMPPS shared libraries where practical
- Have proxy environment variables configured in Helm values
- Keep behavioural changes low-risk for drifted or legacy services
- Pass validation checks after migration

---

## Step 0: Identify and validate the target repository

1. Resolve the target repo root from the current working directory:
   ```bash
   git -C <cwd> rev-parse --show-toplevel
   ```

2. Confirm this looks like a TypeScript service by checking for `package.json`.

3. Confirm it looks like a deployable HMPPS app (for example `helm_deploy/` exists). If not, warn the user and ask whether to continue.

4. Check whether the namespace has the Envoy proxy secret wired from Cloud Platform egress controls. If missing, explain that app-level changes alone are not enough.

---

## Step 1: Assess current proxy readiness

Search for patterns that usually break with proxy rollout:

1. Direct `superagent` usage
2. `agentkeepalive` usage (`Agent`, `HttpsAgent`)
3. Custom HTTP clients that do not read proxy env vars
4. Manual auth token request flows that bypass standard clients
5. Token verification modules (for example `tokenVerification.ts`) implemented directly with `hmpps-rest-client` or custom REST wrappers instead of `hmpps-auth-clients` verification client
6. Legacy health check HTTP stacks
7. Legacy App Insights setup instead of `hmpps-azure-telemetry`
8. Telemetry setup that imports logger before telemetry initialisation (PR #778 pattern)
9. Legacy auth-oriented API clients built on shared base classes (for example `abstractHmppsRestClient`) such as `manageUsersApiClient` or `AuthenticationClient` that should map to `@ministryofjustice/hmpps-auth-clients`

Summarise findings for the user, grouped by:

- Must-fix to become proxy-aware
- Recommended migration for standards alignment
- Optional improvements

Do not edit files until the user has confirmed migration choices in Step 2.

---

## Step 2: Confirm migration strategy with the user

Ask three choices before editing:

1. **Library upgrade mode**
   - **Default:** upgrade to the latest versions of relevant `hmpps-typescript-lib` packages
   - **Alternative:** upgrade only to minimum proxy-aware versions
   - **Alternative:** keep current library versions and use targeted fallback changes only

2. **Helm env-var rollout mode**
   - Add proxy env vars in `helm_deploy/values.yaml` (all environments)
   - Stage by environment: `values-dev.yaml`, then `values-preprod.yaml`, then `values-prod.yaml`

3. **Scope of code migration**
   - Full migration to HMPPS libraries where possible
   - Keep behaviour closest to existing code and use fallback for difficult paths

After the user chooses, repeat the agreed plan in one concise summary and then proceed.

---

## Step 3: Apply library version strategy

If upgrade mode is latest (default), upgrade to latest published versions for:

- `@ministryofjustice/hmpps-rest-client`
- `@ministryofjustice/hmpps-auth-clients`
- `@ministryofjustice/hmpps-monitoring`
- `@ministryofjustice/hmpps-azure-telemetry`

If upgrade mode is minimum proxy-aware, ensure at least:

- `@ministryofjustice/hmpps-rest-client` `2.1.0` or newer
- `@ministryofjustice/hmpps-monitoring` `2.1.0` or newer
- `@ministryofjustice/hmpps-azure-telemetry` `1.0.0` or newer
- `@ministryofjustice/hmpps-auth-clients` `3.0.0` or newer

If upgrade mode is no upgrade, do not change package versions unless user asks.

If a proxy-aware library needed for a selected migration path is missing, install it instead of using fallback patterns purely because it is not present.

In no-upgrade mode, install the minimum proxy-aware version needed for the missing package rather than introducing custom fallback code by default.

Always explain expected behavioural impact before major migrations.

---

## Step 4: Migrate outbound HTTP clients

### Preferred path

For most API calls, migrate clients to `@ministryofjustice/hmpps-rest-client` and align with `hmpps-template-typescript` patterns.

Use this decision rule before migrating any legacy client:

- If the client targets HMPPS Auth or token verification concerns, prefer `@ministryofjustice/hmpps-auth-clients`.
- If the client targets domain or business APIs, prefer `@ministryofjustice/hmpps-rest-client` with an injected auth client where needed.

Prioritise replacing:

- Direct `superagent` request construction
- `agentkeepalive` agent creation in app client code

### Authentication flows

Where the app has custom token acquisition, token verification, or caching code, prefer `@ministryofjustice/hmpps-auth-clients`.

For token verification paths (for example `tokenVerification.ts` style modules), use the verification client from `@ministryofjustice/hmpps-auth-clients` rather than implementing verification directly on top of `@ministryofjustice/hmpps-rest-client`.

Treat this as a default rule unless the user explicitly requests a fallback due to compatibility risk.

For legacy clients named like `AuthenticationClient` or `manageUsersApiClient`, classify by endpoint responsibility before migration:

- If it handles HMPPS Auth or token verification responsibilities, migrate to the relevant `@ministryofjustice/hmpps-auth-clients` client.
- Do not create a new direct `hmpps-rest-client` implementation for those auth responsibilities.
- Only keep a custom `hmpps-rest-client` client where the endpoint is outside the coverage of `hmpps-auth-clients`, and explain why.

### Health and ping flows

If legacy custom health-check HTTP modules exist, migrate to `@ministryofjustice/hmpps-monitoring` endpoint health components.

If `@ministryofjustice/hmpps-monitoring` is missing, install it and continue the migration. Do not switch to fallback health-check HTTP code only because the package is absent.

### Telemetry

Prefer `@ministryofjustice/hmpps-azure-telemetry` and ensure it initialises before instrumented modules load.

If the telemetry file imports logger and logs during shutdown, apply the PR #778-equivalent fix by removing logger dependency from telemetry bootstrap and shutdown path.

---

## Step 5: Fallback path for drifted services

Some services have drifted heavily from template patterns. If full migration is too risky or too disruptive, use targeted fallback changes:

1. Keep existing client shape where needed
2. Replace proxy-unaware agents with proxy-aware alternatives such as `https-proxy-agent`
3. Ensure proxy environment variables are read correctly
4. Preserve existing timeout, retry, and payload behaviours where possible

Do not choose fallback solely because a proxy-aware HMPPS package is missing; install the package first, then reassess compatibility risk.

Do not keep or re-create `abstractHmppsRestClient`-style auth clients when `hmpps-auth-clients` provides the equivalent flow, unless the user explicitly accepts the compatibility trade-off.

Document each fallback decision in the user-facing summary so trade-offs are explicit.

---

## Step 6: Apply Helm proxy configuration

Add proxy env configuration using the rollout mode chosen in Step 2.

For TypeScript services, use this standard pattern:

```yaml
generic-service:
  env:
    NODE_USE_ENV_PROXY: "1"
    APPLICATION_INSIGHTS_NO_STATSBEAT: "true"
  namespace_secrets:
    hmpps-envoy-https-proxy-env:
      HTTP_PROXY: "HTTP_PROXY"
      HTTPS_PROXY: "HTTPS_PROXY"
      NO_PROXY: "NO_PROXY"
      http_proxy: "HTTP_PROXY"
      https_proxy: "HTTPS_PROXY"
      no_proxy: "NO_PROXY"
```

If only staged env files are chosen, apply first to dev unless the user requests otherwise.

---

## Step 7: Validate and report

After code and config changes, run validation in the target repo:

```bash
npm run typecheck && npm run lint && npm run test
```

Then summarise:

- Which files changed
- Which migrations were completed
- Which fallback decisions were used
- Any remaining risks or follow-up tasks

If validation fails, fix relevant issues and re-run checks.

---

## Step 8: Offer docs alignment update

After successful migration, offer to update internal guidance when needed:

- `hmpps-tech-docs/src/content/how-to-guides/retrofitting-egress-controls-with-envoy-proxy.md`

Only update docs when the user asks. Keep docs aligned with what this skill now supports.

---

## Notes and guardrails

- Prefer `hmpps-rest-client` for most outbound traffic.
- Use fallback changes when migration risk is high or behaviour must remain stable.
- Do not assume all services match template structure.
- Ask before introducing behavioural changes that may affect retries, timeouts, or auth semantics.
- Keep migration incremental when requested: dev first, then preprod, then prod.
