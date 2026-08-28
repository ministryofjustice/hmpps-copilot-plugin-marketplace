# hmpps-copilot-plugin-marketplace

A collection of GitHub Copilot skills for HMPPS projects. Each plugin adds AI-assisted workflows to your repository via VS Code's Copilot CLIs plugin system.

To register the marketplace in your Copilot CLI, run:

```bash
/plugin marketplace add ministryofjustice/hmpps-copilot-plugin-marketplace
```

To install a plugin:

```bash
/plugin install hmpps-template-sync@hmpps-marketplace
```

To reload available skills:

```bash
/skills reload
```

To list and view information about the included skill:

```bash
skills list
skills info sync-typescript-template
```

To run the skill:

```bash
/hmpps-template-sync:sync-typescript-template
```

To remove the marketplace and uninstall these plugins, run:

```bash
/plugin marketplace remove hmpps-marketplace --force
```

---

## Using with OpenCode

These skills can also be installed for use with [OpenCode](https://opencode.ai/).

Clone this repo and run the installation script:

```bash
git clone https://github.com/ministryofjustice/hmpps-copilot-plugin-marketplace.git
cd hmpps-copilot-plugin-marketplace
./scripts/install-opencode-skills.sh
```

This creates symlinks in `~/.config/opencode/skills/` pointing to the skill folders in this repo. Restart OpenCode to pick up the new skills.

To remove the installed skills:

```bash
./scripts/install-opencode-skills.sh --remove
```

---

## Available plugins

| Plugin                                                                                         | Description                                                                                                                                                    |
| ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`hmpps-template-sync`](plugins/hmpps-template-sync/skills/sync-typescript-template/README.md) | Keep your repository in sync with changes from the [hmpps-template-typescript](https://github.com/ministryofjustice/hmpps-template-typescript) shared template |
| [`hmpps-proxy-aware`](plugins/hmpps-proxy-aware/skills/make-typescript-proxy-aware/README.md)   | Make TypeScript services proxy-aware using HMPPS patterns, including hmpps-rest-client migrations, telemetry updates, and staged Helm rollout support        |

---

## To create a new plugin

See the guide [here](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-creating).


## To test changes to the marketplace

Remove the plugin:
```bash
/plugin marketplace remove hmpps-marketplace --force
```

Add a local checked out marketplace:
```bash
/plugin marketplace add <path-to-local-repo>
```
