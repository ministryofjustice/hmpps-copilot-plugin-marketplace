---
name: make-typescript-proxy-aware
description: >
  Helps TypeScript developers make applications proxy-aware and bring a drifted HMPPS service's
  infrastructure (data clients, auth, config, monitoring, telemetry) back into line with the
  current hmpps-template-typescript patterns, delivered as separately reviewable phases rather
  than one large PR. Use this skill when asked to: configure proxy support, fix socket hang up
  errors after egress proxy rollout, migrate superagent or agentkeepalive clients, adopt
  hmpps-rest-client, hmpps-auth-clients, hmpps-monitoring, or hmpps-azure-telemetry, align a
  drifted service with hmpps-template-typescript, or apply Helm proxy env vars.
argument-hint: 'Describe the target repo and how far to go: proxy-only fix, or full phased template alignment'
---

# Make TypeScript Proxy-Aware

This skill helps you make HMPPS TypeScript applications proxy-aware for Cloud Platform egress controls — and, because most of the value comes from aligning with the current `hmpps-template-typescript` patterns rather than a narrow proxy-only fix, it treats deeper template alignment as the primary goal, with proxy-awareness as the main forcing function and first deliverable.

It focuses on proven HMPPS patterns from:

- `hmpps-template-typescript`
- `hmpps-typescript-lib`
- `hmpps-tech-docs/src/content/how-to-guides/retrofitting-egress-controls-with-envoy-proxy.md`
- [hmpps-visits-internal-admin-ui PR #437](https://github.com/ministryofjustice/hmpps-visits-internal-admin-ui/pull/437), a real migration that went beyond proxy-awareness into full infrastructure alignment (see [references/pr-437-lessons.md](references/pr-437-lessons.md))

Use this skill when a service needs to route outbound HTTPS traffic through an Envoy forward proxy (especially when errors like `socket hang up` appear after proxy rollout), or when a service cut from the template years ago has drifted and needs to catch up on its infrastructure layer.

## When to Use This Skill

Trigger this skill when the user asks you to:

- Make a service or repo proxy-aware for Cloud Platform egress controls
- Diagnose or fix `socket hang up` (or similar connection reset) errors that started after an Envoy proxy rollout
- Migrate outbound HTTP clients away from raw `superagent` or `agentkeepalive` usage
- Adopt or upgrade `@ministryofjustice/hmpps-rest-client`, `hmpps-auth-clients`, `hmpps-monitoring`, or `hmpps-azure-telemetry`
- Bring a drifted service's auth, data-client, config, monitoring, or telemetry layer back in line with `hmpps-template-typescript` — not just its outbound HTTP handling
- Plan a multi-phase migration where each phase is its own reviewable, testable commit rather than one large PR
- Add or stage proxy environment variables (`HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`) in Helm values

Do not use this skill for unrelated Helm changes, general dependency upgrades, or non-HMPPS TypeScript services — it assumes HMPPS template conventions and Cloud Platform egress controls. Do not use it to rewrite business logic, routes, views, or domain-specific behaviour — scope is limited to the infrastructure layer (see Outcome below). For ongoing template maintenance once a service has caught up, hand off to the `sync-typescript-template` skill (see Phase 4).

---

## Outcome

By the end of this skill, the target app should:

- Use proxy-aware outbound HTTP client patterns
- Use current HMPPS shared libraries where practical, with its auth, data-client, config, and monitoring/telemetry layers aligned with `hmpps-template-typescript` — not just the HTTP transport
- Have proxy environment variables configured in Helm values
- Keep behavioural changes low-risk for drifted or legacy services
- Have been delivered as a sequence of separately committed, separately validated phases (see "Phased delivery" below) rather than one large, hard-to-review change
- Pass validation checks after each phase

**Scope boundary:** this skill only touches the infrastructure layer — outbound HTTP clients, auth/token handling, config shape, monitoring, and telemetry. It does not rewrite routes, controllers, services' business logic, or views, even where those exist in `hmpps-template-typescript` too. If the user wants a broader realignment beyond infrastructure, tell them to use `sync-typescript-template` for specific additional template changes instead.

### Phased delivery

Rather than delivering one large, hard-to-review PR, work through up to four phases, each ending with its own validate → commit → checkpoint (see "Phase checkpoint pattern" below) before starting the next:

1. **Phase 1 — Proxy-critical: outbound HTTP client + Helm.** Replace `superagent`/`agentkeepalive` with `@ministryofjustice/hmpps-rest-client` and add Helm proxy env vars. This alone fixes the proxy problem and is the smallest, lowest-risk, most reviewable change.
2. **Phase 2 — Auth alignment.** Replace custom `hmppsAuthClient`/`tokenVerification`/`tokenStore` modules with `@ministryofjustice/hmpps-auth-clients`. Depends on Phase 1's client pattern; makes auth flows proxy-aware too and unlocks JWT-based user data.
3. **Phase 3 — Structural cleanup enabled by Phase 2.** Config renames, removal of now-redundant clients (for example a `manageUsersApiClient` superseded by JWT claims), monitoring migration, telemetry migration. This is the deepest and riskiest phase — keep it as small a diff as possible.
4. **Phase 4 — Docs and handoff.** Update or author `.github/copilot-instructions.md` to lock in the new patterns, and point the user at `sync-typescript-template` for keeping pace with the template going forward.

Confirm with the user in Step 2 which phases to run — they may only want Phase 1, or all four.

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

## Step 1: Assess current alignment and proxy readiness

Search for patterns that usually break with proxy rollout, and for infrastructure that has drifted from the current template:

1. Direct `superagent` usage
2. `agentkeepalive` usage (`Agent`, `HttpsAgent`)
3. Custom HTTP clients that do not read proxy env vars
4. Manual auth token request flows that bypass standard clients
5. Token verification modules (for example `tokenVerification.ts`) implemented directly with `hmpps-rest-client` or custom REST wrappers instead of `hmpps-auth-clients` verification client
6. Custom `tokenStore/*.ts` implementations (in-memory or Redis) that duplicate what `hmpps-auth-clients` now provides
7. Legacy health check HTTP stacks
8. Legacy App Insights setup instead of `hmpps-azure-telemetry`
9. Telemetry setup that imports logger before telemetry initialisation (PR #778 pattern)
10. Legacy auth-oriented API clients built on shared base classes (for example `abstractHmppsRestClient`) such as `manageUsersApiClient` or `AuthenticationClient` that should map to `@ministryofjustice/hmpps-auth-clients`
11. Config field names that predate `hmpps-auth-clients`/`hmpps-rest-client` (for example `apiClientId`/`apiClientSecret` instead of `authClientId`/`authClientSecret`, or `domain` instead of `ingressUrl`) — see [references/pr-437-lessons.md](references/pr-437-lessons.md)
12. Locally-defined `AgentConfig`/`ApiConfig` types in `config.ts` that duplicate the ones exported by `@ministryofjustice/hmpps-rest-client`
13. `new SQSClient(...)` usage — an AWS SDK client constructed directly, which does not respect proxy environment variables. Most often found in a client related to the HMPPS Audit service (for example `auditClient.ts`/`HmppsAuditClient`), but can appear anywhere the app talks to SQS directly. See [references/sqs-client-migration-pattern.md](references/sqs-client-migration-pattern.md) for how to resolve it.

Summarise findings for the user, grouped by:

- Must-fix to become proxy-aware (Phase 1)
- Recommended migration for standards alignment (Phases 2–3)
- Optional improvements (Phase 4 and beyond)

Do not edit files until the user has confirmed the phased migration plan in Step 2.

---

## Step 2: Confirm phased migration plan with the user

Ask which phases to run, and the strategy for each phase the user selects. Present the four phases from "Phased delivery" above and let the user choose a subset (for example "just Phase 1" or "all four"), then confirm these choices:

1. **Library upgrade mode**
   - **Default:** upgrade to the latest versions of relevant `hmpps-typescript-lib` packages
   - **Alternative:** upgrade only to minimum proxy-aware versions
   - **Alternative:** keep current library versions and use targeted fallback changes only

2. **Helm env-var rollout mode** (dev-first by default)
   - **Default:** Add proxy env vars to `helm_deploy/values-dev.yaml` only, validate Phase 1 in dev, then ask before rolling out further
   - **Alternative:** Add to `values.yaml` (all environments) only if the user explicitly requests it
   - **If rolling out:** After dev validation, stage to `values-preprod.yaml`, then `values-prod.yaml` — each as a separate, tested commit

3. **Scope of code migration**
   - Full migration to HMPPS libraries where possible
   - Keep behaviour closest to existing code and use fallback for difficult paths

After the user chooses, repeat the agreed plan in one concise summary — including which phases will run and in what order — and then proceed. Remind the user that each phase will end with its own commit checkpoint, so they can stop, review, and ship one phase before deciding whether to continue.

---

## Phase checkpoint pattern

At the end of every phase below, repeat this checkpoint before moving to the next phase:

1. Run validation in the target repo:
   ```bash
   npm run typecheck && npm run lint && npm run test
   ```
   If validation fails, fix relevant issues and re-run checks before proceeding.
   If this phase changed any dependency versions (`package.json`/`package-lock.json`), also verify the lock file is installable from clean before considering validation complete:
   ```bash
   rm -rf node_modules package-lock.json && npm install && npm ci
   ```
   A targeted `npm install <package>@<version>` (or `npm uninstall`) can silently prune unrelated optional/platform packages from the lock file (see Gotchas) — `npm ci` succeeding locally is not sufficient proof; only a clean reinstall reliably surfaces this before CI does. **Do not shortcut this to `rm -rf node_modules && npm ci` (keeping the existing `package-lock.json`)** — that only re-installs whatever the (possibly already-pruned) lock file says for your own machine's platform, so it will pass even when other platforms' optional entries (for example Linux `sass-embedded-linux-x64`/`chokidar`/`readdirp` variants, needed by a Linux CI runner but not by your local macOS/arm machine) have been silently dropped. You must delete `package-lock.json` itself and regenerate it with a full, argument-less `npm install` to catch this class of failure locally — a targeted install/uninstall earlier in the same session is enough to cause it, even if every other check passed.
2. Summarise the phase: which files changed, what was migrated, any fallback decisions taken, and remaining risks.
3. Suggest a commit scoped to just this phase, for example:
   ```
   chore: adopt @ministryofjustice/hmpps-rest-client for outbound HTTP clients (proxy-aware Phase 1)
   ```
4. If this is Phase 1 and Helm changes were applied to `values-dev.yaml`, ask the user:
   - "Phase 1 code changes are validated in dev. Do you want me to apply the same Helm proxy env vars to `values-preprod.yaml` and `values-prod.yaml` now, or wait?"
   - Only proceed with rolling out Helm changes to preprod/prod if the user explicitly confirms.
5. Ask the user whether to continue to the next phase now, stop here, or pause so they can review/ship this phase first. Do not start the next phase without confirmation.

---

## Phase 1: Proxy-critical — outbound HTTP client + Helm

This phase alone fixes proxy connectivity. Keep it scoped to client/transport changes and Helm config only — do not touch auth or config renames here (that's Phase 2/3).

### Library versions

If upgrade mode is latest (default), upgrade to latest published versions for:

- `@ministryofjustice/hmpps-rest-client`

If upgrade mode is minimum proxy-aware, ensure at least `@ministryofjustice/hmpps-rest-client` `2.1.0` or newer. If upgrade mode is no upgrade, do not change package versions unless user asks.

If a proxy-aware library needed for this phase is missing, install it instead of using fallback patterns purely because it is not present.

Before writing code against this library, check the actual installed version and its real exported API (for example `node_modules/@ministryofjustice/hmpps-rest-client/dist` or its `README.md`, or `npm view @ministryofjustice/hmpps-rest-client versions`) rather than assuming a shape from memory — these packages evolve and older guidance may not match the installed version.

### Migrate outbound HTTP clients

For most API calls, migrate clients to `@ministryofjustice/hmpps-rest-client`. Follow [references/rest-client-migration-pattern.md](references/rest-client-migration-pattern.md) for the exact current shape of an API client and the `handleNotFoundErrorAsNull` pattern for typed 404 handling — do not guess the constructor signature or call shape from memory. At this phase, keep the existing `hmppsAuthClient`/token acquisition code as-is and just pass its token through (full auth-client migration happens in Phase 2).

Prioritise replacing:

- Direct `superagent` request construction
- `agentkeepalive` agent creation in app client code

### Migrate direct `new SQSClient` usage

If Step 1 found a directly-constructed `new SQSClient(...)`, follow this decision tree rather than assuming one fix applies everywhere — see [references/sqs-client-migration-pattern.md](references/sqs-client-migration-pattern.md) for full detail:

1. **Check whether the usage relates to audit** — is it in a client named like `auditClient`/`HmppsAuditClient`, or otherwise wired up to send events to the HMPPS Audit service? If unclear, ask the user.
2. **If it relates to audit:** check whether `hmpps-typescript-lib`'s `main` branch (and npm) now has a published `audit-client` package.
   - **If yes:** migrate the app to import `@ministryofjustice/hmpps-audit-client` (confirm the exact published package name) instead of constructing `SQSClient` directly — this package is proxy-aware. Check the package has actually been published to npm (not just merged to `main`), and upgrade the app to at least that version before importing from it.
   - **If no (not yet published):** apply the local fallback pattern instead (see below) — do not block the phase waiting for the upstream package.
3. **If it's unrelated to audit, or the `audit-client` package doesn't exist yet:** implement the proxy-aware `NodeHttpHandler` + `HttpsProxyAgent` fallback pattern directly in the target repo, scoped to its own SQS client file.

Whichever path is used, this is still Phase 1 work — it fixes proxy connectivity for SQS traffic the same way the outbound HTTP client migration does.

### Apply Helm proxy configuration

Add proxy env configuration to **`helm_deploy/values-dev.yaml` only** at this stage. For TypeScript services, use this standard pattern:

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

Add only to `values-dev.yaml` — do not apply to `values-preprod.yaml`, `values-prod.yaml`, or the shared `values.yaml` unless the user explicitly asks for it after dev validation.

Run the **Phase checkpoint pattern** before moving on. After dev validation passes:

- If the user only wanted proxy-awareness, stop here — Phases 2–4 are optional deeper alignment.
- **Before rolling out to preprod/prod:** ask the user whether to apply the same Helm change to `values-preprod.yaml` and `values-prod.yaml`. Do not assume a staged rollout unless the user confirms each stage. If they want a full rollout, treat each environment as a separate commit (dev first, validated; then preprod, validated; then prod).

---

## Phase 2: Auth alignment

Depends on Phase 1's client pattern. Migrates token acquisition, verification, and storage to `@ministryofjustice/hmpps-auth-clients`.

### Library versions

Upgrade `@ministryofjustice/hmpps-auth-clients` following the mode chosen in Step 2 (latest by default, `3.0.0`+ minimum, or skip if no-upgrade). If missing, install it rather than keeping custom auth code as a fallback purely because the package is absent.

### Authentication flows

Where the app has custom token acquisition, token verification, or caching code, migrate to `@ministryofjustice/hmpps-auth-clients`:

- Replace a custom `hmppsAuthClient.ts`-style module with `AuthenticationClient` (see [references/rest-client-migration-pattern.md](references/rest-client-migration-pattern.md) for the `server/data/index.ts` wiring).
- Replace a custom `tokenVerification.ts` module with `VerificationClient`. Its `verifyToken(request: AuthenticatedRequest)` method takes the library's own `AuthenticatedRequest` shape, not a plain Express `Request` — this is not a drop-in replacement for a local `TokenVerifier` type. Check how the app's authentication middleware calls its verifier (for example a passport-based `authenticationMiddleware(tokenVerifier)` wrapper) and update that middleware's verifier type/signature too, casting the request where needed (`request as unknown as AuthenticatedRequest`), following the exact pattern in `hmpps-template-typescript`'s `setUpAuthentication.ts`.
- Replace custom `tokenStore/*.ts` implementations (in-memory or Redis) with the `InMemoryTokenStore`/`RedisTokenStore` the library exports — do not keep bespoke token store files once this package is in use, **unless another, unrelated part of the app reuses the same token-store abstraction for non-auth caching** (for example a reference-data cache built on the same `TokenStore` interface). In that case, only remove the auth-specific usage and leave the shared files in place for their other purpose — grep for all importers of the token store files before deleting them, not just the auth-related ones.

Treat this as a default rule unless the user explicitly requests a fallback due to compatibility risk.

For legacy clients named like `AuthenticationClient` or `manageUsersApiClient`, classify by endpoint responsibility before migration:

- If it handles HMPPS Auth or token verification responsibilities, migrate to the relevant `@ministryofjustice/hmpps-auth-clients` client.
- Do not create a new direct `hmpps-rest-client` implementation for those auth responsibilities.
- Only keep a custom `hmpps-rest-client` client where the endpoint is outside the coverage of `hmpps-auth-clients`, and explain why.

Once the shared `AuthenticationClient` instance exists in `server/data/index.ts`, check for any other place in the app that constructs its own separate `AuthenticationClient` purely to reuse its token store (for example a permissions/authorisation library's config expecting an `authenticationClient` option) — pass the same shared instance through instead of constructing a second one.

After swapping in the library's `AuthenticationClient`/`VerificationClient`, check whether any now-unused local helper types or modules were left behind (for example a bespoke `SanitisedError`/error-mapping helper that existed only to support the old `tokenVerification.ts`) and remove them too — grep for their remaining usages first to confirm they're actually dead, don't assume.

Run the **Phase checkpoint pattern** before moving on.

---

## Phase 3: Structural cleanup enabled by Phase 2

This is the deepest and riskiest phase — it's where most of PR #437's real value came from, but also where the diff can balloon. Keep each change as small and separately explainable as possible, and lean on the fallback path (below) for anything that looks too risky to do in full.

### Redundant clients

If a client only fetches current-user display data (name, roles, caseload), check first whether that data is already available from decoding the user's JWT elsewhere in the app (for example in `setUpCurrentUser`/`populateCurrentUser`). If so, prefer removing the client and its call sites entirely over migrating it — see the `manageUsersApiClient` case in [references/pr-437-lessons.md](references/pr-437-lessons.md). This kind of deletion, not just migration, is what "deeper alignment" means in practice — flag it clearly in the phase summary since it's a bigger behavioural change than a like-for-like swap.

### Config renames

Any local `AgentConfig`/`ApiConfig` type definitions in `config.ts` should be replaced with the equivalents imported from `@ministryofjustice/hmpps-rest-client`, and any config field renames this implies (for example `apiClientId` → `authClientId`, `domain` → `ingressUrl`) should be searched for and updated at every call site, not just in `config.ts` — see [references/pr-437-lessons.md](references/pr-437-lessons.md).

Before assuming a field rename requires Helm changes, check whether the underlying env var name is already decoupled from the JS field name. Most `config.ts` implementations use a `get(envVarName, fallback, options)` helper where the env var name is a plain string argument, not derived from the object key — so renaming `domain` → `ingressUrl` or `signInClientId` → `authClientId` is often a **pure internal rename** with zero Helm/secret impact, as long as the `get('INGRESS_URL', ...)`/`get('SIGN_IN_CLIENT_ID', ...)` string argument itself is left unchanged. Only touch Helm `namespace_secrets`/env values if you are also renaming the env var itself (for example to match the template's `AUTH_CODE_CLIENT_ID` naming) — treat that as a separate, explicitly-confirmed step, not a default part of this phase.

### Health and ping flows

If legacy custom health-check HTTP modules exist, migrate to `@ministryofjustice/hmpps-monitoring` endpoint health components. If the package is missing, install it and continue the migration rather than switching to fallback health-check HTTP code only because it's absent.

### Telemetry

Prefer `@ministryofjustice/hmpps-azure-telemetry` and ensure it initialises before instrumented modules load. If the telemetry file imports logger and logs during shutdown, apply the PR #778-equivalent fix by removing the logger dependency from telemetry bootstrap and shutdown paths.

**Node 24 + Envoy can break raw `applicationinsights` even without any other proxy work.** If the target app still uses the raw `applicationinsights` SDK directly (not yet on `hmpps-azure-telemetry`) and runs on Node 24, its default HTTP(S) agent handling can be actively broken by the Cloud Platform Envoy proxy — not just "unproxied," but rejected outright (Envoy access logs show `response_code: 403`, `response_code_details: "http1.https_url_on_plaintext_connection"`). This is a real, must-fix defect, not a hypothetical one, whenever the target service is/will be on Node 24 behind Envoy.

When you hit this, compare two options by actual diff size/risk before picking one — do not default to the full library migration just because it's the "preferred" option in the abstract:

1. **Lightweight fix (usually less work when the app is still on raw `applicationinsights`):** force the SDK onto Node's own core, proxy-aware `http.Agent`/`https.Agent` instances (activated by `NODE_USE_ENV_PROXY`, same mechanism `hmpps-rest-client` relies on) instead of the SDK's own bespoke `proxyHttpUrl`/`proxyHttpsUrl` handling. This is a single-file, ~30-40 line change to the app's `azureAppInsights.ts`-equivalent: clear `config.proxyHttpUrl`/`config.proxyHttpsUrl`, and set `config.httpAgent`/`config.httpsAgent` to `new HttpAgent({ keepAlive: true, proxyEnv: process.env })` / `new HttpsAgent({ keepAlive: true, proxyEnv: process.env })`, applied between `setup()` and `start()`. Pass the full `process.env` object (not a hand-built subset) as `proxyEnv` — Node's `http.Agent`/`https.Agent` types expect the whole `NodeJS.ProcessEnv` shape, and a narrowed object literal will fail typecheck if the app augments `ProcessEnv` with its own keys. Only apply the override when at least one proxy env var is actually set, so local/dev runs without a proxy are unaffected. See a real example: [hmpps-prisoner-pay-ui PR #101](https://github.com/ministryofjustice/hmpps-prisoner-pay-ui/pull/101/changes).
2. **Full migration to `hmpps-azure-telemetry`:** a bigger, OpenTelemetry-based rewrite — different API (`initialiseTelemetry()`/spans/processors instead of `TelemetryClient.trackEvent(name, properties)`), requiring changes to every call site that currently calls `trackEvent` (a wrapping `telemetryService.ts` plus each route/service that imports it), not just the bootstrap file.

Pick whichever is the smaller, lower-risk diff for the app as it stands today — if the app is still on raw `applicationinsights`, that's almost always option 1; if it's already on `hmpps-azure-telemetry` (or already mid-migration to it), just fix or confirm its Node 24 proxy-agent behaviour directly rather than introducing a second telemetry pattern. Don't present this as an open question to the user without also making and executing a recommendation — the user may explicitly ask you to decide and implement, not just report options.

#### Lessons from a real full `hmpps-azure-telemetry` migration

A complete option-2 migration (raw `applicationinsights` → `@ministryofjustice/hmpps-azure-telemetry`) was carried out end-to-end on a real drifted service. It succeeded, but surfaced enough real gotchas to record here in detail — treat this as the authoritative shape of that migration, not the abbreviated summary above:

1. **Check for a hidden `applicationinsights` dependency via a shared HMPPS lib before touching the app's own telemetry code.** A service can have `applicationinsights` in `package.json` not because it uses it directly, but only because an older version of `@ministryofjustice/hmpps-prison-permissions-lib` (or a similar shared lib) imports `TelemetryClient` purely for its type, and the app passes its App Insights client through to that lib's `.create({ telemetryClient })` option. If so, check whether a newer major version of that lib has dropped `applicationinsights` in favour of a minimal structural interface (for example `{ trackEvent(name, attributes?): void }`) — `hmpps-prison-permissions-lib` v4.0.0+ did exactly this, and its changelog explicitly recommends passing `hmpps-azure-telemetry`'s `telemetry` export directly as `telemetryClient` since it already satisfies the interface. Upgrading that lib first removes one whole leg of dependency conflict before installing the new telemetry package, and is itself a values-add (dropping a legacy dependency), not just an unblocking step. Read that lib's changelog for other breaking changes bundled into the same major bump and grep the app for any affected APIs before upgrading.
2. **Expect a real `@opentelemetry/*` peer-dependency clash with `@sentry/node`.** `@sentry/node` (if already present, which is common in HMPPS template-derived apps) bundles its own OpenTelemetry instrumentation stack. `hmpps-azure-telemetry` exact-pins several `@opentelemetry/*` peers (for example `@opentelemetry/api@1.9.0`, `@opentelemetry/resources@2.5.1`). When these disagree with whatever Sentry resolved, `npm install` fails with `ERESOLVE`. Resolve by adding explicit `overrides` in `package.json` forcing the whole tree to one version per clashing package (prefer the newer version already in use elsewhere in the tree, since these are usually backward compatible within the same major line) — the same pattern likely already exists in the repo for `@opentelemetry/core` if it has hit this before with a Sentry upgrade, so this is an established, accepted pattern, not a novel workaround. If `npm install` produces only a truncated `npm error` line with no visible `ERESOLVE` detail, check `~/.npm/_logs/*-eresolve-report.txt` directly (not `-debug-0.log`) for the full conflict report.
3. **The app's existing App Insights init almost certainly runs too late in the import order for OpenTelemetry to work correctly — check this explicitly, don't assume the current wiring is fine.** Raw `applicationinsights` is forgiving about when `setup()`/`start()` are called relative to other imports (it uses diagnostics-channel-based patching). OpenTelemetry's `instrumentation-http`/`-express`/`-bunyan` are not — they must patch those modules before anything else `require`s them. A common drifted pattern is initialising App Insights inside a data-layer module (for example `server/data/index.ts`) that is imported after the app module (which imports `express` at its top), because `server/index.ts` does `import createApp from './app'` before `import { services } from './services'`. Migrating the telemetry call itself without also moving its invocation to be the literal first statement in the true process entry point (before even the app import chain starts) will silently produce incomplete or missing spans. The fix is a small, standalone side-effecting module (see the template's `azureAppInsights.ts`) that calls `initialiseTelemetry(...).startRecording()` at module load time, imported as the very first line of `server.ts`/`server.js` — ahead of the app import.
4. **There is no drop-in equivalent for a `res.locals`-reading App Insights telemetry processor.** A common existing pattern (`addUserDataToRequests`-style) reads `res.locals.user` inside an App Insights envelope processor to tag every telemetry item with the current user. `hmpps-azure-telemetry`'s span filter/modifier functions only see span name/kind/attributes/duration — they have no access to `req`/`res`. Replace this with a small Express middleware, registered *after* whatever middleware populates `res.locals.user` (and any caseload-enrichment middleware that runs after it), calling `telemetry.setSpanAttributes({ username, activeCaseLoadId, ... })` while the request's span is still active.
5. **`telemetry.trackEvent`'s attribute type is stricter than `TelemetryClient.trackEvent`'s `properties`.** The old App Insights client's `properties` bag commonly accepted `string | number | null | undefined` values (and callers pass `null`/`undefined` routinely, for example an optional caseload ID). The new library's attributes only accept `string | number | boolean`. When rewriting a wrapping `telemetryService.ts`, filter out `null`/`undefined` properties before forwarding them rather than passing them through — passing `null` will fail typecheck.
6. **Validate more than typecheck/lint/test for this specific phase** — because none of the unit test suite exercises the actual module-load-order behaviour that this migration depends on, add a manual smoke test as part of the phase checkpoint: `npm run build`, then run the built server directly (`node dist/server.js`), confirm it logs a sane telemetry-initialisation message and serves `/health`, then send it `SIGTERM` and confirm a "flushing telemetry" log appears before the process exits. This is the only way to actually confirm the import-order fix in point 3 worked, and that graceful-shutdown flushing (which the template's pattern requires you to add explicitly — there usually isn't an existing `SIGTERM`/`SIGINT` handler in a drifted app) behaves correctly.
7. **This migration alone does not empirically prove proxy-awareness.** `@azure/monitor-opentelemetry-exporter`'s transport is built on `@azure/core-rest-pipeline`, which is proxy-aware by design (matching why the template prefers it) — but this is a structural argument, not something you can confirm without a live Azure Application Insights endpoint and a working Envoy proxy in front of it. State this residual uncertainty explicitly in the phase summary rather than declaring the proxy problem fully verified-solved.

Run the **Phase checkpoint pattern** before moving on. Consider splitting this phase into smaller commits (for example redundant-client removal as one commit, config renames as another) if the combined diff is large.

---

## Phase 4: Docs and handoff

After the earlier phases, offer to update internal guidance when needed:

- `hmpps-tech-docs/src/content/how-to-guides/retrofitting-egress-controls-with-envoy-proxy.md` — only if the user asks, and only to keep it aligned with what this skill now supports.

Also offer to write or update the target repo's own `.github/copilot-instructions.md`, summarising the new client/auth/config patterns (controller → service → API client layering, how tokens are obtained via `asSystem()`/`asUser()`, where config renames landed) so future Copilot-assisted changes to that repo don't drift back to the pre-migration approach. Only do this if the user agrees. See the worked example in [references/pr-437-lessons.md](references/pr-437-lessons.md).

Finally, point the user at the `sync-typescript-template` skill for ongoing maintenance: once this catch-up is done, that skill applies individual upstream template PRs on demand, which is the right tool for staying current going forward rather than re-running this skill.

Run the **Phase checkpoint pattern** to close out.

---

## Fallback path for drifted services

Some services have drifted too heavily from template patterns for a full migration in any given phase to be safe. Where that's true for a specific phase, use targeted fallback changes instead of skipping the phase outright:

1. Keep existing client shape where needed
2. Replace proxy-unaware agents with proxy-aware alternatives such as `https-proxy-agent`
3. Ensure proxy environment variables are read correctly
4. Preserve existing timeout, retry, and payload behaviours where possible

Do not choose fallback solely because a proxy-aware HMPPS package is missing; install the package first, then reassess compatibility risk.

Do not keep or re-create `abstractHmppsRestClient`-style auth clients when `hmpps-auth-clients` provides the equivalent flow, unless the user explicitly accepts the compatibility trade-off.

Document each fallback decision in the phase summary so trade-offs are explicit.

---

## Lessons from a real migration (PR #437)

[hmpps-visits-internal-admin-ui PR #437](https://github.com/ministryofjustice/hmpps-visits-internal-admin-ui/pull/437) is a real, Copilot-assisted migration from a drifted service to the current `hmpps-template-typescript` pattern — delivered as one large PR rather than phased. Full lessons are in [references/pr-437-lessons.md](references/pr-437-lessons.md); the headlines, mapped to the phases above, are:

- **Phase 1/2:** Bespoke `restClient.ts`, `hmppsAuthClient.ts`, `tokenVerification.ts`, and `tokenStore/*.ts` files were deleted outright, not refactored in place, once the library equivalents were wired up.
- **Phase 3:** A `manageUsersApiClient` used only for current-user display data was removed entirely, because that data was already available from the user's JWT — not migrated onto `hmpps-auth-clients`.
- **Phase 3:** Config renames (`apiClientId` → `authClientId`, `domain` → `ingressUrl`) rippled beyond `config.ts` into `setUpAuthentication.ts` and auth URL construction.
- **Phase 3:** Stale Helm values for deleted clients (unused API URLs, an unnecessary blank line) were cleaned up as part of the same change, not left behind.
- **Phase 4:** A new `.github/copilot-instructions.md` was authored as part of the same PR to lock in the new patterns for future changes.

This skill breaks that same scope into four separately-reviewable phases rather than one PR — use the phase boundaries above even when following this example.

---

## Notes and guardrails

- Prefer `hmpps-rest-client` for most outbound traffic.
- Use fallback changes when migration risk is high or behaviour must remain stable.
- Do not assume all services match template structure.
- Ask before introducing behavioural changes that may affect retries, timeouts, or auth semantics.
- Keep migration incremental: **default to dev-only unless the user explicitly asks for more environments.** After dev validation, ask before rolling out to preprod/prod.
- Keep each phase in its own commit, validated independently, so the user can review and ship one phase before deciding whether to continue to the next.
- Stay within the infrastructure scope (see "Scope boundary" in Outcome) — do not extend phases into business logic, routes, or views.

---

## Gotchas

- **`socket hang up` after rollout usually means an agent bypasses the proxy.** Look for `agentkeepalive` or custom `https.Agent`/`http.Agent` instances created outside `hmpps-rest-client` — these often ignore `HTTP_PROXY`/`HTTPS_PROXY` entirely.
- **`NODE_USE_ENV_PROXY: "1"` is required, not optional**, for Node's built-in `undici`/`fetch`-based clients to honour proxy env vars — services relying solely on library-level proxy support without this flag can still bypass the proxy for some requests.
- **Always ask before rolling out Helm changes beyond dev.** Even if the user wants all four code phases, still apply Helm env vars to dev-only first, validate Phase 1 there, then explicitly ask before copying those changes to preprod and prod. This prevents accidental environment-wide rollouts.
- **Telemetry must initialise before logger use (PR #778 pattern).** If a telemetry bootstrap file imports the app logger and logs during shutdown, that import order can suppress or break telemetry — remove the logger dependency from telemetry bootstrap and shutdown paths.
- **Raw `applicationinsights` can be actively broken by Node 24 + Envoy, not just "unproxied."** Its own proxy handling can send requests Envoy rejects outright (403, `http1.https_url_on_plaintext_connection`). Fix by forcing it onto Node's core proxy-aware `http.Agent`/`https.Agent` (a small, single-file change — see the Telemetry subsection under Phase 3) rather than defaulting straight to a full `hmpps-azure-telemetry` migration; compare actual diff size before choosing.
- **A hidden `applicationinsights` dependency can come from a shared HMPPS lib, not the app.** Before starting a full `hmpps-azure-telemetry` migration, check whether `package.json`'s `applicationinsights` entry is only there because an older `@ministryofjustice/hmpps-prison-permissions-lib` (or similar) imports its `TelemetryClient` type for a `telemetryClient` option — a newer major version of that lib may already have dropped `applicationinsights` for a minimal structural interface, and upgrading it first removes a whole leg of `ERESOLVE` conflict before installing the new telemetry package.
- **`hmpps-azure-telemetry`'s exact-pinned `@opentelemetry/*` peers commonly clash with `@sentry/node`'s bundled OpenTelemetry stack.** Resolve with `overrides` in `package.json` forcing one version per clashing package (usually the newer one already resolved elsewhere) — check for a pre-existing `@opentelemetry/core` override in the repo first, since this is a repeatable, accepted pattern once a service has both Sentry and this telemetry lib.
- **A drifted app's existing telemetry-init call site is very likely too late in the import order for real OpenTelemetry instrumentation, even if it "worked" for raw `applicationinsights`.** Check whether telemetry init happens inside a data-layer module that loads after `express` is first imported (a common pattern: `server/index.ts` imports the app module, which imports `express`, before it imports the services/data module that calls telemetry init). Moving the telemetry *call* to the new library without also moving *where* it's invoked — to the literal first statement of the true process entry point — will silently produce incomplete instrumentation.
- **There is no span-processor equivalent for a `res.locals`-reading App Insights telemetry processor.** `hmpps-azure-telemetry` span filters/modifiers only see span name/kind/attributes/duration, never `req`/`res`. Replace a `res.locals.user`-reading processor with a middleware calling `telemetry.setSpanAttributes({...})`, placed after whichever middleware populates the data it needs.
- **A full telemetry migration needs a manual boot/shutdown smoke test, not just typecheck/lint/test.** None of those checks exercise real import-order or graceful-shutdown-flush behaviour — after `npm run build`, run `node dist/server.js` directly, confirm telemetry initialises and `/health` responds, then send `SIGTERM` and confirm a telemetry-flush log appears before the process exits.

- **`http.Agent`/`https.Agent`'s `proxyEnv` option wants the whole `process.env`, not a hand-built subset.** Passing `{ HTTP_PROXY, HTTPS_PROXY, ... }` as a narrowed object literal fails typecheck against `NodeJS.ProcessEnv` in apps that augment that global interface with their own keys — pass `process.env` itself.
- **Config field renames often need zero Helm changes.** Where `config.ts` uses a `get(envVarName, fallback)`-style helper, the env var name string is decoupled from the object's field name — renaming `domain` → `ingressUrl` or `signInClientId` → `authClientId` can be a pure internal TypeScript rename with no Helm/secret impact, as long as the `get('INGRESS_URL', ...)` argument itself is untouched. Confirm this by checking Helm values files for the actual env var name before assuming a rename requires infra changes.
- **Auth-shaped clients aren't always auth clients.** A class named `AuthenticationClient` or `manageUsersApiClient` may still be a general REST client — classify by the endpoint it calls (HMPPS Auth/token verification vs. domain API), not by its name, before deciding whether it belongs in `hmpps-auth-clients` or `hmpps-rest-client`.
- **Missing package is not a reason to fall back.** Default to installing the proxy-aware HMPPS package and reassessing risk, rather than writing custom fallback code, unless the user explicitly accepts the compatibility trade-off.
- **App-level changes alone don't fix `socket hang up` errors.** Confirm the namespace has the Cloud Platform Envoy proxy secret wired up (Step 0) — without it, code changes have no effect.
- **A "user info" API client may already be redundant.** Before migrating a client that only fetches the current user's name/roles/caseload, check whether that data is already decoded from the user's JWT elsewhere (see the `manageUsersApiClient` removal in [references/pr-437-lessons.md](references/pr-437-lessons.md)) — deleting the client can be the correct outcome, not migrating it.
- **Bundled reference snippets can go stale.** `references/rest-client-migration-pattern.md` is a snapshot; prefer reading `hmpps-typescript-lib`/`hmpps-template-typescript` directly (sibling checkout or `gh api`) whenever precision matters, per Step 0.
- **Don't run phases back-to-back without a checkpoint.** Even if the user asked for "all four phases," still pause after each one to run validation and offer a natural commit boundary — a single mega-diff defeats the purpose of phasing.
- **Phase 3 is where scope creep is most likely.** It's tempting to "tidy up while you're in there" — resist rewriting unrelated code; keep the diff explainable as exactly the structural cleanup described in that phase.
- **`@ministryofjustice/hmpps-rest-client`'s `SanitisedError` uses `.responseStatus`, not `.status`.** Many drifted services have a local `SanitisedError` type with a `.status` field, and production code (route/service error handling) and tests often check `error.status`. Migrating to the library's `RestClient` silently changes this to `.responseStatus`, which breaks any code that reads `.status` on errors bubbling up from a migrated API client — this is a real behavioural change, not just a typing issue. After migrating clients in Phase 1, grep the whole app (not just tests) for `.status` reads on caught/thrown errors and update the ones that originate from migrated API clients to `.responseStatus`. Do this as part of Phase 1 validation, not as an afterthought.
- **The global Express error handler often needs to support both error shapes at once.** A top-level `errorHandler.ts` typically receives both `http-errors`-style errors (which use `.status`, e.g. from `createError.Conflict()` or unmatched-route 404s) and, once Phase 1 lands, `SanitisedError`s from migrated API clients (which use `.responseStatus`). Don't blindly rewrite `.status` to `.responseStatus` here — check both (for example `error.status ?? error.responseStatus`) so existing `http-errors` usage elsewhere in the app keeps working.
- **Tests that mock errors with `http-errors` (`createError.Conflict()`, `new BadRequest()`, etc.) as a stand-in for "an API error with this status code" need updating too.** These mocks only set `.status`, which matched the old local `SanitisedError.status` by coincidence. After migrating to `hmpps-rest-client`, such tests silently stop exercising the intended branch (e.g. a 409-duplicate-record redirect) because the code now checks `.responseStatus`. Fix by adding the field the production code actually checks, for example `Object.assign(createError.Conflict(), { responseStatus: 409 })`, rather than switching the mock to a different error factory.
- **`RestClient.stream()` has no `errorHandler` param — only `errorLogger`.** If the old client had custom fallback behaviour on `stream()` (for example returning a placeholder image on a 404), it cannot be replicated via a `handleError`-style callback; wrap the `stream()` call in try/catch and inspect `(error as SanitisedError).responseStatus` instead.
- **`https-proxy-agent` v6+ is ESM-only (`"type": "module"`) and breaks Jest under `ts-jest`/CommonJS.** When implementing the SQS proxy-aware fallback pattern (or anything else importing `https-proxy-agent` directly), pin to `^7.0.0` — the last version published before the ESM-only switch — even if "upgrade to latest" was chosen in Step 2. Installing the latest major will typecheck and lint fine but fail every test file that transitively imports it, with an error like `Cannot use import statement outside a module` pointing at `https-proxy-agent/dist/index.js`. This is a documented exception to "always take the latest published version."
- **A targeted `npm install <package>@<version>` can silently prune unrelated optional/platform-specific packages from `package-lock.json`** (observed with `sass-embedded-*` variants when only changing `https-proxy-agent`'s version, and recurring on a later `hmpps-azure-telemetry` migration in the same repo after a targeted `npm uninstall`/`npm install` sequence for an unrelated package swap), which then fails CI with `npm ci` errors like `Missing: sass-embedded-<platform>@<version> from lock file` even though `npm install` and local tests passed. **Critically, a same-platform `npm ci` against the existing lock file will not catch this** — `npm ci` only needs the entries relevant to your own machine's OS/arch, so it happily succeeds locally on macOS/arm even when the Linux-only entries CI needs have been pruned. The only reliable local check is deleting `package-lock.json` itself (not just `node_modules`) and regenerating it with a full, argument-less `npm install`, then running `npm ci` against the fresh lock file — see the Phase checkpoint pattern above. After any dependency version change, diff the lockfile's `packages` map (added/removed keys, not just line count) to confirm only expected packages moved.
- **Phase 1's domain API clients typing against `hmpps-rest-client`'s structural `AuthenticationClient` interface (not a concrete class) is what makes Phase 2 a clean swap.** If Phase 1 was done correctly, migrated clients accept anything shaped like `{ getToken(username?): Promise<string> }`, so replacing the Phase 1 placeholder auth adapter with the library's real `AuthenticationClient` in Phase 2 should require zero changes to those client files — if it doesn't, that's a sign Phase 1 typed against a concrete class instead of the interface and should be corrected.
- **`VerificationClient.verifyToken()` is not a drop-in replacement for a local token verifier function.** It takes the library's own `AuthenticatedRequest` type, not a plain Express `Request`, so the app's own authentication middleware wrapper (whatever calls the token verifier — often named something like `authenticationMiddleware`) usually needs its verifier type updated too, with a cast at the call site (`request as unknown as AuthenticatedRequest`). Check `hmpps-template-typescript`'s `setUpAuthentication.ts` for the exact current pattern rather than assuming the old and new verifier signatures line up.
- **A "bespoke token store" may be doing double duty as a generic cache elsewhere in the app**, unrelated to auth (for example a reference-data cache reusing the same `TokenStore` interface for its key/TTL shape). Grep all importers of `tokenStore/*.ts` files before deleting them in Phase 2 — only remove the auth-specific usage if something else genuinely depends on the same files for a different purpose, and say so explicitly in the phase summary.
- **Once a shared `AuthenticationClient` instance exists, look for other constructors elsewhere in the app building their own separate instance just to reuse its token store** (a common pattern: a permissions/authorisation library config wanting its own `authenticationClient` option). Passing the same shared instance through is simpler and avoids duplicate token acquisition/caching — check for this explicitly once Phase 2's `AuthenticationClient` is wired up in `server/data/index.ts`.
- **Removing one legacy module can leave another one dead.** For example, a bespoke `sanitisedError.ts` helper may have existed solely to support the old `tokenVerification.ts`; once that's replaced with `VerificationClient`, grep for remaining usages of any helpers it imported before considering Phase 2 complete, and remove genuinely dead code as part of the same phase rather than leaving it to accumulate.
