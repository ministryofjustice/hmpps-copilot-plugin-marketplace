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
- Replace a custom `tokenVerification.ts` module with `VerificationClient`.
- Replace custom `tokenStore/*.ts` implementations (in-memory or Redis) with the `InMemoryTokenStore`/`RedisTokenStore` the library exports — do not keep bespoke token store files once this package is in use.

Treat this as a default rule unless the user explicitly requests a fallback due to compatibility risk.

For legacy clients named like `AuthenticationClient` or `manageUsersApiClient`, classify by endpoint responsibility before migration:

- If it handles HMPPS Auth or token verification responsibilities, migrate to the relevant `@ministryofjustice/hmpps-auth-clients` client.
- Do not create a new direct `hmpps-rest-client` implementation for those auth responsibilities.
- Only keep a custom `hmpps-rest-client` client where the endpoint is outside the coverage of `hmpps-auth-clients`, and explain why.

Run the **Phase checkpoint pattern** before moving on.

---

## Phase 3: Structural cleanup enabled by Phase 2

This is the deepest and riskiest phase — it's where most of PR #437's real value came from, but also where the diff can balloon. Keep each change as small and separately explainable as possible, and lean on the fallback path (below) for anything that looks too risky to do in full.

### Redundant clients

If a client only fetches current-user display data (name, roles, caseload), check first whether that data is already available from decoding the user's JWT elsewhere in the app (for example in `setUpCurrentUser`/`populateCurrentUser`). If so, prefer removing the client and its call sites entirely over migrating it — see the `manageUsersApiClient` case in [references/pr-437-lessons.md](references/pr-437-lessons.md). This kind of deletion, not just migration, is what "deeper alignment" means in practice — flag it clearly in the phase summary since it's a bigger behavioural change than a like-for-like swap.

### Config renames

Any local `AgentConfig`/`ApiConfig` type definitions in `config.ts` should be replaced with the equivalents imported from `@ministryofjustice/hmpps-rest-client`, and any config field renames this implies (for example `apiClientId` → `authClientId`, `domain` → `ingressUrl`) should be searched for and updated at every call site, not just in `config.ts` — see [references/pr-437-lessons.md](references/pr-437-lessons.md).

### Health and ping flows

If legacy custom health-check HTTP modules exist, migrate to `@ministryofjustice/hmpps-monitoring` endpoint health components. If the package is missing, install it and continue the migration rather than switching to fallback health-check HTTP code only because it's absent.

### Telemetry

Prefer `@ministryofjustice/hmpps-azure-telemetry` and ensure it initialises before instrumented modules load. If the telemetry file imports logger and logs during shutdown, apply the PR #778-equivalent fix by removing the logger dependency from telemetry bootstrap and shutdown paths.

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
- **Auth-shaped clients aren't always auth clients.** A class named `AuthenticationClient` or `manageUsersApiClient` may still be a general REST client — classify by the endpoint it calls (HMPPS Auth/token verification vs. domain API), not by its name, before deciding whether it belongs in `hmpps-auth-clients` or `hmpps-rest-client`.
- **Missing package is not a reason to fall back.** Default to installing the proxy-aware HMPPS package and reassessing risk, rather than writing custom fallback code, unless the user explicitly accepts the compatibility trade-off.
- **App-level changes alone don't fix `socket hang up` errors.** Confirm the namespace has the Cloud Platform Envoy proxy secret wired up (Step 0) — without it, code changes have no effect.
- **A "user info" API client may already be redundant.** Before migrating a client that only fetches the current user's name/roles/caseload, check whether that data is already decoded from the user's JWT elsewhere (see the `manageUsersApiClient` removal in [references/pr-437-lessons.md](references/pr-437-lessons.md)) — deleting the client can be the correct outcome, not migrating it.
- **Bundled reference snippets can go stale.** `references/rest-client-migration-pattern.md` is a snapshot; prefer reading `hmpps-typescript-lib`/`hmpps-template-typescript` directly (sibling checkout or `gh api`) whenever precision matters, per Step 0.
- **Don't run phases back-to-back without a checkpoint.** Even if the user asked for "all four phases," still pause after each one to run validation and offer a natural commit boundary — a single mega-diff defeats the purpose of phasing.
- **Phase 3 is where scope creep is most likely.** It's tempting to "tidy up while you're in there" — resist rewriting unrelated code; keep the diff explainable as exactly the structural cleanup described in that phase.
