# `new SQSClient` migration pattern

A directly-constructed `new SQSClient(...)` (from `@aws-sdk/client-sqs`) does not read
`HTTP_PROXY`/`HTTPS_PROXY` env vars — like `superagent` and `agentkeepalive`, it needs an explicit
proxy-aware request handler. This is commonly found in a client wired up to the HMPPS Audit
service (for example `auditClient.ts`/`HmppsAuditClient`), but can appear anywhere an app talks to
SQS directly.

**For audit traffic, the fix is always to adopt `@ministryofjustice/hmpps-audit-client`
(`AuditClient`) — never the local `NodeHttpHandler`/`HttpsProxyAgent` fallback.** That package is
only proxy-aware from **major version 2.0** onwards (the proxy fix landed via
[hmpps-typescript-lib PR #211](https://github.com/ministryofjustice/hmpps-typescript-lib/pull/211/changes#diff-c97f5f11e1acec8acf9b34ed775ddc72fd14273edabd7508e4a8e0945283c09aL79));
versions before `2.0` construct `SQSClient` without proxy support, so simply having the dependency
installed isn't enough — the installed version must be `2.0.0-beta.1` or later. A concrete example
of the full migration (config, DI wiring, service, and tests) is
[hmpps-contacts-ui PR #851](https://github.com/ministryofjustice/hmpps-contacts-ui/pull/851).

The local fallback pattern below is now only for **non-audit** SQS traffic — SQS queues unrelated
to the HMPPS Audit service, where no shared proxy-aware client package exists.

---

## Decision tree

1. **Does the `new SQSClient` usage relate to audit / the HMPPS Audit service?**
   Check the surrounding client name (`auditClient`, `HmppsAuditClient`) and whether it publishes
   events to an audit queue. If it's unclear, ask the user rather than guessing.

2. **If it relates to audit — always migrate to `@ministryofjustice/hmpps-audit-client`, at a version `>= 2.0.0-beta.1`.**
   Check the versions actually published to npm first (`npm view @ministryofjustice/hmpps-audit-client versions`), since guidance can go stale:
   - `2.0.0-beta.1` is the first proxy-aware release. As of writing it is **not** the npm `latest`
     dist-tag (`1.1.3` is), so it must be installed by pinning the exact version, for example
     `npm install @ministryofjustice/hmpps-audit-client@2.0.0-beta.1` — a plain
     `npm install @ministryofjustice/hmpps-audit-client` (or "upgrade to latest") will silently
     install the older, non-proxy-aware `1.x` line.
   - **Prefer a full (non-beta) `2.x` release over the beta if one has since been published** —
     re-check `npm view @ministryofjustice/hmpps-audit-client versions` and use the newest proper
     `2.x` release rather than staying on `2.0.0-beta.1` once that exists.
   - Do not fall back to the local `NodeHttpHandler`/`HttpsProxyAgent` pattern for audit traffic
     just because upgrading is extra work — the shared package is always the right answer here, it
     is only a question of which `>= 2.0` version to pin.
   - Migrate the constructor/import shape to match the installed package (verify against its own
     `README`/type declarations rather than assuming — the shape has changed across majors). See
     [hmpps-contacts-ui PR #851](https://github.com/ministryofjustice/hmpps-contacts-ui/pull/851)
     for a worked example: `import { AuditClient } from '@ministryofjustice/hmpps-audit-client'`,
     constructed as `new AuditClient(config.sqs.audit, logger)` and passed into services in place
     of the old local `HmppsAuditClient`.
   - Remove the app's local `SQSClient`/`HmppsAuditClient` construction, any bespoke
     proxy-handling code for it, and now-unused direct dependencies on `@aws-sdk/client-sqs` /
     `aws-sdk-client-mock` once the import is wired up (check nothing else in the app still needs
     them for a genuinely separate, non-audit queue).

3. **If it's unrelated to audit:** apply the fallback pattern below directly in the target repo,
   scoped to the file that constructs the `SQSClient`.

---

## Fallback pattern (non-audit SQS only — apply directly in the target repo)

Use this only for SQS traffic that has nothing to do with the HMPPS Audit service. Audit traffic
must use `@ministryofjustice/hmpps-audit-client` `>= 2.0.0-beta.1` instead (see decision tree
above), never this fallback.

This is the same shape that was added to `hmpps-typescript-lib`'s `audit-client` package to make it
proxy-aware — replicate it locally for other SQS destinations. Requires
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
