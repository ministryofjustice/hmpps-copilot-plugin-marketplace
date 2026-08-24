---
name: document-business-logic
description: >
  Write human-readable documentation of business logic for non-technical stakeholders
  (policy leads, product, auditors). Use when asked to: document a service's business
  rules, create a plain-English doc in /docs, or fix DocsChangeTrackingTest failures
  caused by code drift.
---

# Documenting business logic for non-technical readers

Some HMPPS services implement business or policy rules significant enough to warrant plain-English explanation for non-technical readers — not just code comments. Examples exist in services like create-and-vary-a-licence-api:

- `docs/eligibility.md` — documents `EligibilityService.kt`
- `docs/licence-start-date.md` — documents `ReleaseDateService.kt`

Freshness of these docs is enforced automatically by `DocsChangeTrackingTest` against a registry file (`docs-change-tracking.yaml`) — if the source code changes, the test fails until the doc is reviewed and the registry updated. **This ensures documentation never silently drifts out of sync.**

## When to use this skill

Use this skill when asked to:

- Document significant business rules or policy logic from a service/class
- Create a new markdown doc under `/docs` in plain language
- Fix a failing `DocsChangeTrackingTest` because source code has drifted from its documentation
- Update or refresh an existing business logic document

---

## Step 1: Decide what to document and read the source first

Identify the class or service that implements the business rule. Read it fully — don't paraphrase from memory or tests. Look especially for:

- **Named constants/config values** that represent rules (e.g. "3 working days", "28 days") — quote the actual default values, note if they're configurable via `@Value`
- **Branching logic** representing distinct real-world scenarios (licence kinds, eligibility routes, edge cases) — each branch usually deserves its own section
- **Fallback/default behaviour** when data is missing, and anything logged as a "data quality issue" — these are important enough to call out
- **Helper/private functions** encoding a sub-rule (e.g. "move to last working day") — worth their own short section if reused

Create `docs/<kebab-case-topic>.md` (match the source concept, not the class name). For example:
- ✅ `licence-start-date.md` (not `release-date-service.md`)
- ✅ `eligibility.md`
- ✅ `sentence-date-updates.md`

## Step 2: Write the document structure

Every doc must start with this exact blockquote (adjust the topic):

```markdown
> This document explains, in plain language, how the system <does this thing>.
> It is aimed at non-technical readers.
>
> This document is checked automatically for staleness: if a developer changes
> the underlying <topic> logic in the code, an automated test will fail until
> someone reviews this document and confirms it's still accurate (or updates it).
> See `docs-change-tracking.yaml` at the root of the repository if you want to
> understand how that check works.
```

Then structure the rest:

1. **"What this is for"** — one short paragraph or bullet list framing why this logic exists and what decision it drives. Restate the "so what", not just "what".

2. **Glossary of key terms/dates** — bullet list with bold term and plain-English definition. Include every domain term a reader would otherwise need to look up (e.g. "conditional release date (CRD)", "post-recall release date (PRRD)").

3. **One section per rule/scenario** — usually one per enum value, licence kind, or decision branch. Use `##`/`###` headings mirroring the code's own branching. State conditions as bullet lists of "all of the following must be true" where the code uses `&&` or `when` chains.

4. **Edge cases / defaults** — a closing section calling out fallback behaviour, data-quality issues, and what the system defaults to and why (usually "defaults to not blocking, to avoid wrongly penalising for missing data" — but confirm against actual code).

5. **"How it all comes together"** (if multi-step) — explain priority order if one exists (see `eligibility.md`'s "How the final decision is made").

### Tone rules (most important)

- **Write for someone with zero familiarity** with the codebase, Kotlin, or Spring — no class names, method names, variable names, or code snippets
- **Prefer plain nouns/verbs** over jargon: "the date someone is due to be released", not "CRD field". Introduce the abbreviation (e.g. "conditional release date (CRD)") once in the glossary, then it's fine to reuse sparingly
- **Use short paragraphs and bullet lists** over long prose; use tables for fixed enumerable sets of options
- **State rules as plain conditions** ("if X and Y, then Z") rather than describing control flow
- **Don't editorialize** or add caveats not in the code (no "this seems inefficient") — be a faithful, neutral mirror of current logic
- **Bold sparingly** — only for genuinely key terms/dates/outcomes on first use in a section
- **Avoid absolute claims** not guaranteed by code (e.g. don't say "always" if there's a config flag that can disable it)

---

## Step 3: Register the doc in `docs-change-tracking.yaml` (mandatory)

Every doc documented by this process must have an entry in `docs-change-tracking.yaml` at the repo root, or the test will never run for it.

Add an entry:

```yaml
- id: <kebab-case-id>
  description: "<one-line description of the business logic covered>"
  doc: docs/<your-doc>.md
  sources:
    - src/main/kotlin/uk/gov/justice/digital/hmpps/<service>/service/<Path>.kt
  hash: <computed-below>
```

**Computing the hash:**

The `hash` must be computed exactly as `DocsChangeTrackingTest` computes it — an MD5 digest built from each resolved source file (sorted by repo-relative path): the UTF-8 bytes of the path + a single null byte + the raw file bytes.

Use the Python one-liner provided in [references/compute-hash.md](references/compute-hash.md), or run the test and copy the hash from the failure message (faster if unsure).

For a `sources` entry that's a directory, extend the paths list with every `*.kt` file under it (sorted), not just the directory path itself.

**Validate the entry:**

```bash
./gradlew test --tests "*DocsChangeTrackingTest*"
```

Every entry in the registry runs as its own dynamic test (named after its `id`). Confirm the new one appears and passes, alongside all pre-existing entries.

---

## Step 4: Keeping docs fresh (for future code changes)

When someone later changes the source of an already-documented rule:

1. The test will fail with the newly computed hash
2. Re-read the changed source code
3. Update the corresponding `docs/*.md` file to reflect new behaviour (same tone rules above)
4. Update only the `hash` field in `docs-change-tracking.yaml` to the value reported in the test failure
5. Re-run the test to confirm it's green
6. **Never update the hash without actually reviewing/updating the doc content first** — that defeats the whole purpose

---

## Reference materials

See the bundled examples in this skill for:

- `DocsChangeTrackingTest.kt` — the actual Kotlin test implementation
- `docs-change-tracking.yaml` — a complete registry example with multiple entries
- `compute-hash.md` — Python one-liner to compute the MD5 hash
