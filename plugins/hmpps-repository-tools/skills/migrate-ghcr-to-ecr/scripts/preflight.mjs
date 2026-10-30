#!/usr/bin/env node
// Checks the prerequisites for a GHCR -> ECR migration of the repository in the current directory.
// Prints JSON to stdout: { ok, repo, checks: [{ name, ok, detail }] }. Exits 1 if any check fails.
import { execFileSync } from 'node:child_process'

const REQUIRED_VARIABLES = ['CLOUD_PLATFORM_ECR_REGISTRY_URL', 'ECR_REGION', 'ECR_REPOSITORY']
const REQUIRED_SECRETS = ['ECR_ROLE_TO_ASSUME']

const run = (cmd, args) =>
  execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim()

const checks = []
const add = (name, ok, detail) => checks.push({ name, ok, detail })
let repo = null

try {
  add('gh installed', true, run('gh', ['--version']).split('\n')[0])
} catch {
  add('gh installed', false, 'GitHub CLI (gh) not found. Install it from https://cli.github.com')
}

if (checks[0].ok) {
  try {
    run('gh', ['auth', 'status'])
    add('gh authenticated', true, 'gh auth status succeeded')
  } catch {
    add('gh authenticated', false, 'Not authenticated. Run `gh auth login` and try again')
  }
}

if (checks.every(c => c.ok)) {
  try {
    repo = run('gh', ['repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner'])
    add('repository detected', true, repo)
  } catch {
    add('repository detected', false, 'Run this from inside a clone of the GitHub repository to migrate')
  }
}

if (repo) {
  try {
    const variables = JSON.parse(run('gh', ['variable', 'list', '--json', 'name,value']))
    for (const v of REQUIRED_VARIABLES) {
      const found = variables.find(n => n.name === v)
      add(`variable ${v}`, Boolean(found && found.value), found?.value ? 'set' : 'missing or empty')
    }
  } catch (e) {
    add('repository variables', false, `Could not list variables: ${e.stderr?.trim() || e.message}`)
  }

  try {
    const names = JSON.parse(run('gh', ['secret', 'list', '--json', 'name'])).map(s => s.name)
    for (const s of REQUIRED_SECRETS) {
      add(`secret ${s}`, names.includes(s), names.includes(s) ? 'set' : 'missing')
    }
  } catch (e) {
    add('repository secrets', false, `Could not list secrets: ${e.stderr?.trim() || e.message}`)
  }
}

const ok = checks.every(c => c.ok)
console.log(JSON.stringify({ ok, repo, checks }, null, 2))
if (!ok) {
  console.error('Preflight failed. The ECR prerequisites must be in place before migrating.')
  process.exit(1)
}
