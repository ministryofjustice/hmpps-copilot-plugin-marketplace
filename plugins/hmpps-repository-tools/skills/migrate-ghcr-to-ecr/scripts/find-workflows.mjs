#!/usr/bin/env node
// Lists GitHub Actions workflows that call the shared HMPPS workflows relevant to the ECR migration,
// other places that still reference ghcr.io, and where `image.repository` sits in the Helm values
// (which gives the --set path for the deploy jobs). Read-only; prints JSON to stdout.
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
const helmImageRepositories = []

// Finds every `repository:` key whose parent key is `image`, and returns its full dotted path,
// for example `image.repository` or `generic-service.image.repository`. Line based, using indentation.
const findImageRepositories = (rel, lines) => {
  const stack = []
  lines.forEach((text, i) => {
    if (/^\s*(#|$)/.test(text) || /^\s*(---|\.\.\.)\s*$/.test(text)) return
    const m = text.match(/^(\s*)(-\s+)?(["']?)([\w.-]+)\3\s*:(?:\s+(.*?))?\s*$/)
    if (!m) return
    const indent = m[1].length + (m[2] || '').length
    while (stack.length && stack[stack.length - 1].indent >= indent) stack.pop()
    const key = m[4]
    const value = (m[5] || '').replace(/\s+#.*$/, '')
    if (key === 'repository' && stack.length && stack[stack.length - 1].key === 'image') {
      helmImageRepositories.push({ file: rel, line: i + 1, path: [...stack.map(s => s.key), key].join('.'), value })
    }
    if (!value || value.startsWith('#')) stack.push({ indent, key })
  })
}

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
    if (/^helm_deploy\/(.+\/)?values[^/]*\.ya?ml$/.test(rel)) findImageRepositories(rel, lines)
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
// The Helm --set path for the image repository: only set when exactly one distinct path is found.
const paths = [...new Set(helmImageRepositories.map(r => r.path))]
const helmSetPath = paths.length === 1 ? paths[0] : null
console.log(JSON.stringify({ sharedCalls, ghcrReferences, helmImageRepositories, helmSetPath }, null, 2))
