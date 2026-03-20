# Copilot Instructions

## Repository purpose

This is the **HMPPS Copilot Plugin Marketplace** — a collection of GitHub Copilot CLI plugins for HMPPS projects. Each plugin provides AI-assisted workflows that are installed into consumer repositories via:

```
copilot plugin marketplace add ministryofjustice/hmpps-copilot-plugin-marketplace
```

## Architecture

The repository has two layers of configuration:

1. **Marketplace registry** — `.github/plugin/marketplace.json` lists all available plugins with their name, description, version, and source path.

2. **Plugins** — each plugin lives in `plugins/<plugin-name>/` and contains:
   - `plugin.json` — plugin metadata (name, description, version, author, license, keywords)
   - `skills/<skill-name>/` — one or more skills, each with:
     - `SKILL.md` — YAML frontmatter (`name`, `description`) followed by detailed markdown instructions that Copilot follows when executing the skill
     - `scripts/` — vanilla Node.js `.mjs` scripts the skill invokes

When a plugin is installed via `copilot plugin install`, it is cached at `~/.copilot/state/installed-plugins/MARKETPLACE/PLUGIN-NAME/`. Skills within the plugin are loaded from there — they are **not** copied into the consumer repo.

## Adding a new plugin

1. Create `plugins/<plugin-name>/plugin.json`
2. Add skills under `plugins/<plugin-name>/skills/<skill-name>/` — each skill needs a `SKILL.md` and any supporting scripts
3. Register the plugin in `.github/plugin/marketplace.json`

Refer to the [GitHub Copilot plugin authoring guide](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-creating).

## SKILL.md conventions

`SKILL.md` uses YAML frontmatter to declare the skill to Copilot:

```yaml
---
name: skill-name
description: >
  One or two sentences describing when to trigger this skill.
  Include trigger phrases here.
---
```

The markdown body is the step-by-step instructions Copilot follows. Write it as imperative instructions directed at the Copilot agent, not at a human developer.

## Script conventions

- Scripts are plain `.mjs` files using native Node.js ESM — no `package.json`, no npm dependencies
- Scripts that produce data for Copilot to consume output **JSON to stdout**
- Scripts that produce output for display to users output **human-readable text to stdout**
- Errors go to stderr; scripts exit with code `1` on failure
- GitHub API calls are unauthenticated by default; scripts should respect a `GITHUB_TOKEN` env var if set to avoid rate limits

## Validation (in consumer repos)

After applying template changes via the `sync-typescript-template` skill, validate with:

```bash
npm run typecheck && npm run lint && npm run test
```

Commit message convention for template syncs:
```
chore: apply template change from hmpps-template-typescript PR #<number>
```
