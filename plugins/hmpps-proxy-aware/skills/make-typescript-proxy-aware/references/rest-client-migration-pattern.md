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
