---
name: write-skill
description: >
  Helps design, structure, and write high-quality GitHub Copilot skills (SKILL.md files and
  bundled assets). Use this skill when asked to: create a new skill, write a SKILL.md,
  scaffold a plugin skill, improve a skill's description or discoverability, add reference
  files or templates to a skill, or review/refactor an existing skill.
---

# Write a GitHub Copilot Skill

This skill helps you design and write effective GitHub Copilot skills: self-contained folders
that package reusable capabilities (instructions, reference files, templates, and scripts)
that agents can discover automatically and users can invoke via slash commands.

Use this skill whenever asked to create a new skill, scaffold a skill folder, write or improve
a `SKILL.md`, or review an existing skill for quality.

---

> **⚠️ If anything about the task — its purpose, triggers, scope, or expected output — is
> ambiguous, stop and ask the user. Never guess or invent details on their behalf.** This
> applies at every step below, not just Step 1.

---

## Outcome

By the end of this skill, either:

- The target skill should exist, and should:
  - Live in its own folder containing a `SKILL.md` and, if needed, bundled assets
  - Have YAML frontmatter with a kebab-case `name` matching the folder name, and a rich
    `description` written for agent discovery
  - Contain clear, imperative instructions for a single, focused purpose
  - Reference any bundled templates, scripts, or reference docs by relative path
  - Be generic enough to work across different projects, not hard-coded to one repo
- Or, if Step 0 determines a skill is the wrong tool, no skill is created and the user is
  told what to do instead (see Step 0).

---

## Step 0: Decide whether a skill is the right tool

Before scaffolding anything, work out whether the requested capability should actually be a
skill. Use this distinction:

- **Skill** — a repeatable, self-contained, on-demand task using standard tools, invoked
  explicitly (an agent matching intent automatically, or a user via slash command). Choose
  this when the request is a one-off capability someone will trigger by name or intent.
- **Instructions** (e.g. `.github/instructions/*.md`) — apply automatically and provide
  ongoing context or standards. Choose this instead when the request is something that should
  *always* be true or always applied, not a task performed on demand.
- **Agent persona** — for complex, multi-step workflows that need persistent state or MCP
  servers. Choose this instead when the task can't be captured as a self-contained set of
  instructions using standard tools.

**Expected behaviour based on the outcome:**

- If a **skill** is the right fit → proceed to Step 1.
- If **instructions** are the right fit → do not create a skill. Tell the user this belongs
  in an instructions file instead, and offer to create/update the relevant
  `.github/instructions/*.md` file (or ask where it should live if unclear). Stop here.
- If an **agent persona** is the right fit → do not create a skill. Tell the user this needs
  a dedicated agent rather than a skill, explain why, and stop here.
- If it's **genuinely unclear** which of the three applies → ask the user before proceeding.
  Do not default to building a skill just because that's what this skill produces.

## Step 1: Clarify the skill's purpose

Before writing anything, confirm:

1. **What single task or workflow** does this skill perform? Aim for a coherent unit of work:
   scoped too narrowly, it forces multiple skills to load for one task; scoped too broadly
   (e.g. bundling unrelated tasks like "query the database" and "administer the database"),
   it becomes hard for an agent to activate precisely. Split unrelated tasks into separate
   skills.
2. **What triggers it?** What phrases, keywords, or user intents should cause an agent to
   invoke this skill automatically?
3. **What does it produce?** Code changes, a generated file, a report, a git commit, etc.
4. **Does it need bundled assets** — reference docs, templates, JSON schemas, or scripts —
   to avoid the agent hallucinating formats or conventions?
5. **What real expertise should this be grounded in?** Prefer project-specific source
   material over generic knowledge — ask the user for existing runbooks, style guides, API
   specs, past corrections they've made to an agent, or examples of the task done well. A
   skill synthesized from real conventions and failure cases outperforms one synthesized from
   generic "best practices."

**If any of this is unclear or ambiguous, ask the user before proceeding — do not guess.**

## Step 2: Scaffold the folder

Create a folder named with the skill's kebab-case name (e.g. `skills/generate-tests/`).
Bundle supporting assets in conventional subfolders when useful:

```
skills/<skill-name>/
├── SKILL.md
├── references/       # background docs, patterns, specs
├── assets/           # templates, images, data files to copy/adapt
└── scripts/           # helper scripts the skill invokes
```

Only add subfolders that are actually needed — don't create empty scaffolding.

## Step 3: Write the YAML frontmatter

```yaml
---
name: skill-name
description: 'What the skill does and when to use it (1-1024 characters)'
---
```

- **name** _(required)_: kebab-case, matches the folder name, doubles as the `/command` users
  can type. Constraints from the Agent Skills spec:
  - 1-64 characters
  - lowercase alphanumeric characters and hyphens only
  - must not start or end with a hyphen
  - must not contain consecutive hyphens (`--`)
- **description** _(required)_: the most important field for agent discovery. Write it so an
  agent reading it alone can decide whether to invoke the skill. Must be 1-1024 characters.
  Include:
  - What the skill accomplishes
  - Concrete trigger phrases / keywords / user intents
  - Avoid vague descriptions

  ✅ Good: `'Generate conventional commit messages by analyzing staged git changes and
  applying the Conventional Commits specification'`

  ❌ Poor: `'Commit helper'`

- **license** _(optional)_: the license applied to the skill — either a license name or a
  reference to a bundled license file, e.g. `license: Apache-2.0`.
- **compatibility** _(optional, max 500 characters)_: environment requirements — intended
  product, required system packages, network access needs, e.g.
  `compatibility: Requires git, docker, jq, and access to the internet`. Only include this if
  the skill has specific requirements; most skills don't need it.
- **metadata** _(optional)_: an arbitrary string key-value map for additional properties not
  covered by the spec, e.g. `author` or `version`. Use reasonably unique key names to avoid
  conflicts.
- **allowed-tools** _(optional, experimental)_: a space-separated string of pre-approved tools
  the skill may use, e.g. `allowed-tools: Bash(git:*) Bash(jq:*) Read`. Support varies between
  agent implementations.
- **argument-hint** _(optional, Copilot CLI extension, v1.0.64+; not part of the Agent Skills
  spec)_: a short placeholder shown in the slash-command input box, e.g.
  `argument-hint: 'Enter function or file to test'`

## Step 4: Write the instructions body

Structure the markdown body as imperative instructions directed at the agent, not prose
aimed at a human developer:

1. **State the objective** up front: "Your goal is to [specific task] for [specific target]."
2. **Add a "When to Use This Skill" section** with trigger phrases/keywords — reinforces
   discovery even though the frontmatter description is the primary discovery mechanism.
3. **Define explicit requirements and guardrails**:
   - ✅ "Use Jest with React Testing Library"
   - ❌ "Use whatever testing framework"
   - ✅ "Do not modify existing test files; create new ones"
   - ❌ "Update tests as needed"
4. **Break complex skills into numbered steps** (analyse → generate → validate, etc.)
5. **Reference bundled assets by relative path**, e.g.:
   `Follow the patterns in [references/testing-patterns.md](references/testing-patterns.md).`
6. **Use imperative mood throughout**: "Generate unit tests for the selected function", not
   "You should generate some tests".
7. **Only include what the agent wouldn't already know.** Skip generic explanations (what a
   PDF is, how HTTP works) and focus on project-specific conventions, non-obvious edge cases,
   and the particular tools/APIs to use. If the agent would get it right without the
   instruction, cut it.
8. **Match specificity to fragility.** Give the agent freedom (and explain *why*) when
   multiple approaches are valid and the task tolerates variation. Be strictly prescriptive
   — exact commands, "do not add flags" — when a sequence is fragile or consistency matters.
9. **Provide a default, not a menu.** When several tools/approaches could work, pick one as
   the default and mention an alternative briefly, rather than listing them as equal options.
10. **Favor procedures over declarations.** Teach *how to approach* a class of problem (e.g.
    "read the schema, join on the `_id` convention, apply filters from the request") rather
    than hard-coding the answer to one specific instance — so the skill generalizes.

### Useful instruction patterns

Use whichever of these fit the skill — not every skill needs all of them:

- **Gotchas section** — a list of concrete, non-obvious, environment-specific facts the agent
  would otherwise get wrong (e.g. naming inconsistencies, misleading health checks). Keep
  these in `SKILL.md` itself so the agent reads them before hitting the situation.
- **Output templates** — when output must follow a specific format, show a concrete template
  instead of describing it in prose. Short templates can live inline; longer ones belong in
  `assets/` and should be referenced by path.
- **Workflow checklists** — for multi-step workflows with dependencies, give the agent an
  explicit `- [ ]` checklist to track progress and avoid skipping steps.
- **Validation loops** — for self-checkable work, instruct: do the work → run a validator
  (script, checklist, or reference doc) → fix issues → repeat until it passes.

## Step 5: Add bundled assets (if needed)

- `references/*.md` — background docs, conventions, or specs the agent should follow instead
  of guessing
- `assets/*` — templates, images, or data files the agent copies/adapts (code, JSON, config,
  lookup tables)
- `scripts/*` — small helper scripts the skill invokes (e.g. `.mjs`/`.sh` files); keep them
  dependency-free where possible and document their invocation in `SKILL.md`
- Keep each bundled file under 5 MB
- Reference bundled files with paths one level deep from `SKILL.md` (e.g.
  `references/REFERENCE.md`, not `references/foo/bar/REFERENCE.md`) — avoid deeply nested
  reference chains

### Progressive disclosure

Agents load skills in three stages, so structure content to take advantage of this:

1. **Metadata** (~100 tokens) — `name` and `description` are loaded at startup for all skills
2. **Instructions** (<5000 tokens recommended) — the full `SKILL.md` body loads only once the
   skill is activated
3. **Resources** (as needed) — files in `scripts/`, `references/`, or `assets/` load only when
   the agent needs them

Keep `SKILL.md` under 500 lines. Move detailed or rarely-needed material into separate
`references/*.md` files rather than inlining everything in the main body.

## Step 6: Review against the checklist

Before finishing, check the skill against these criteria:

- [ ] One purpose per skill
- [ ] `name` is kebab-case, ≤64 characters, matches the folder name, and has no leading/
  trailing or consecutive hyphens
- [ ] `description` is 1-1024 characters, includes trigger keywords, and is written for agent
  discovery, not humans
- [ ] Instructions use imperative mood and are unambiguous
- [ ] Requirements and guardrails are explicit, not vague
- [ ] `SKILL.md` is under 500 lines; detailed material is split into `references/*.md`
- [ ] Bundled assets are referenced by relative path, one level deep, where relevant
- [ ] The skill is generic enough to work across different projects/codebases
- [ ] Bundled files are each under 5 MB
- [ ] Nothing was guessed or invented where the task, triggers, or output were ambiguous —
  the user was asked instead

If there's an opportunity to run the new skill against a real task, do so and refine the
instructions based on what actually happens — even one pass of execute-then-revise
meaningfully improves quality. Pay attention to steps the agent found confusing, instructions
it ignored, or corrections you had to make; feed those back into the skill (e.g. as a new
gotcha).

## Reference examples

- **Simple, single-purpose skill**: a `generate-tests` skill with just a `SKILL.md` — clear
  objective, "When to Use" section, explicit requirements (framework, naming conventions,
  coverage expectations).
- **Skill with bundled assets**: a diagram-generator skill bundling a schema doc, JSON
  templates, and a helper script, so the agent has everything needed to produce valid output
  without hallucinating the format.
- **Automation skill**: a `conventional-commit` skill that runs `git status` and
  `git diff --cached`, then constructs and executes a commit following the Conventional
  Commits specification.

See this repository's own plugins (e.g. `plugins/hmpps-proxy-aware/skills/`) for examples
that already follow these conventions.
