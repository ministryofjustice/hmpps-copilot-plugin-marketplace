---
name: hmpps-architecture-pattern
description: >
  Write human-readable documentation of a technical architecture pattern
  for stakeholders of varying technical backgrounds. Use when asked to
  document patterns, write architecture guidance, create technical standards,
  or explain HMPPS technology choices.
---

# Documenting a technical architecture pattern

> **Note:** This skill is designed for use in the `hmpps-architecture-patterns` repository.
> The file path `source/documentation/patterns/` is specific to that repo.

HMPPS Digital aligns the technical approach of delivery teams by providing guidance in the form of technical architecture patterns. Technical architecture patterns are similar to the patterns-based approach used by Christopher Alexander in the book 'A Pattern Language'. Text in the HMPPS technical architecture patterns should strictly follow the guidelines for the 'explanation' sector of the [Diataxis framework](https://diataxis.fr/explanation/).

## When to use this skill

Use this skill when asked to:

- Document a technical architecture pattern
- Create guidance for a new technical standard
- Explain why HMPPS uses a particular technology or approach

---

## Step 1: Collect information on the technical architecture pattern

Gather the following information, asking clarifying questions as needed:

1. **Pattern name** — Ensure the pattern has a clear, descriptive name
2. **Problem statement** — What problem does this pattern solve? What situations call for it?
3. **Rationale** — Why has HMPPS Digital chosen this approach? What are the benefits?
4. **Outcomes** — What outcomes does this pattern support for delivery teams?
5. **Implementation details** — What are the key steps, tools, or practices teams should follow?
6. **Category** — Which category does this pattern belong to? This may be an existing category or a new category
7. **Resources** — What documentation, GitHub repos, Slack channels, or other resources support this pattern?

## Step 2: Write the document

### File location and naming

- Create the file in `source/documentation/patterns/`
- Use kebab-case for the filename: `pattern-name.html.md.erb`
- Include frontmatter with `title` and `category`

### Document structure

```markdown
---
title: Pattern Name
category: Category Name
---

# Pattern Name

## Outline

One short paragraph (2-3 sentences) framing why this pattern exists and what outcomes it supports. Focus on the "so what", not just "what".

## Rationale

A longer section explaining why HMPPS Digital is implementing this pattern. Include:
- The problems being solved
- Benefits of this approach
- When and where it should be applied

Use bold text for key points to aid scanning.

## Implementation

A bulleted list of actionable guidance helping technical teams implement the pattern. Include links to relevant GitHub repositories, templates, and tools.

## Documentation

Links to relevant documentation:
- External docs (e.g., official product documentation)
- Internal docs (e.g., HMPPS engineering docs, Cloud Platform user guide)
- Confluence pages (note if login required)

## Support

- Slack channels for questions and support
- Team contacts where appropriate
```

### Tone rules

- **Write for someone with zero familiarity** with HMPPS Digital
- Use plain language; avoid jargon without explanation
- Be specific and actionable in the Implementation section
- Link to resources rather than duplicating content
