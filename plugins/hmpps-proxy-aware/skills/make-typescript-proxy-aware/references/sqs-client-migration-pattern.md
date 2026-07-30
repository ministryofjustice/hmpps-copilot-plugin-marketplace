# `new SQSClient` migration pattern

A directly-constructed `new SQSClient(...)` (from `@aws-sdk/client-sqs`) does not read
`HTTP_PROXY`/`HTTPS_PROXY` env vars — like `superagent` and `agentkeepalive`, it needs an explicit
proxy-aware request handler. This is commonly found in a client wired up to the HMPPS Audit
service (for example `auditClient.ts`/`HmppsAuditClient`), but can appear anywhere an app talks to
SQS directly.

The canonical fix comes from
[hmpps-typescript-lib PR #211](https://github.com/ministryofjustice/hmpps-typescript-lib/pull/211/changes#diff-c97f5f11e1acec8acf9b34ed775ddc72fd14273edabd7508e4a8e0945283c09aL79),
which added proxy support to that library's own `audit-client` package.

---

## Decision tree

1. **Does the `new SQSClient` usage relate to audit / the HMPPS Audit service?**
   Check the surrounding client name (`auditClient`, `HmppsAuditClient`) and whether it publishes
   events to an audit queue. If it's unclear, ask the user rather than guessing.

2. **If it relates to audit — check whether `hmpps-typescript-lib` now has a published `audit-client` package** (check the `main` branch and npm, for example `npm view @ministryofjustice/hmpps-audit-client versions`, confirming the exact published package name first since it may differ):
   - **Published:** migrate the target app to depend on that package and import its `HmppsAuditClient`/equivalent instead of constructing `SQSClient` locally. Make sure the app is upgraded to at least the version that includes proxy support (the fix landed in PR #211) — check the installed version, not just that the package exists. Remove the app's local `SQSClient` construction and any bespoke proxy-handling code once the import is wired up.
   - **Not yet published:** don't block on it. Apply the local fallback pattern below directly in the target repo instead, and note in the phase summary that this can be swapped for the shared package once it's published.

3. **If it's unrelated to audit, or the shared package isn't available yet:** apply the fallback
   pattern below directly in the target repo, scoped to the file that constructs the `SQSClient`.

---

## Fallback pattern (apply directly in the target repo)

This is the same shape PR #211 added inside `hmpps-typescript-lib`'s `audit-client` package —
replicate it locally when importing the shared package isn't yet an option. Requires
`@smithy/node-http-handler` and `https-proxy-agent` as dependencies.

**Pin `https-proxy-agent` to `^7.0.0`, not the latest major.** From v6 onward `https-proxy-agent` is
published as ESM-only (`"type": "module"` in its `package.json`), which breaks Jest under `ts-jest`
(CommonJS) with an error like `Cannot use import statement outside a module` pointing at
`https-proxy-agent/dist/index.js`, even though `npm install`, `npm run build`, and `npm run
typecheck`/`lint` all succeed. This surfaces only when running tests, so don't assume the package
is fine just because the app compiles. `^7.0.0` is the last CommonJS-compatible major and is what
`hmpps-typescript-lib`'s own `audit-client` package pins to — use it here too even if the phase's
library-upgrade mode is "latest".

`proxySupport.ts` (place alongside the SQS client file, for example `server/data/helpers/proxySupport.ts`):

```typescript
import { NodeHttpHandler } from '@smithy/node-http-handler'
import { HttpsProxyAgent } from 'https-proxy-agent'

/**
 * Determines if proxy support should be enabled based on Node proxy configuration.
 *
 * Returns true when any of the following are set:
 * - NODE_USE_ENV_PROXY is '1' or 'true' (case-insensitive)
 * - NODE_OPTIONS contains '--use-env-proxy'
 * - process.execArgv includes '--use-env-proxy'
 */
export function isProxyEnabled(): boolean {
  const nodeUseEnvProxy = process.env.NODE_USE_ENV_PROXY?.toLowerCase()
  return (
    nodeUseEnvProxy === '1' ||
    nodeUseEnvProxy === 'true' ||
    process.env.NODE_OPTIONS?.includes('--use-env-proxy') ||
    process.execArgv.includes('--use-env-proxy')
  )
}

/**
 * Reads proxy configuration from environment variables (case-insensitive).
 */
export function getProxyUrl(): string | undefined {
  return process.env.HTTPS_PROXY || process.env.https_proxy || process.env.HTTP_PROXY || process.env.http_proxy
}

/**
 * Creates an SQS client request handler with proxy support if configured.
 *
 * When proxy support is enabled and a proxy is configured via environment variables, returns a
 * NodeHttpHandler configured with an HttpsProxyAgent. Otherwise returns an empty object so
 * SQSClient falls back to its default handler.
 */
export function createProxyRequestHandler(): { requestHandler?: NodeHttpHandler } {
  if (!isProxyEnabled()) {
    return {}
  }

  const proxyUrl = getProxyUrl()
  if (!proxyUrl) {
    return {}
  }

  const agent = new HttpsProxyAgent(proxyUrl)
  return {
    requestHandler: new NodeHttpHandler({
      httpsAgent: agent,
    }),
  }
}
```

Usage at the `SQSClient` construction site:

```typescript
import { SQSClient } from '@aws-sdk/client-sqs'
import { createProxyRequestHandler } from './helpers/proxySupport'

// Before:
// this.sqsClient = new SQSClient({ region: config.region, ...config.clientConfig })

// After:
this.sqsClient = new SQSClient({
  region: config.region,
  ...createProxyRequestHandler(),
  ...config.clientConfig,
})
```

Note the spread order: `createProxyRequestHandler()` comes before `config.clientConfig` so that an
explicit `requestHandler` in `clientConfig` (for example in tests) still takes precedence.

`NODE_USE_ENV_PROXY` still needs to be set via Helm (see the "Apply Helm proxy configuration"
section of Phase 1) for this to activate in deployed environments.
