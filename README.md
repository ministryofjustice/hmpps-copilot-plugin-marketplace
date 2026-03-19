# hmpps-copilot-plugin-marketplace

A collection of GitHub Copilot skills for HMPPS projects. Each plugin adds AI-assisted workflows to your repository via VS Code's Copilot CLIs plugin system.

To register the market place in your Copilot CLI, run:

```bash
/plugin marketplace add ministryofjustice/hmpps-copilot-plugin-marketplace
```

To install a plugin:
```bash
/plugin install hmpps-template-sync@hmpps-marketplace 
```

To list and view information about the included skill:
```bash
skills list
skills info sync-typescript-template
```

To run the skill 
```bash
/hmpps-template-sync:sync-typescript-template
```

To remove the marketplace and uninstall these plugins, run:
```bash
    /plugin marketplace remove hmpps-marketplace --force
```

---

## Available plugins

| Plugin                                                                                                   | Description                                                                                                                                                    |
| -------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`hmpps-template-sync`](plugins/hmpps-template-sync/README.md) | Keep your repository in sync with changes from the [hmpps-template-typescript](https://github.com/ministryofjustice/hmpps-template-typescript) shared template |
| [`skills`](plugins/skills/README.md)                                                                     | General-purpose skill for managing and applying template changes                                                                                               |

---

## To create a new plugin

See the guide [here](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-creating).
