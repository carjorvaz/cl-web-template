#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later

import { mkdtemp, cp, rm, chmod, lstat, readdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, relative } from 'node:path';
import { spawn } from 'node:child_process';

const repoRoot = resolve(new URL('..', import.meta.url).pathname);

const requiredFiles = [
  '.envrc',
  '.github/workflows/ci.yml',
  '.gitignore',
  'AGENTS.md',
  'LICENSE',
  'README.md',
  'app.asd',
  'assets/style.lass',
  'docs/README.md',
  'docs/ARCHITECTURE.md',
  'docs/HARNESS.md',
  'docs/PRODUCT.md',
  'docs/RELIABILITY.md',
  'docs/QUALITY.md',
  'docs/PLANS.md',
  'docs/TEMPLATE.md',
  'docs/technical-debt.md',
  'flake.lock',
  'flake.nix',
  'scripts/asset-tools.lisp',
  'scripts/run.lisp',
  'scripts/test.lisp',
  'scripts/build-assets.lisp',
  'scripts/validate-assets.lisp',
  'scripts/validate-architecture.lisp',
  'scripts/validate-docs.lisp',
  'scripts/browser-smoke.mjs',
  'scripts/template-smoke.mjs',
  'src/package.lisp',
  'src/domain.lisp',
  'src/web.lisp',
  'static/app.js',
  'static/htmx.min.js',
  'static/style.css',
  't/package.lisp',
  't/domain-tests.lisp',
  't/web-tests.lisp',
];

const excludedRoots = new Set(['.git', '.direnv', 'result']);

function shouldCopy(sourcePath) {
  const rel = relative(repoRoot, sourcePath);
  if (rel === '') return true;
  const first = rel.split(/[\\/]/)[0];
  if (excludedRoots.has(first)) return false;
  return !first.startsWith('result-');
}

function run(command, args, cwd) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, args, {
      cwd,
      env: { ...process.env, HOME: process.env.HOME || tmpdir() },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) {
        resolvePromise({ stdout, stderr });
      } else {
        const error = new Error(`${command} ${args.join(' ')} failed with ${code}\n${stdout}\n${stderr}`);
        error.stdout = stdout;
        error.stderr = stderr;
        reject(error);
      }
    });
  });
}

async function makeWritable(path) {
  const info = await lstat(path);
  if (info.isDirectory()) {
    await chmod(path, 0o700);
    const entries = await readdir(path);
    await Promise.all(entries.map((entry) => makeWritable(join(path, entry))));
  } else {
    await chmod(path, 0o600);
  }
}

async function main() {
  const missing = requiredFiles.filter((relativePath) => !existsSync(join(repoRoot, relativePath)));
  if (missing.length > 0) {
    throw new Error(`Template repository is missing required files:\n- ${missing.join('\n- ')}`);
  }

  const workspace = await mkdtemp(join(tmpdir(), 'cl-web-template-'));
  try {
    await cp(repoRoot, workspace, { recursive: true, filter: shouldCopy });
    const commands = [
      ['nix', ['develop', '-c', 'sbcl', '--script', 'scripts/validate-docs.lisp']],
      ['nix', ['develop', '-c', 'sbcl', '--script', 'scripts/validate-assets.lisp']],
      ['nix', ['develop', '-c', 'sbcl', '--script', 'scripts/test.lisp']],
      ['nix', ['develop', '-c', 'sbcl', '--script', 'scripts/validate-architecture.lisp']],
    ];
    for (const [command, args] of commands) {
      await run(command, args, workspace);
    }
    console.log(`Template smoke passed in ${workspace}`);
  } finally {
    if (!process.env.TEMPLATE_SMOKE_KEEP_TMP) {
      await makeWritable(workspace).catch(() => {});
      await rm(workspace, { recursive: true, force: true });
    }
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
