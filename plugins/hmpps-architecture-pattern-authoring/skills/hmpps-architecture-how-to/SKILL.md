---
name: hmpps-architecture-how-to
description: >
  Write a human-readable HMPPS architecture how-to guide that shows a
  delivery team how to achieve a specific goal by combining existing
  HMPPS architecture patterns. Use when asked to write a how-to guide,
  document how to solve a real-world problem using HMPPS patterns,
  produce step-by-step guidance for a goal (e.g. "how to publish a
  domain event", "how to add authentication to a new service"), or
  write a narrative that stitches multiple patterns together.
---

# Writing an HMPPS architecture how-to guide

> **Note:** This skill is designed for use in the `hmpps-architecture-patterns` repository.
> The file path `source/documentation/how-to/` is specific to that repo.

HMPPS Digital aligns the technical approach of delivery teams by providing goal-oriented how-to guides that show teams how to combine existing architecture patterns to achieve a concrete outcome. Text in HMPPS how-to guides should strictly follow the guidelines for the 'how-to guide' sector of the [Diataxis framework](https://diataxis.fr/how-to-guides/).

How-to guides are **goal-oriented**, not learning-oriented. They assume the reader is a competent practitioner who knows *why* they are doing this and needs to know *how*. They are distinct from:

- **Patterns / explanation** — *why* HMPPS does something a certain way (see `hmpps-architecture-pattern` skill)
- **Tutorials** — lessons that teach a beginner by doing
- **Reference** — dry, factual description of a component or API

## When to use this skill

Use this skill when asked to:

- Write a how-to guide in the HMPPS architecture patterns site
- Document how to achieve a specific goal by combining HMPPS architecture patterns
- Produce step-by-step guidance for a real-world delivery task (e.g. "how to publish a domain event", "how to expose a new API through the API gateway")

---

## Step 1: Collect information on the how-to guide

Gather the following, asking clarifying questions as needed. Do not guess — if a field is unclear, ask.

1. **Guide title** — A short imperative phrase starting with "How to…" (e.g. *How to publish a domain event*)
2. **Goal** — The concrete outcome the reader will have achieved by the end. One sentence.
3. **Audience and assumed knowledge** — Who is this for (e.g. a delivery team engineer)? What must they already know or have in place before starting?
4. **Prerequisites** — Accounts, access, tools, running services, or prior setup the reader needs before step 1
5. **Patterns being composed** — Which existing HMPPS architecture patterns does this guide draw on? List them by name so they can be cross-linked. If a required pattern does not yet exist, flag it.
6. **Steps** — The ordered sequence of actions the reader must take. Each step should be a single, verifiable action.
7. **Decision points** — Any "if X, do Y; otherwise do Z" branches the reader will hit
8. **Verification** — How the reader confirms each step (and the whole goal) succeeded
9. **Related guides and next steps** — What the reader might reasonably want to do next
10. **Resources** — Supporting docs, GitHub repos, Slack channels

## Step 2: Write the document

### File location and naming

- Create the file in `source/documentation/how-to/`
- Use kebab-case, starting with the verb: `publish-a-domain-event.html.md.erb`
- Include frontmatter with `title` (phrased as "How to…") and `goal` (one sentence stating the concrete outcome)

### Document structure

```markdown
---
title: How to <do the thing>
goal: <one sentence stating the concrete outcome the reader will achieve>
---

# How to <do the thing>

## Goal

One or two sentences expanding on the frontmatter `goal`. Focus on the "so what".

## Before you start

- Who this guide is for and what they are assumed to already know
- Prerequisites: access, tooling, running services, prior setup
- The HMPPS architecture patterns this guide composes, each linked to its pattern page

## Steps

Numbered, imperative steps. One action per step. Each step should:

- Start with a verb ("Create…", "Add…", "Deploy…")
- Link to the relevant pattern(s) rather than restating them
- Include the exact commands, config snippets, or file paths the reader needs
- End with a short "You should now see…" or equivalent check

Use sub-steps only where a step genuinely branches.

### Handling decisions

Where the reader must choose a path, use a short sub-heading per option and describe when to pick each.

## Verify the outcome

How the reader confirms the overall goal has been achieved end-to-end (e.g. an event visible on a topic, a health check returning 200, a log line appearing).

## Troubleshooting

Common failure modes and how to resolve them. Optional — include only if there are known pitfalls.

## Next steps

Links to related how-to guides, patterns, or reference material the reader is likely to want next.

## Support

- Slack channels for questions
- Team contacts where appropriate
```

### Tone and content rules

- **Goal-oriented, not educational** — Do not teach concepts. Assume the reader knows *why* and needs to know *how*. If you find yourself explaining rationale, either delete it or move it to the linked pattern page.
- **Imperative voice** — "Add the following to your Helm values" not "You could add…" or "One approach is to add…"
- **Concrete and copy-pasteable** — Prefer real file paths, real commands, real config snippets over paraphrase
- **One path through the guide** — Cover the recommended path only. Alternatives belong in patterns or reference docs, or as explicit decision points
- **Link, don't duplicate** — Every pattern this guide composes must be linked to its pattern page. Do not restate pattern rationale
- **Assume competence, not omniscience** — The reader is a delivery team engineer, not a beginner and not an HMPPS architect
- **Verifiable** — Every step should have an observable outcome the reader can check
