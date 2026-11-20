#!/usr/bin/env node
// Updates the default branch and creates the migration branch from it.
// Usage: node prepare-branch.mjs [branch-name]   (default: feat/migrate_build_deploy_to_ECR)
// Refuses to run with uncommitted changes, or if the branch already exists.
import { execFileSync } from 'node:child_process'

const branch = process.argv[2] || 'feat/migrate_build_deploy_to_ECR'

const git = (...args) => execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim()
const fail = msg => {
  console.error(msg)
  process.exit(1)
}

try {
  if (git('status', '--porcelain')) {
    fail('Working tree has uncommitted changes. Ask the developer to commit or stash them first.')
  }

  let defaultBranch = 'main'
  try {
    defaultBranch = git('symbolic-ref', '--short', 'refs/remotes/origin/HEAD').replace('origin/', '')
  } catch {
    // origin/HEAD not set; fall back to main
  }

  if (git('branch', '--list', branch)) {
    fail(`Branch ${branch} already exists locally. Ask the developer whether to reuse it or choose another name.`)
  }

  git('checkout', defaultBranch)
  git('pull', '--ff-only', 'origin', defaultBranch)
  git('checkout', '-b', branch)

  console.log(JSON.stringify({ ok: true, defaultBranch, branch, head: git('rev-parse', '--short', 'HEAD') }, null, 2))
} catch (e) {
  fail(`git command failed: ${e.stderr?.trim() || e.message}`)
}
