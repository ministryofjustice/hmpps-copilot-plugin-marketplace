#!/usr/bin/env node
/**
 * fix-security.mjs
 *
 * Automatically fixes HMPPS security configuration issues in a Node.js repository.
 * Run check-security.mjs first to identify issues, then run this to fix them.
 *
 * Usage: node fix-security.mjs [--repo <path>] [--checks <id,id,...>]
 *
 * --repo     Path to the repository root (defaults to cwd)
 * --checks   Comma-separated list of check IDs to fix (defaults to all failures)
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs'
import { resolve, join, dirname } from 'node:path'
import { execSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))

// ── CLI args ──────────────────────────────────────────────────────────────────

const args = process.argv.slice(2)

const repoArgIndex = args.indexOf('--repo')
const repoPath = repoArgIndex !== -1 ? resolve(args[repoArgIndex + 1]) : process.cwd()

const checksArgIndex = args.indexOf('--checks')
const requestedChecks =
  checksArgIndex !== -1 ? args[checksArgIndex + 1].split(',').map((s) => s.trim()) : null

// ── Helpers ───────────────────────────────────────────────────────────────────

function readFile(filePath) {
  try {
    return readFileSync(filePath, 'utf8')
  } catch {
    return null
  }
}

async function fetchText(url) {
  const token = process.env.GITHUB_TOKEN
  const headers = token ? { Authorization: `Bearer ${token}` } : {}
  const res = await fetch(url, { headers })
  if (!res.ok) throw new Error(`HTTP ${res.status} fetching ${url}`)
  return res.text()
}

function ensureDir(dirPath) {
  if (!existsSync(dirPath)) {
    mkdirSync(dirPath, { recursive: true })
  }
}

// ── Run checks to find failures ───────────────────────────────────────────────

let checkResults
try {
  const output = execSync(`node ${JSON.stringify(join(__dirname, 'check-security.mjs'))} --repo ${JSON.stringify(repoPath)}`, {
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
  })
  checkResults = JSON.parse(output)
} catch (err) {
  // Script exits 1 when there are failures — that's expected. Parse stdout.
  if (err.stdout) {
    try {
      checkResults = JSON.parse(err.stdout)
    } catch {
      console.error('Failed to parse check-security.mjs output:', err.stdout)
      process.exit(1)
    }
  } else {
    console.error('Failed to run check-security.mjs:', err.message)
    process.exit(1)
  }
}

const failures = checkResults.filter((c) => c.status === 'fail')
const toFix = requestedChecks
  ? failures.filter((c) => requestedChecks.includes(c.id))
  : failures

if (toFix.length === 0) {
  console.log(JSON.stringify({ fixed: [], skipped: [], errors: [] }, null, 2))
  process.exit(0)
}

// ── Fix handlers ──────────────────────────────────────────────────────────────

const fixed = []
const skipped = []
const errors = []

/**
 * NOT auto-fixable — requires GitHub repository settings UI.
 */
function skipActionsEnabled() {
  skipped.push({
    id: 'actions-enabled',
    reason: 'GitHub Actions status cannot be changed automatically. Enable it in the repository settings under Actions > General.',
  })
}

/**
 * Creates/overwrites .nvmrc with Node.js 24.
 */
function fixNvmrc() {
  const nvmrcPath = join(repoPath, '.nvmrc')
  writeFileSync(nvmrcPath, '24\n', 'utf8')
  fixed.push({ id: 'nvmrc', action: `Wrote "24" to ${nvmrcPath}` })
}

/**
 * Updates package.json engines.npm and/or engines.node.
 * Preserves file formatting by doing a targeted JSON manipulation.
 */
function fixEngines(checkId) {
  const packageJsonPath = join(repoPath, 'package.json')
  const content = readFile(packageJsonPath)
  if (!content) {
    errors.push({ id: checkId, message: 'package.json not found — cannot update engines field.' })
    return
  }

  let pkg
  try {
    pkg = JSON.parse(content)
  } catch {
    errors.push({ id: checkId, message: 'package.json is not valid JSON — cannot update engines field.' })
    return
  }

  if (!pkg.engines) pkg.engines = {}

  if (checkId === 'engines-npm' || checkId === 'engines-node') {
    // Fix both at once since they live in the same object
    pkg.engines.node = '>=24.0.0'
    pkg.engines.npm = '>=11.10.0'
  }

  // Detect indentation from original file
  const indentMatch = content.match(/^(\s+)"/m)
  const indent = indentMatch ? indentMatch[1] : '  '

  writeFileSync(packageJsonPath, JSON.stringify(pkg, null, indent) + '\n', 'utf8')
  fixed.push({ id: checkId, action: `Updated engines in package.json: node >= 24.0.0, npm >= 11.10.0` })
}

/**
 * Fetches the canonical .npmrc from the HMPPS template and writes it to the repo.
 */
async function fixNpmrc() {
  let content
  try {
    content = await fetchText(
      'https://raw.githubusercontent.com/ministryofjustice/hmpps-template-typescript/main/.npmrc',
    )
  } catch (err) {
    errors.push({ id: 'npmrc', message: `Could not fetch template .npmrc: ${err.message}` })
    return
  }
  writeFileSync(join(repoPath, '.npmrc'), content, 'utf8')
  fixed.push({ id: 'npmrc', action: 'Wrote .npmrc from HMPPS template.' })
}

/**
 * Fetches a security workflow from the HMPPS template and writes it to .github/workflows/.
 */
async function fixWorkflow(checkId, filename) {
  const url = `https://raw.githubusercontent.com/ministryofjustice/hmpps-template-typescript/main/.github/workflows/${filename}`
  let content
  try {
    content = await fetchText(url)
  } catch (err) {
    errors.push({ id: checkId, message: `Could not fetch ${filename} from template: ${err.message}` })
    return
  }
  const workflowsDir = join(repoPath, '.github', 'workflows')
  ensureDir(workflowsDir)
  writeFileSync(join(workflowsDir, filename), content, 'utf8')
  fixed.push({ id: checkId, action: `Wrote .github/workflows/${filename} from HMPPS template.` })
}

/**
 * Appends missing entries to .gitignore (or creates it).
 */
function fixGitignore(checkId, entry) {
  const gitignorePath = join(repoPath, '.gitignore')
  const existing = readFile(gitignorePath) ?? ''
  const lines = existing.split('\n').map((l) => l.trim())

  if (lines.includes(entry)) {
    // Already present — check was a false positive, mark as skipped
    skipped.push({ id: checkId, reason: `${entry} is already in .gitignore.` })
    return
  }

  const newContent = existing.endsWith('\n') || existing === ''
    ? existing + entry + '\n'
    : existing + '\n' + entry + '\n'

  writeFileSync(gitignorePath, newContent, 'utf8')
  fixed.push({ id: checkId, action: `Added "${entry}" to .gitignore.` })
}

// ── Apply fixes ───────────────────────────────────────────────────────────────

// Track whether we've already fixed engines (npm and node share the same fix)
let enginesFixed = false

for (const check of toFix) {
  try {
    switch (check.id) {
      case 'actions-enabled':
        skipActionsEnabled()
        break
      case 'nvmrc':
        fixNvmrc()
        break
      case 'engines-npm':
      case 'engines-node':
        if (!enginesFixed) {
          fixEngines(check.id)
          enginesFixed = true
          // Mark the other engines check as fixed too if it was in the list
          const otherId = check.id === 'engines-npm' ? 'engines-node' : 'engines-npm'
          if (toFix.some((c) => c.id === otherId)) {
            fixed.push({ id: otherId, action: 'Fixed as part of engines update (see engines-npm/engines-node fix).' })
          }
        }
        break
      case 'npmrc':
        await fixNpmrc()
        break
      case 'workflow-codeql':
        await fixWorkflow('workflow-codeql', 'security_codeql_actions_scan.yml')
        break
      case 'workflow-npm-dependency':
        await fixWorkflow('workflow-npm-dependency', 'security_npm_dependency.yml')
        break
      case 'workflow-veracode-pipeline':
        await fixWorkflow('workflow-veracode-pipeline', 'security_veracode_pipeline_scan.yml')
        break
      case 'workflow-veracode-policy':
        await fixWorkflow('workflow-veracode-policy', 'security_veracode_policy_scan.yml')
        break
      case 'gitignore-node-modules':
        fixGitignore('gitignore-node-modules', 'node_modules')
        break
      case 'gitignore-env':
        fixGitignore('gitignore-env', '.env')
        break
      case 'dockerfile-npmrc':
        skipped.push({
          id: 'dockerfile-npmrc',
          reason:
            'Dockerfile changes cannot be applied automatically — the correct placement of .npmrc in a COPY instruction depends on your build stage structure. Add ".npmrc" to the COPY instruction before your npm install step, for example: COPY package*.json .npmrc ./',
        })
        break
      case 'dockerfile-base-image':
        skipped.push({
          id: 'dockerfile-base-image',
          reason:
            'Dockerfile base image changes cannot be applied automatically — update the FROM instruction(s) manually to use ghcr.io/ministryofjustice/hmpps-node:24-alpine (or the appropriate variant for your project).',
        })
        break
      default:
        skipped.push({ id: check.id, reason: `No automated fix available for check "${check.id}".` })
    }
  } catch (err) {
    errors.push({ id: check.id, message: `Unexpected error: ${err.message}` })
  }
}

// ── Output ────────────────────────────────────────────────────────────────────

console.log(JSON.stringify({ fixed, skipped, errors }, null, 2))

process.exit(errors.length > 0 ? 1 : 0)
