#!/usr/bin/env node
/**
 * check-security.mjs
 *
 * Audits a Node.js GitHub repository against HMPPS security standards.
 * Outputs a JSON array of check results to stdout.
 *
 * Usage: node check-security.mjs [--repo <path>]
 */

import { readFileSync, readdirSync } from 'node:fs'
import { resolve, join } from 'node:path'
import { execSync } from 'node:child_process'

// ── CLI args ──────────────────────────────────────────────────────────────────

const args = process.argv.slice(2)
const repoArgIndex = args.indexOf('--repo')
const repoPath = repoArgIndex !== -1 ? resolve(args[repoArgIndex + 1]) : process.cwd()

// ── Helpers ───────────────────────────────────────────────────────────────────

function result(id, label, status, detail) {
  return { id, label, status, detail }
}

function readFile(filePath) {
  try {
    return readFileSync(filePath, 'utf8')
  } catch {
    return null
  }
}

function parseJson(content) {
  try {
    return JSON.parse(content)
  } catch {
    return null
  }
}

/**
 * Compares semantic version strings. Returns true if `actual` satisfies `>= required`.
 * Handles version strings like "11.10.0", "11.10", ">=11.10.0".
 */
function semverAtLeast(actual, required) {
  const clean = (v) => v.replace(/[^0-9.]/g, '')
  const parts = (v) => clean(v).split('.').map((n) => parseInt(n, 10) || 0)
  const [aMaj, aMin, aPatch] = parts(actual)
  const [rMaj, rMin, rPatch] = parts(required)
  if (aMaj !== rMaj) return aMaj > rMaj
  if (aMin !== rMin) return aMin > rMin
  return aPatch >= rPatch
}

/**
 * Normalises file content for comparison: trims trailing whitespace per line,
 * collapses multiple blank lines, strips leading/trailing blank lines.
 */
function normaliseContent(content) {
  return content
    .split('\n')
    .map((line) => line.trimEnd())
    .join('\n')
    .trim()
}

async function fetchText(url) {
  const token = process.env.GITHUB_TOKEN
  const headers = token ? { Authorization: `Bearer ${token}` } : {}
  const res = await fetch(url, { headers })
  if (!res.ok) throw new Error(`HTTP ${res.status} fetching ${url}`)
  return res.text()
}

// ── Checks ────────────────────────────────────────────────────────────────────

const checks = []

// 1. .nvmrc exists and specifies Node.js 24
const nvmrcPath = join(repoPath, '.nvmrc')
const nvmrcContent = readFile(nvmrcPath)
if (!nvmrcContent) {
  checks.push(result('nvmrc', '.nvmrc file', 'fail', '.nvmrc not found in repository root.'))
} else {
  const version = nvmrcContent.trim()
  // Accept "24", "v24", "24.x", "lts/jod" (Node.js 24 LTS codename)
  const isNode24 = /^v?24(\.|\b)/.test(version) || version === 'lts/jod'
  if (isNode24) {
    checks.push(result('nvmrc', '.nvmrc file', 'pass', `Specifies Node.js version: ${version}`))
  } else {
    checks.push(
      result(
        'nvmrc',
        '.nvmrc file',
        'fail',
        `.nvmrc specifies "${version}" but Node.js 24 is required. Update .nvmrc to contain "24".`,
      ),
    )
  }
}

// 2. package.json engines.npm >= 11.10
const packageJsonPath = join(repoPath, 'package.json')
const packageJsonContent = readFile(packageJsonPath)
const packageJson = packageJsonContent ? parseJson(packageJsonContent) : null

if (!packageJson) {
  checks.push(
    result('engines-npm', 'package.json engines.npm', 'fail', 'package.json not found or invalid JSON.'),
  )
} else {
  const npmRange = packageJson?.engines?.npm
  if (!npmRange) {
    checks.push(
      result(
        'engines-npm',
        'package.json engines.npm',
        'fail',
        'No engines.npm field in package.json. Add "engines": { "npm": ">=11.10.0" }.',
      ),
    )
  } else {
    // Extract lowest version from range like ">=11.10.0", "^11.10", "11.10.0"
    const versionMatch = npmRange.match(/(\d[\d.]*)/)
    const version = versionMatch ? versionMatch[1] : '0'
    if (semverAtLeast(version, '11.10.0')) {
      checks.push(
        result('engines-npm', 'package.json engines.npm', 'pass', `engines.npm is set to "${npmRange}".`),
      )
    } else {
      checks.push(
        result(
          'engines-npm',
          'package.json engines.npm',
          'fail',
          `engines.npm is "${npmRange}" but npm >= 11.10.0 is required.`,
        ),
      )
    }
  }
}

// 3. package.json engines.node targets Node.js 24
if (!packageJson) {
  checks.push(
    result('engines-node', 'package.json engines.node', 'fail', 'package.json not found or invalid JSON.'),
  )
} else {
  const nodeRange = packageJson?.engines?.node
  if (!nodeRange) {
    checks.push(
      result(
        'engines-node',
        'package.json engines.node',
        'fail',
        'No engines.node field in package.json. Add "engines": { "node": ">=24.0.0" }.',
      ),
    )
  } else {
    const versionMatch = nodeRange.match(/(\d[\d.]*)/)
    const version = versionMatch ? versionMatch[1] : '0'
    const majorVersion = parseInt(version.split('.')[0], 10)
    if (majorVersion === 24) {
      checks.push(
        result(
          'engines-node',
          'package.json engines.node',
          'pass',
          `engines.node is set to "${nodeRange}".`,
        ),
      )
    } else {
      checks.push(
        result(
          'engines-node',
          'package.json engines.node',
          'fail',
          `engines.node is "${nodeRange}" but Node.js 24 (e.g. ">=24.0.0") is required.`,
        ),
      )
    }
  }
}

// 4. .npmrc content matches template
const npmrcPath = join(repoPath, '.npmrc')
const npmrcContent = readFile(npmrcPath)

let templateNpmrc = null
try {
  templateNpmrc = await fetchText(
    'https://raw.githubusercontent.com/ministryofjustice/hmpps-template-typescript/main/.npmrc',
  )
} catch (err) {
  checks.push(
    result(
      'npmrc',
      '.npmrc file',
      'warn',
      `Could not fetch template .npmrc for comparison: ${err.message}`,
    ),
  )
}

if (templateNpmrc !== null) {
  if (!npmrcContent) {
    checks.push(result('npmrc', '.npmrc file', 'fail', '.npmrc not found in repository root.'))
  } else if (normaliseContent(npmrcContent) === normaliseContent(templateNpmrc)) {
    checks.push(result('npmrc', '.npmrc file', 'pass', '.npmrc content matches the HMPPS template.'))
  } else {
    checks.push(
      result(
        'npmrc',
        '.npmrc file',
        'fail',
        '.npmrc exists but its content does not match the HMPPS template at https://github.com/ministryofjustice/hmpps-template-typescript/blob/main/.npmrc',
      ),
    )
  }
}

// 5. GitHub Actions enabled
let actionsEnabled = null
try {
  const remote = execSync('git -C ' + JSON.stringify(repoPath) + ' remote get-url origin', {
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
  }).trim()

  // Extract owner/repo from remote URL (https or ssh)
  const match = remote.match(/[:/]([^/]+)\/([^/]+?)(?:\.git)?$/)
  if (match) {
    const [, owner, repo] = match
    const output = execSync(
      `gh api repos/${owner}/${repo}/actions/permissions --jq '.enabled'`,
      { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] },
    ).trim()
    actionsEnabled = output === 'true'
    if (actionsEnabled) {
      checks.push(
        result('actions-enabled', 'GitHub Actions enabled', 'pass', `GitHub Actions are enabled for ${owner}/${repo}.`),
      )
    } else {
      checks.push(
        result(
          'actions-enabled',
          'GitHub Actions enabled',
          'fail',
          `GitHub Actions are disabled for ${owner}/${repo}. Enable them in the repository settings under Actions > General.`,
        ),
      )
    }
  } else {
    checks.push(
      result('actions-enabled', 'GitHub Actions enabled', 'warn', `Could not parse repository remote URL: ${remote}`),
    )
  }
} catch (err) {
  checks.push(
    result(
      'actions-enabled',
      'GitHub Actions enabled',
      'warn',
      `Could not check GitHub Actions status (is gh CLI authenticated?): ${err.message}`,
    ),
  )
}

// 6–9. Required security workflow files
const requiredWorkflows = [
  {
    id: 'workflow-codeql',
    filename: 'security_codeql_actions_scan.yml',
    label: 'CodeQL actions scan workflow',
    reusableWorkflow: 'hmpps-github-actions/.github/workflows/security_codeql_actions.yml',
  },
  {
    id: 'workflow-npm-dependency',
    filename: 'security_npm_dependency.yml',
    label: 'npm dependency scan workflow',
    reusableWorkflow: 'hmpps-github-actions/.github/workflows/security_npm_dependency.yml',
  },
  {
    id: 'workflow-veracode-pipeline',
    filename: 'security_veracode_pipeline_scan.yml',
    label: 'Veracode pipeline scan workflow',
    reusableWorkflow: 'hmpps-github-actions/.github/workflows/security_veracode_pipeline_scan.yml',
  },
  {
    id: 'workflow-veracode-policy',
    filename: 'security_veracode_policy_scan.yml',
    label: 'Veracode policy scan workflow',
    reusableWorkflow: 'hmpps-github-actions/.github/workflows/security_veracode_policy_scan.yml',
  },
]

for (const wf of requiredWorkflows) {
  const wfPath = join(repoPath, '.github', 'workflows', wf.filename)
  const wfContent = readFile(wfPath)
  if (!wfContent) {
    checks.push(
      result(
        wf.id,
        wf.label,
        'fail',
        `${wf.filename} not found in .github/workflows/. This workflow provides scheduled ${wf.label}.`,
      ),
    )
  } else if (!wfContent.includes(wf.reusableWorkflow)) {
    checks.push(
      result(
        wf.id,
        wf.label,
        'warn',
        `${wf.filename} exists but does not reference the expected reusable workflow "${wf.reusableWorkflow}@v2". Review the file manually.`,
      ),
    )
  } else {
    const hasSchedule = wfContent.includes('schedule:') && wfContent.includes('cron:')
    if (hasSchedule) {
      checks.push(result(wf.id, wf.label, 'pass', `${wf.filename} is present with a scheduled trigger.`))
    } else {
      checks.push(
        result(
          wf.id,
          wf.label,
          'warn',
          `${wf.filename} exists but has no scheduled cron trigger. Add a schedule to ensure regular security scans.`,
        ),
      )
    }
  }
}

// 10. node_modules in .gitignore
const gitignorePath = join(repoPath, '.gitignore')
const gitignoreContent = readFile(gitignorePath)
if (!gitignoreContent) {
  checks.push(
    result('gitignore-node-modules', '.gitignore excludes node_modules', 'fail', '.gitignore not found.'),
  )
} else {
  const lines = gitignoreContent.split('\n').map((l) => l.trim())
  if (lines.some((l) => l === 'node_modules' || l === 'node_modules/')) {
    checks.push(
      result(
        'gitignore-node-modules',
        '.gitignore excludes node_modules',
        'pass',
        'node_modules is excluded in .gitignore.',
      ),
    )
  } else {
    checks.push(
      result(
        'gitignore-node-modules',
        '.gitignore excludes node_modules',
        'fail',
        '.gitignore does not exclude node_modules. Add "node_modules" to .gitignore.',
      ),
    )
  }
}

// 11. .env in .gitignore
if (!gitignoreContent) {
  checks.push(
    result('gitignore-env', '.gitignore excludes .env', 'fail', '.gitignore not found.'),
  )
} else {
  const lines = gitignoreContent.split('\n').map((l) => l.trim())
  if (lines.some((l) => l === '.env' || l === '.env*' || l === '*.env')) {
    checks.push(
      result('gitignore-env', '.gitignore excludes .env', 'pass', '.env files are excluded in .gitignore.'),
    )
  } else {
    checks.push(
      result(
        'gitignore-env',
        '.gitignore excludes .env',
        'fail',
        '.gitignore does not exclude .env files. Add ".env" to .gitignore to prevent accidentally committing secrets.',
      ),
    )
  }
}

// 12. Dockerfiles copy .npmrc into the build
function findDockerfiles(dir) {
  try {
    return readdirSync(dir)
      .filter((f) => f === 'Dockerfile' || f.startsWith('Dockerfile.') || f.endsWith('.dockerfile'))
      .map((f) => join(dir, f))
  } catch {
    return []
  }
}

const dockerfiles = findDockerfiles(repoPath)

if (dockerfiles.length === 0) {
  checks.push(
    result(
      'dockerfile-npmrc',
      'Dockerfile copies .npmrc',
      'warn',
      'No Dockerfile found in the repository root. If this project is containerised, ensure .npmrc is copied into the build stage.',
    ),
  )
} else {
  for (const dockerfilePath of dockerfiles) {
    const filename = dockerfilePath.split('/').pop()
    const content = readFile(dockerfilePath)
    if (!content) continue

    const usesNpm = /\bnpm\s+(install|ci|run)\b/.test(content)
    const copiesNpmrc = /^COPY\s+[^\n]*\.npmrc/m.test(content)

    if (!usesNpm) {
      // Dockerfile doesn't run npm at all — not applicable
      checks.push(
        result(
          'dockerfile-npmrc',
          'Dockerfile copies .npmrc',
          'warn',
          `${filename} does not appear to run npm, so .npmrc may not be required. Review manually if npm is invoked indirectly.`,
        ),
      )
    } else if (copiesNpmrc) {
      checks.push(
        result(
          'dockerfile-npmrc',
          'Dockerfile copies .npmrc',
          'pass',
          `${filename} copies .npmrc into the build.`,
        ),
      )
    } else {
      checks.push(
        result(
          'dockerfile-npmrc',
          'Dockerfile copies .npmrc',
          'fail',
          `${filename} runs npm but does not copy .npmrc. Add ".npmrc" to the COPY instruction before your npm install step, for example: COPY package*.json .npmrc ./`,
        ),
      )
    }
  }
}

// ── Output ────────────────────────────────────────────────────────────────────

console.log(JSON.stringify(checks, null, 2))

const hasFailures = checks.some((c) => c.status === 'fail')
process.exit(hasFailures ? 1 : 0)
