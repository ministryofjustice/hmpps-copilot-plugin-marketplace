---
name: hmpps-architecture-blueprint
description: >
  Write human-readable documentation to be part of a technical blueprint
  for stakeholders of varying technical backgrounds. Use when asked to
  document a blueprint item, write very high level architecture guidance
  or explain HMPPS technical direction.
---

# Documenting a technical architecture blueprint item

> **Note:** This skill is designed for use in the `hmpps-architecture-blueprint` repository.
> The file paths below (`source/documentation/explanation/`, `source/index.html.md.erb`)
> are specific to that repo.

HMPPS Digital aligns the technical approach of delivery teams by providing
north star guidance in the form of technical blueprint documents. Technical
blueprint documents are **explanation** pages in the
[Diataxis framework](https://diataxis.fr/explanation/): they are
understanding-oriented, provide context and background, and explain *why*
HMPPS has chosen an approach. They are not step-by-step how-tos, tutorials,
or reference material.

## When to use this skill

Use this skill when asked to:

- Document a technical blueprint item
- Write high-level architecture guidance or "north star" direction
- Explain the rationale behind an HMPPS technical choice

## Audience

Write for a **technical reader who is new to HMPPS Digital**. Assume general
software engineering literacy (APIs, events, microservices, cloud), but
explain HMPPS-specific concepts, terms, and systems (domains, delivery
teams, NOMIS/NDelius/OASys, etc.) or link to a page that does.

---

## Step 1: Read existing blueprint pages

Before drafting, read at least two existing pages in
`source/documentation/explanation/` to absorb the tone, section depth, and
linking style. Good examples:

- `principles-overview.html.md.erb`
- `domain-events.html.md.erb`
- `service-technical-architecture.html.md.erb`

Also skim `source/index.html.md.erb` to see how existing pages are framed
and linked from the homepage.

## Step 2: Check for overlap

Search `source/documentation/` for pages that already cover part of the
topic. If a related page exists:

- **Link to it** rather than duplicating its content.
- If the new page will overlap significantly, ask whether the request would
  be better served by extending the existing page instead of creating a
  new one.

## Step 3: Collect information on the technical blueprint

Gather the following information, asking clarifying questions as needed:

1. **Document name** — a clear, descriptive title and purpose
2. **Technical direction** — the direction or approach the page describes
3. **Rationale** — why HMPPS Digital has chosen this approach and the benefits
4. **Scope of application** — when and where teams should apply it
5. **Related pages** — existing blueprint pages to link to (from Step 2)
6. **External resources** — documentation, GitHub repos, Confluence pages,
   Slack channels or ADRs that support this direction

## Step 4: Write the document

### File location and naming

- Create the file in `source/documentation/explanation/`
- Use kebab-case for the filename: `blueprint-document-name.html.md.erb`

### Document structure

```markdown
---
title: Document Name
---

# Document Name

## Technical Direction

One short paragraph (2-3 sentences) framing why this pattern exists and
what outcomes it supports. Focus on the "so what", not just "what".

## Rationale

A longer section explaining why HMPPS Digital is implementing this pattern.
Cover:

- The problems being solved
- Benefits of this approach
- When and where it should be applied

Use bold text for key points to aid scanning. Use sub-headings
(`### Benefits`, `### When to apply this`) if the section is long enough to
need them.

## Further Reading

- [Related blueprint page](./related-page.html)
- [External resource](https://example.org/...)
```

The **Further Reading** section is required — every existing explanation
page has one, and it enforces the "link, don't duplicate" rule.

### Tone rules

- Write for the audience defined above (technical, new to HMPPS)
- Use plain language; avoid jargon without explanation
- Explanation, not instruction — describe direction and rationale, not
  step-by-step procedure (that belongs in a how-to)
- Link to resources rather than duplicating content
- Use bold text for key points to aid scanning

## Step 5: Wire the page into navigation

New blueprint pages are usually linked from `source/index.html.md.erb`
under an appropriate heading. After writing the page, ask whether to add a
homepage link and, if so, where it fits best. Do not assume — some pages
are deliberately hidden (see `hide_in_navigation: true` in existing
frontmatter).
