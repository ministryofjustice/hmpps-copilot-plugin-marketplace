# Make TypeScript Proxy-Aware Skill

A GitHub Copilot skill that helps you make HMPPS TypeScript services proxy-aware for Cloud Platform egress controls — **and**, because most of that benefit actually comes from aligning with the current `hmpps-template-typescript` patterns rather than a narrow proxy-only fix, helps bring a drifted service's auth, data-client, config, monitoring, and telemetry layers back in line with the template too.

To keep that broader alignment reviewable, the skill delivers it as **up to four separate phases**, each ending in its own validated, committed checkpoint — not one large, hard-to-review PR.

It guides Copilot through: assess current proxy readiness and template drift, agree which phases to run and the migration strategy with you, apply each phase's code and Helm changes with its own validate/commit checkpoint, then move to the next phase only once you're ready.

---

## The four phases

1. **Phase 1 — Proxy-critical: outbound HTTP client + Helm.** Replace `superagent`/`agentkeepalive` with `@ministryofjustice/hmpps-rest-client` and add Helm proxy env vars. Fixes the proxy problem on its own — the smallest, lowest-risk, most reviewable change.
2. **Phase 2 — Auth alignment.** Replace custom `hmppsAuthClient`/`tokenVerification`/`tokenStore` modules with `@ministryofjustice/hmpps-auth-clients`.
3. **Phase 3 — Structural cleanup.** Config renames, removal of now-redundant clients (for example a `manageUsersApiClient` superseded by JWT claims), monitoring and telemetry migration. The deepest and riskiest phase — kept as small a diff as possible.
4. **Phase 4 — Docs and handoff.** Update or author `.github/copilot-instructions.md` to lock in the new patterns, and hand off to the `sync-typescript-template` skill for keeping pace with the template going forward.

You choose how far to go — Phase 1 only for a minimal proxy fix, or all four for full infrastructure alignment. Each phase ends with a commit you can review and ship before deciding whether to continue.

---

## Example usage

You can trigger this skill by asking Copilot in plain English. Here are some examples:

### Start with a guided conversation (recommended)

```
Make this service proxy-aware for Cloud Platform egress controls.
Start by assessing the repo and then ask me any decisions you need, one question at a time.
Do not make edits until I confirm your proposed plan.
```

This keeps the user experience simple: Copilot does the discovery work, presents options — including which phases to run — asks follow-up questions, and then applies changes once approved.

### Assess a service before making changes

```
Use the make-typescript-proxy-aware skill for this repository.
Run Step 0 and Step 1 only and do not edit files yet.
```

```
Check this service for proxy-unaware HTTP usage and template drift, and group findings by which phase they belong to.
```

```
Find any superagent or agentkeepalive usage that could break after Envoy proxy rollout.
```

Copilot will inspect the repository and summarise what needs to change before any edits are made.

---

### Choose your scope: proxy-only or full alignment

```
I only want proxy-awareness for now — run Phase 1 only, then stop.
```

```
Go for full template alignment across all four phases, pausing for my review after each one.
```

Copilot will confirm which phases you want and the migration strategy for each before it edits anything.

---

### Apply a phase

```
Apply Phase 1 now: migrate outbound HTTP clients and add Helm proxy env configuration.
```

```
Phase 1 looks good and is merged — go ahead with Phase 2 (auth alignment).
```

```
Use fallback mode for risky areas in this phase, keep existing behaviour where possible, and document each fallback decision.
```

After each phase, Copilot validates, summarises, suggests a phase-scoped commit message, and asks whether to continue — it will not silently roll straight through all four phases into one diff.

---

### Validate after a phase

```
Run validation for this phase and report failures.
```

Each phase validates with:

```bash
npm run typecheck && npm run lint && npm run test
```

If checks fail, Copilot should fix relevant issues and re-run validation before offering the commit.

---

## Typical migration scope

This skill is designed to help with:

- Replacing proxy-unaware outbound HTTP patterns (Phase 1)
- Moving to `@ministryofjustice/hmpps-rest-client` for API clients where practical (Phase 1)
- Moving auth flows to `@ministryofjustice/hmpps-auth-clients` where practical (Phase 2)
- Config renames and removing clients made redundant by the above, such as a JWT-superseded `manageUsersApiClient` (Phase 3)
- Aligning health checks with `@ministryofjustice/hmpps-monitoring` where practical (Phase 3)
- Aligning telemetry with `@ministryofjustice/hmpps-azure-telemetry` (Phase 3)
- Applying Helm proxy env vars and namespace secret wiring (Phase 1)
- Authoring/updating `.github/copilot-instructions.md` to lock in the new patterns (Phase 4)

**Out of scope:** business logic, routes, controllers' domain behaviour, and views — even where `hmpps-template-typescript` differs there too. For broader template alignment beyond infrastructure, use the `sync-typescript-template` skill to apply specific upstream template changes on demand.

---

## Notes

- **Skill first, then edits.** Start with assessment (Step 0 and Step 1) so changes are deliberate.
- **Choose your depth.** Phase 1 alone is a minimal proxy fix; all four phases is full infrastructure alignment. You decide in Step 2.
- **Choose your risk profile.** You can prefer full migration or fallback changes that keep behaviour close to current code, per phase.
- **Staged rollout is supported.** You can apply Helm changes in dev first, then preprod, then prod.
- **Platform wiring still matters.** App changes alone are not enough if Cloud Platform egress proxy secrets are not available in the namespace.
- **Each phase is a separate commit.** Copilot won't move to the next phase without your go-ahead — review and ship one phase at a time rather than getting one large PR.
- **Bundled reference material.** The skill includes `references/rest-client-migration-pattern.md` (the current canonical `hmpps-template-typescript` client/auth/config pattern) and `references/pr-437-lessons.md` (concrete lessons from a real-world migration, [PR #437](https://github.com/ministryofjustice/hmpps-visits-internal-admin-ui/pull/437), mapped onto the four phases), so Copilot doesn't have to guess library shapes from memory.
- **Checking out reference repos helps.** If you have `hmpps-typescript-lib` and/or `hmpps-template-typescript` cloned as sibling directories next to your target repo, Copilot will use them directly as the freshest source of truth instead of the bundled snapshots — worth doing if you'll use this skill repeatedly.
- **After you've caught up, use `sync-typescript-template`.** Once all chosen phases are done, that's the right tool for staying current with future template changes — this skill is for the initial catch-up, not ongoing maintenance.
