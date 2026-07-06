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

1. **What single task or workflow** does this skill perform? (One purpose per skill — split
   unrelated tasks into separate skills.)
2. **What triggers it?** What phrases, keywords, or user intents should cause an agent to
   invoke this skill automatically?
3. **What does it produce?** Code changes, a generated file, a report, a git commit, etc.
4. **Does it need bundled assets** — reference docs, templates, JSON schemas, or scripts —
   to avoid the agent hallucinating formats or conventions?

**If any of this is unclear or ambiguous, ask the user before proceeding — do not guess.**

## Step 2: Scaffold the folder

Create a folder named with the skill's kebab-case name (e.g. `skills/generate-tests/`).
Bundle supporting assets in conventional subfolders when useful:

```
skills/<skill-name>/
├── SKILL.md
├── references/       # background docs, patterns, specs
├── templates/         # starter files to copy/adapt
└── scripts/            # helper scripts the skill invokes
```

Only add subfolders that are actually needed — don't create empty scaffolding.

## Step 3: Write the YAML frontmatter

```yaml
---
name: skill-name
description: 'What the skill does and when to use it (10-1024 characters)'
---
```

- **name**: kebab-case, matches the folder name, doubles as the `/command` users can type
- **description**: the most important field for agent discovery. Write it so an agent reading
  it alone can decide whether to invoke the skill. Include:
  - What the skill accomplishes
  - Concrete trigger phrases / keywords / user intents
  - Avoid vague descriptions

  ✅ Good: `'Generate conventional commit messages by analyzing staged git changes and
  applying the Conventional Commits specification'`

  ❌ Poor: `'Commit helper'`

- **argument-hint** _(optional, v1.0.64+)_: a short placeholder shown in the slash-command
  input box, e.g. `argument-hint: 'Enter function or file to test'`

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
4. **Break complex skills into numbered steps** (analyze → generate → validate, etc.)
5. **Reference bundled assets by relative path**, e.g.:
   `Follow the patterns in [references/testing-patterns.md](references/testing-patterns.md).`
6. **Use imperative mood throughout**: "Generate unit tests for the selected function", not
   "You should generate some tests".

## Step 5: Add bundled assets (if needed)

- `references/*.md` — background docs, conventions, or specs the agent should follow instead
  of guessing
- `templates/*` — starter files the agent copies/adapts (code, JSON, config)
- `scripts/*` — small helper scripts the skill invokes (e.g. `.mjs`/`.sh` files); keep them
  dependency-free where possible and document their invocation in `SKILL.md`
- Keep each bundled file under 5 MB

## Step 6: Review against the checklist

Before finishing, check the skill against these criteria:

- [ ] One purpose per skill
- [ ] `name` is kebab-case and matches the folder name
- [ ] `description` includes trigger keywords and is written for agent discovery, not humans
- [ ] Instructions use imperative mood and are unambiguous
- [ ] Requirements and guardrails are explicit, not vague
- [ ] Bundled assets are referenced by relative path where relevant
- [ ] The skill is generic enough to work across different projects/codebases
- [ ] Bundled files are each under 5 MB
- [ ] Nothing was guessed or invented where the task, triggers, or output were ambiguous —
  the user was asked instead

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
