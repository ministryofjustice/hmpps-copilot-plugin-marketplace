# Make TypeScript Proxy-Aware Skill

A GitHub Copilot skill that helps you make HMPPS TypeScript services proxy-aware for Cloud Platform egress controls.

It guides Copilot through a low-risk migration workflow: assess current proxy readiness, agree migration choices with you, apply code and Helm changes, then validate the result.

---

## Example usage

You can trigger this skill by asking Copilot in plain English. Here are some examples:

### Start with a guided conversation (recommended)

```
Make this service proxy-aware for Cloud Platform egress controls.
Start by assessing the repo and then ask me any decisions you need, one question at a time.
Do not make edits until I confirm your proposed plan.
```

This keeps the user experience simple: Copilot does the discovery work, presents options, asks follow-up questions, and then applies changes once approved.

### Assess a service before making changes

```
Use the make-typescript-proxy-aware skill for this repository.
Run Step 0 and Step 1 only and do not edit files yet.
```

```
Check this service for proxy-unaware HTTP usage and group findings into must-fix, recommended, and optional.
```

```
Find any superagent or agentkeepalive usage that could break after Envoy proxy rollout.
```

Copilot will inspect the repository and summarise what needs to change before any edits are made.

---

### Confirm migration choices

```
Proceed with Step 2.
Use latest shared library versions, stage Helm env vars dev then preprod then prod, and keep code changes low risk.
```

```
Use minimum proxy-aware versions only, apply Helm vars to all environments, and do a full migration to HMPPS libraries where possible.
```

Copilot will confirm your selected strategy before it edits files.

---

### Apply proxy-aware migration

```
Apply the agreed make-typescript-proxy-aware plan now.
Migrate clients, update telemetry and monitoring where needed, and add Helm proxy env configuration.
```

```
Use fallback mode for risky areas, keep existing behaviour where possible, and document each fallback decision.
```

Copilot will apply changes and then summarise:

- Which files changed
- Which migrations were completed
- Which fallback decisions were used
- Any remaining risks or follow-up tasks

---

### Validate after migration

```
Run validation for this migration and report failures.
```

The skill validates with:

```bash
npm run typecheck && npm run lint && npm run test
```

If checks fail, Copilot should fix relevant issues and re-run validation.

---

## Typical migration scope

This skill is designed to help with:

- Replacing proxy-unaware outbound HTTP patterns
- Moving to `@ministryofjustice/hmpps-rest-client` for API clients where practical
- Moving auth flows to `@ministryofjustice/hmpps-auth-clients` where practical
- Aligning health checks with `@ministryofjustice/hmpps-monitoring` where practical
- Aligning telemetry with `@ministryofjustice/hmpps-azure-telemetry`
- Applying Helm proxy env vars and namespace secret wiring

---

## Notes

- **Skill first, then edits.** Start with assessment (Step 0 and Step 1) so changes are deliberate.
- **Choose your risk profile.** You can prefer full migration or fallback changes that keep behaviour close to current code.
- **Staged rollout is supported.** You can apply Helm changes in dev first, then preprod, then prod.
- **Platform wiring still matters.** App changes alone are not enough if Cloud Platform egress proxy secrets are not available in the namespace.
