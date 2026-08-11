# Canonical rest-client migration pattern

This is the current canonical pattern used by `hmpps-template-typescript` for a proxy-aware
outbound HTTP client, auth token handling, and token verification. It is quoted directly from
the template repository so you don't have to guess the shape of the HMPPS libraries.

This snapshot can go stale as the libraries evolve. If `hmpps-template-typescript` is checked
out locally (see Step 0 in `SKILL.md`), read the live files at the paths below instead of
relying on this file. Otherwise, fetch the current version directly, for example:

```bash
gh api repos/ministryofjustice/hmpps-template-typescript/contents/server/data/exampleApiClient.ts --jq '.content' | base64 -d
```

---

## API client (`server/data/exampleApiClient.ts`)

Extend `RestClient` from `@ministryofjustice/hmpps-rest-client`. Call `this.get/post/put/delete`
with `asSystem()` (or `asUser(token)`, or `asSystem(username)`) as the second argument — do not
construct `superagent` requests or `agentkeepalive` agents directly.

```typescript
import { RestClient, asSystem } from '@ministryofjustice/hmpps-rest-client'
import type { AuthenticationClient } from '@ministryofjustice/hmpps-auth-clients'
import config from '../config'
import logger from '../../logger'

export default class ExampleApiClient extends RestClient {
  constructor(authenticationClient: AuthenticationClient) {
    super('Example API', config.apis.exampleApi, logger, authenticationClient)
  }

  // System token, not tied to a specific user — for service-to-service calls
  getCurrentTime() {
    return this.get<string>({ path: '/example/time' }, asSystem())
  }

  // User's own token — use asUser(token) instead of asSystem() when authorization
  // depends on the calling user's roles/permissions:
  //   import { asUser } from '@ministryofjustice/hmpps-rest-client'
  //   getCurrentTime(token: string) {
  //     return this.get({ path: '/example/time' }, asUser(token))
  //   }

  // System token attributed to a specific user (for audit trails) — asSystem(username):
  //   getCurrentTime(username: string) {
  //     return this.get({ path: '/example/time' }, asSystem(username))
  //   }
}
```

### Handling 404s as `null`

Use a typed `errorHandler` rather than a try/catch around `error.status === 404` (a pattern seen
in older `RestClient` implementations):

```typescript
import { SanitisedError } from '@ministryofjustice/hmpps-rest-client'

const handleNotFoundErrorAsNull = <ErrorData>(
  _path: string,
  _verb: string,
  error: SanitisedError<ErrorData>,
): null => {
  if (error.responseStatus === 404) {
    return null
  }
  throw error
}

export default handleNotFoundErrorAsNull
```

```typescript
async getThing(id: string): Promise<Thing | null> {
  return this.get<Thing | null>({ path: `/things/${id}`, errorHandler: handleNotFoundErrorAsNull }, asSystem())
}
```

**`stream()` has no `errorHandler` param — only `errorLogger`.** If the old client had custom
fallback behaviour on a streamed response (for example returning a placeholder image on a 404),
it can't be replicated via a `handleError`-style callback the way `get`/`post` can. Wrap the
`stream()` call in a try/catch instead and inspect `(error as SanitisedError).responseStatus`.

### `.status` → `.responseStatus`: check the whole app, not just the client file

The library's `SanitisedError` exposes `.responseStatus`, whereas many drifted services have an
older local `SanitisedError` type with a `.status` field that the same app's routes, services, and
tests read directly (for example `if (error.status === 409) { ... }` to detect a duplicate-record
conflict, or a global Express `errorHandler.ts` checking `error.status === 401`). Swapping in the
library's `RestClient` silently changes this field name for every error that bubbles up from a
migrated client — this is a real behavioural change, not just a type error, and `tsc` will only
catch it where the error type is explicitly typed as the old `SanitisedError`.

After migrating clients in Phase 1:

1. Grep the whole app (routes, services, middleware — not just the client files) for `.status`
   reads on caught/thrown errors, and update the ones that originate from migrated API clients to
   `.responseStatus`.
2. Treat the top-level Express error handler specially: it usually receives both `http-errors`
   -style errors (which use `.status`, e.g. from `createError.Conflict()` or an unmatched route)
   and, post-migration, `SanitisedError`s from migrated clients (which use `.responseStatus`).
   Check both, for example `error.status ?? error.responseStatus`, rather than rewriting it to
   `.responseStatus` only.
3. Update any tests that mock errors via `http-errors` factories (`createError.Conflict()`, `new
   BadRequest()`, etc.) as a stand-in for "an API error with this status code" — these only set
   `.status`, so after the migration they silently stop exercising the intended branch unless the
   mock also carries `.responseStatus`, for example:
   ```typescript
   contactsService.updateContactIdentity.mockRejectedValue(
     Object.assign(createError.Conflict(), { responseStatus: 409 }),
   )
   ```

---

## Wiring (`server/data/index.ts`)

`AuthenticationClient`, `InMemoryTokenStore`, and `RedisTokenStore` all come from
`@ministryofjustice/hmpps-auth-clients` — do not keep or write bespoke `tokenStore/*.ts` files
once this package is in use; the library owns token storage and caching.

```typescript
import { AuthenticationClient, InMemoryTokenStore, RedisTokenStore } from '@ministryofjustice/hmpps-auth-clients'
import { createRedisClient } from './redisClient'
import config from '../config'
import ExampleApiClient from './exampleApiClient'
import applicationInfoSupplier from '../applicationInfo'
import logger from '../../logger'

const applicationInfo = applicationInfoSupplier()

export const dataAccess = () => {
  const hmppsAuthClient = new AuthenticationClient(
    config.apis.hmppsAuth,
    logger,
    config.redis.enabled ? new RedisTokenStore(createRedisClient()) : new InMemoryTokenStore(),
  )

  return {
    applicationInfo,
    hmppsAuthClient,
    exampleApiClient: new ExampleApiClient(hmppsAuthClient),
  }
}

export type DataAccess = ReturnType<typeof dataAccess>
```

Every domain API client is constructed with the single shared `hmppsAuthClient` instance — there
is no separate manual `getSystemClientToken` implementation to maintain.

---

## Token verification middleware (`server/middleware/setUpAuthentication.ts`)

`VerificationClient` from `@ministryofjustice/hmpps-auth-clients` replaces a hand-rolled
`tokenVerification.ts` module that calls the token verification API directly with `superagent`:

```typescript
import { VerificationClient, AuthenticatedRequest } from '@ministryofjustice/hmpps-auth-clients'
import config from '../config'
import logger from '../../logger'

export default function setupAuthentication() {
  const router = Router()
  const tokenVerificationClient = new VerificationClient(config.apis.tokenVerification, logger)

  // ...passport wiring...

  router.use(async (req, res, next) => {
    if (req.isAuthenticated() && (await tokenVerificationClient.verifyToken(req as unknown as AuthenticatedRequest))) {
      return next()
    }
    req.session.returnTo = req.originalUrl
    return res.redirect('/sign-in')
  })

  return router
}
```

**Drifted services often split this across separate files** (for example a `server/authentication/auth.ts` holding the passport strategy and a generic `authenticationMiddleware(tokenVerifier)` wrapper, plus a `server/middleware/setUpCurrentUser.ts` that supplies the verifier), rather than the template's single merged `setUpAuthentication.ts`. In that shape:

- Update the local `TokenVerifier` type (wherever it's currently imported from a bespoke `tokenVerification.ts`) to `(request: AuthenticatedRequest) => Promise<boolean>`, importing `AuthenticatedRequest` from `@ministryofjustice/hmpps-auth-clients` instead.
- Construct the `VerificationClient` where the router is built (for example in `setUpCurrentUser.ts`) and pass `request => verificationClient.verifyToken(request)` into the existing `authenticationMiddleware` wrapper — the wrapper itself still does the `req as unknown as AuthenticatedRequest` cast before calling the verifier.
- This is a smaller, lower-risk change than restructuring the files to match the template's single-file layout — that kind of file-layout consolidation belongs in Phase 3 (or `sync-typescript-template`) if the user wants it, not Phase 2.

---

## Config (`server/config.ts`)

Import `AgentConfig` (and, where relevant, `ApiConfig`) from `@ministryofjustice/hmpps-rest-client`
instead of defining them locally:

```typescript
import { AgentConfig } from '@ministryofjustice/hmpps-rest-client'
```

Delete any local `AgentConfig`/`ApiConfig` class or interface definitions once the import is in
place — keeping both is a common leftover that causes confusing duplicate types.

---

## Helm proxy configuration

Sourced from `hmpps-tech-docs/src/content/how-to-guides/retrofitting-egress-controls-with-envoy-proxy.md`,
this is the confirmed current pattern for TypeScript services (also shown in `SKILL.md` Step 6):

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

Minimum versions confirmed by the same doc: `@ministryofjustice/hmpps-rest-client` `2.1.0`+, and
`@ministryofjustice/hmpps-monitoring` `2.1.0`+ (this pulls in the proxy-aware rest-client
transport). `NODE_USE_ENV_PROXY` must be set even when these libraries are present — without it,
Node's built-in `undici`/`fetch`-based clients won't read the proxy env vars.
