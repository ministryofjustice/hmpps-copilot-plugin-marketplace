# Lessons from a real migration: hmpps-visits-internal-admin-ui PR #437

[PR #437](https://github.com/ministryofjustice/hmpps-visits-internal-admin-ui/pull/437) is a
Copilot-assisted migration of a drifted HMPPS TypeScript service to the current
`hmpps-template-typescript` pattern, described in its own PR body as making the service
proxy-aware as a side effect of aligning with the template. Use these lessons to anticipate
issues and set expectations before and during a migration — they go beyond what's obvious from
reading the library APIs alone.

## What was deleted entirely, not just refactored

These files were deleted outright because the HMPPS libraries now own that responsibility.
Don't try to "modernise" them in place — remove them once the replacement is wired up:

- `server/data/restClient.ts` — replaced by `RestClient` from `@ministryofjustice/hmpps-rest-client`
- `server/data/hmppsAuthClient.ts` — replaced by `AuthenticationClient` from `@ministryofjustice/hmpps-auth-clients`
- `server/data/tokenVerification.ts` — replaced by `VerificationClient` from `@ministryofjustice/hmpps-auth-clients`
- `server/data/tokenStore/*.ts` (interface + in-memory + Redis implementations, plus their tests)
  — replaced by `InMemoryTokenStore`/`RedisTokenStore` exported from `@ministryofjustice/hmpps-auth-clients`

If you find equivalents of these files in a target repo, treat them as prime deletion candidates
once the library-based replacement is in place — not as code to patch.

## `manageUsersApiClient` was removed, not migrated

The service had a `manageUsersApiClient` used only to fetch the current user's display name and
roles. It was deleted entirely rather than mapped onto `hmpps-auth-clients`, because that
information was already available by decoding the user's JWT in `setUpCurrentUser.ts` — no API
call was needed at all.

**Lesson:** before migrating a "manage users" style API client, check whether the fields it
fetches (name, roles, active caseload, etc.) are already present as JWT claims decoded elsewhere
in the app (for example in a `populateCurrentUser`/`setUpCurrentUser` middleware or the
`HmppsUser` type). If so, prefer removing the API call rather than migrating it — this is a
bigger simplification than a like-for-like migration and is easy to miss.

## Config renames that ripple outward

Adopting `AuthenticationClient` requires config shape changes that touch call sites beyond
`config.ts` itself:

- `apiClientId` / `apiClientSecret` → `authClientId` / `authClientSecret`
- `domain` → `ingressUrl`
- Local `AgentConfig`/`ApiConfig` definitions removed in favour of importing `AgentConfig` from
  `@ministryofjustice/hmpps-rest-client`

**Lesson:** search the whole repo for the old property names (`apiClientId`, `config.domain`,
etc.) after renaming in `config.ts` — `setUpAuthentication.ts` and any auth URL construction are
easy to miss and will silently use `undefined` if not updated.

## `ENVIRONMENT_NAME` no longer needs app-side translation

The app previously had a `translateEnvironment()` function mapping `preprod` → `PRE-PRODUCTION`,
`prod` → `''`, and uppercasing everything else. This was deleted; the Helm values files for each
environment now set the already-correct display string directly (for example
`ENVIRONMENT_NAME: PRE-PRODUCTION` in `values-preprod.yaml`, and no value at all for prod).

**Lesson:** if a target app has similar app-side string-translation logic for environment name
(or other Helm-supplied values), consider pushing the translation into the per-environment Helm
values file instead of keeping code-side branching — check `hmpps-template-typescript`'s
`values-*.yaml` files for the expected literal values per environment.

## `handleNotFoundErrorAsNull` replaces try/catch-on-404

Several client methods previously wrapped a call in try/catch and returned `null` on
`error.status === 404`. The migrated version uses a small shared `errorHandler` function passed
to `this.get(...)` (see `references/rest-client-migration-pattern.md`). Prefer this shared helper
over repeating the try/catch pattern in every client.

## A `NO_HTTPS` escape hatch was added

`config.ts` changed `https: production` to `https: process.env.NO_HTTPS === 'true' ? false : production`.
This is unrelated to proxy-awareness itself, but shows a pattern worth recognising: small,
narrowly-scoped environment escape hatches added during a migration to unblock local/feature-env
testing. Don't be surprised to see (or need) similar small additions — call them out explicitly
in the migration summary rather than folding them silently into the main change.

## The migration authored a `.github/copilot-instructions.md`

As part of the same PR, a new `.github/copilot-instructions.md` was added, documenting the
service's architecture (controller → service → API client layering), build/test/lint commands,
auth/token handling, and the "adding a new feature area" checklist — effectively locking in the
now-current patterns for future Copilot-assisted changes to that repo.

**Lesson:** after completing a proxy-aware migration (Step 7 in `SKILL.md`), offer to write or
update a `.github/copilot-instructions.md` for the target repo summarising the new client/auth
patterns, so future changes (by Copilot or humans) don't drift back to the old approach. Only do
this if the user agrees — see Step 8.

## Housekeeping seen alongside the migration

- A `lint-fix` npm script (`eslint . --cache --max-warnings 0 --fix`) was added and used before
  the final `lint` check — if the target repo lacks a fast auto-fix script, consider suggesting
  one rather than hand-fixing formatting issues.
- Helm values had a stray blank line and an unused `MANAGE_USERS_API_URL` entry removed — cleaning
  up now-dead env vars for deleted clients is part of a complete migration, not an afterthought.
