#!/usr/bin/env node
// Lists GitHub Actions workflows that call the shared HMPPS workflows relevant to the ECR migration,
// and other places that still reference ghcr.io. Read-only; prints JSON to stdout.
// Usage: node find-workflows.mjs [repo-root]
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, relative } from 'node:path'

const root = process.argv[2] || process.cwd()
const SHARED = /ministryofjustice\/hmpps-github-actions\/\.github\/workflows\/([\w-]+)\.ya?ml@(\S+)/
const TARGETS = new Set([
  'docker_build', 'docker_push', 'docker_build_ecr', 'docker_push_ecr',
  'deploy_env', 'deploy_to_env',
  'security_snyk_scan', 'security_snyk_scan_ecr',
])
const SKIP_DIRS = new Set(['.git', 'node_modules', 'build', 'dist', 'out', '.gradle', 'target'])

const sharedCalls = []
const ghcrReferences = []

const walk = dir => {
  for (const name of readdirSync(dir)) {
    if (SKIP_DIRS.has(name)) continue
    const full = join(dir, name)
    const stats = statSync(full)
    if (stats.isDirectory()) {
      walk(full)
      continue
    }
    if (stats.size > 1_000_000) continue
    const rel = relative(root, full)
    const isWorkflow = /^\.github\/workflows\/.+\.ya?ml$/.test(rel)
    let lines
    try {
      lines = readFileSync(full, 'utf8').split('\n')
    } catch {
      continue
    }
    lines.forEach((text, i) => {
      if (isWorkflow) {
        const m = text.match(SHARED)
        if (m && TARGETS.has(m[1])) {
          sharedCalls.push({ file: rel, line: i + 1, workflow: m[1], ref: m[2], commented: text.trim().startsWith('#') })
        }
      }
      if (/ghcr\.io/i.test(text)) ghcrReferences.push({ file: rel, line: i + 1, text: text.trim() })
    })
  }
}

walk(root)
console.log(JSON.stringify({ sharedCalls, ghcrReferences }, null, 2))
