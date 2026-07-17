---
name: make-typescript-proxy-aware
description: >
  Helps TypeScript developers make applications proxy-aware in line with HMPPS patterns.
  Use this skill when asked to: configure proxy support, fix socket hang up errors after
  egress proxy rollout, migrate superagent or agentkeepalive clients, adopt hmpps-rest-client,
  hmpps-auth-clients, hmpps-monitoring, or hmpps-azure-telemetry, and apply Helm proxy env vars.
argument-hint: 'Describe the target repo and the migration goal, e.g. "fix socket hang up errors after proxy rollout"'
---

# Make TypeScript Proxy-Aware

This skill helps you make HMPPS TypeScript applications proxy-aware for Cloud Platform egress controls.

It focuses on proven HMPPS patterns from:

- `hmpps-template-typescript`
- `hmpps-typescript-lib`
- `hmpps-tech-docs/src/content/how-to-guides/retrofitting-egress-controls-with-envoy-proxy.md`

Use this skill when a service needs to route outbound HTTPS traffic through an Envoy forward proxy, especially when errors like `socket hang up` appear after proxy rollout.

## When to Use This Skill

Trigger this skill when the user asks you to:

- Make a service or repo proxy-aware for Cloud Platform egress controls
- Diagnose or fix `socket hang up` (or similar connection reset) errors that started after an Envoy proxy rollout
- Migrate outbound HTTP clients away from raw `superagent` or `agentkeepalive` usage
- Adopt or upgrade `@ministryofjustice/hmpps-rest-client`, `hmpps-auth-clients`, `hmpps-monitoring`, or `hmpps-azure-telemetry`
- Add or stage proxy environment variables (`HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`) in Helm values

Do not use this skill for unrelated Helm changes, general dependency upgrades, or non-HMPPS TypeScript services — it assumes HMPPS template conventions and Cloud Platform egress controls.

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

5. Check whether `hmpps-typescript-lib` and/or `hmpps-template-typescript` are checked out as sibling directories next to the target repo (for example `../hmpps-typescript-lib`, `../hmpps-template-typescript`). These are the canonical source of the patterns this skill applies:
   - **If found:** read the real source there directly for anything version-specific (exact exported API, current file layout, latest example client) instead of relying on memory or bundled snippets — it's the freshest possible source of truth.
   - **If not found:** tell the user that cloning these two repos as siblings would let you cross-reference the canonical pattern directly, and ask if they'd like to do that now. If they'd rather not, continue anyway using `references/rest-client-migration-pattern.md` (a distilled snapshot of the current template pattern), and fetch specific files on demand when you need to verify something precisely, for example:
     ```bash
     gh api repos/ministryofjustice/hmpps-template-typescript/contents/server/data/exampleApiClient.ts --jq '.content' | base64 -d
     ```
   - Either way, do not assume the bundled snapshot is exhaustive — it covers the core client/auth/config pattern only.

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

Before writing code against any of these libraries, check the actual installed version and its real exported API (for example `node_modules/@ministryofjustice/<package>/dist` or its `README.md`, or `npm view <package> versions`) rather than assuming a shape from memory — these packages evolve and older guidance may not match the installed version.

---

## Step 4: Migrate outbound HTTP clients

### Preferred path

For most API calls, migrate clients to `@ministryofjustice/hmpps-rest-client` and align with `hmpps-template-typescript` patterns. Follow [references/rest-client-migration-pattern.md](references/rest-client-migration-pattern.md) for the exact current shape of an API client, its wiring in `server/data/index.ts`, and the `handleNotFoundErrorAsNull` pattern for typed 404 handling — do not guess the constructor signature or call shape from memory.

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
- If the client only fetches current-user display data (name, roles, caseload), check first whether that data is already available from decoding the user's JWT elsewhere in the app (for example in `setUpCurrentUser`/`populateCurrentUser`). If so, prefer removing the client and its call sites entirely over migrating it — see the `manageUsersApiClient` case in [references/pr-437-lessons.md](references/pr-437-lessons.md).

Any local `AgentConfig`/`ApiConfig` type definitions in `config.ts` should be replaced with the equivalents imported from `@ministryofjustice/hmpps-rest-client`, and any config field renames this implies (for example `apiClientId` → `authClientId`, `domain` → `ingressUrl`) should be searched for and updated at every call site, not just in `config.ts` — see [references/pr-437-lessons.md](references/pr-437-lessons.md).

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

Also offer to write or update the target repo's own `.github/copilot-instructions.md`, summarising the new client/auth/config patterns (controller → service → API client layering, how tokens are obtained via `asSystem()`/`asUser()`, where config renames landed) so future Copilot-assisted changes to that repo don't drift back to the pre-migration approach. Only do this if the user agrees. See the worked example in [references/pr-437-lessons.md](references/pr-437-lessons.md).

---

## Lessons from a real migration (PR #437)

[hmpps-visits-internal-admin-ui PR #437](https://github.com/ministryofjustice/hmpps-visits-internal-admin-ui/pull/437) is a real, Copilot-assisted migration from a drifted service to the current `hmpps-template-typescript` pattern. Full lessons are in [references/pr-437-lessons.md](references/pr-437-lessons.md); the headlines are:

- Bespoke `restClient.ts`, `hmppsAuthClient.ts`, `tokenVerification.ts`, and `tokenStore/*.ts` files were deleted outright, not refactored in place, once the library equivalents were wired up.
- A `manageUsersApiClient` used only for current-user display data was removed entirely, because that data was already available from the user's JWT — not migrated onto `hmpps-auth-clients`.
- Config renames (`apiClientId` → `authClientId`, `domain` → `ingressUrl`) rippled beyond `config.ts` into `setUpAuthentication.ts` and auth URL construction.
- Stale Helm values for deleted clients (unused API URLs, an unnecessary blank line) were cleaned up as part of the same change, not left behind.

---

## Notes and guardrails

- Prefer `hmpps-rest-client` for most outbound traffic.
- Use fallback changes when migration risk is high or behaviour must remain stable.
- Do not assume all services match template structure.
- Ask before introducing behavioural changes that may affect retries, timeouts, or auth semantics.
- Keep migration incremental when requested: dev first, then preprod, then prod.

---

## Gotchas

- **`socket hang up` after rollout usually means an agent bypasses the proxy.** Look for `agentkeepalive` or custom `https.Agent`/`http.Agent` instances created outside `hmpps-rest-client` — these often ignore `HTTP_PROXY`/`HTTPS_PROXY` entirely.
- **`NODE_USE_ENV_PROXY: "1"` is required, not optional**, for Node's built-in `undici`/`fetch`-based clients to honour proxy env vars — services relying solely on library-level proxy support without this flag can still bypass the proxy for some requests.
- **Telemetry must initialise before logger use (PR #778 pattern).** If a telemetry bootstrap file imports the app logger and logs during shutdown, that import order can suppress or break telemetry — remove the logger dependency from telemetry bootstrap and shutdown paths.
- **Auth-shaped clients aren't always auth clients.** A class named `AuthenticationClient` or `manageUsersApiClient` may still be a general REST client — classify by the endpoint it calls (HMPPS Auth/token verification vs. domain API), not by its name, before deciding whether it belongs in `hmpps-auth-clients` or `hmpps-rest-client`.
- **Missing package is not a reason to fall back.** Default to installing the proxy-aware HMPPS package and reassessing risk, rather than writing custom fallback code, unless the user explicitly accepts the compatibility trade-off.
- **App-level changes alone don't fix `socket hang up` errors.** Confirm the namespace has the Cloud Platform Envoy proxy secret wired up (Step 0) — without it, code changes have no effect.
- **A "user info" API client may already be redundant.** Before migrating a client that only fetches the current user's name/roles/caseload, check whether that data is already decoded from the user's JWT elsewhere (see the `manageUsersApiClient` removal in [references/pr-437-lessons.md](references/pr-437-lessons.md)) — deleting the client can be the correct outcome, not migrating it.
- **Bundled reference snippets can go stale.** `references/rest-client-migration-pattern.md` is a snapshot; prefer reading `hmpps-typescript-lib`/`hmpps-template-typescript` directly (sibling checkout or `gh api`) whenever precision matters, per Step 0.
