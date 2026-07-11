#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later

import {
  chmod,
  copyFile,
  lstat,
  mkdir,
  mkdtemp,
  readdir,
  rm,
} from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { isAbsolute, join, relative, resolve, sep } from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(fileURLToPath(new URL('..', import.meta.url)));

const requiredFiles = [
  '.envrc',
  '.github/workflows/ci.yml',
  '.gitignore',
  'AGENTS.md',
  'LICENSE',
  'README.md',
  'app.asd',
  'justfile',
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
  'test/package.lisp',
  'test/domain-tests.lisp',
  'test/web-tests.lisp',
];

const excludedRoots = new Set(['.git', '.jj', '.hermes', '.direnv', 'result']);

function isExcludedRoot(name) {
  return excludedRoots.has(name) || name.startsWith('result-');
}

function isInside(root, path) {
  const rel = relative(root, path);
  return rel !== '..' && !rel.startsWith(`..${sep}`) && !isAbsolute(rel);
}

function run(command, args, cwd, env) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, args, {
      cwd,
      env,
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

async function copyRegularFile(source, destination, info) {
  await copyFile(source, destination);
  await chmod(destination, info.mode & 0o777);
}

async function copyPublishedEntry(source, destination) {
  const info = await lstat(source);
  if (info.isSymbolicLink()) {
    throw new Error(`Template source contains an unsupported symbolic link: ${source}`);
  }
  if (info.isDirectory()) {
    await mkdir(destination, { mode: 0o700 });
    const entries = await readdir(source);
    for (const entry of entries) {
      await copyPublishedEntry(join(source, entry), join(destination, entry));
    }
    await chmod(destination, info.mode & 0o777);
    return;
  }
  if (!info.isFile()) {
    throw new Error(`Template source contains an unsupported file type: ${source}`);
  }
  await copyRegularFile(source, destination, info);
}

async function copyPublishedTree(workspace) {
  const entries = await readdir(repoRoot);
  for (const entry of entries) {
    if (!isExcludedRoot(entry)) {
      await copyPublishedEntry(join(repoRoot, entry), join(workspace, entry));
    }
  }
}

async function trackedFiles() {
  const gitMetadata = join(repoRoot, '.git');
  const metadataInfo = await lstat(gitMetadata);
  if (metadataInfo.isSymbolicLink()) {
    throw new Error(`Template source contains an unsupported symbolic link: ${gitMetadata}`);
  }
  const { stdout } = await run(
    'git',
    ['-C', repoRoot, 'ls-files', '-z', '--cached'],
    repoRoot,
    { PATH: process.env.PATH || '/usr/bin:/bin:/usr/sbin:/sbin' },
  );
  return stdout.split('\0').filter(Boolean);
}

async function inspectTrackedPath(relativePath) {
  if (relativePath.split('/').some((part) => part === '' || part === '.' || part === '..')) {
    throw new Error(`Git reported an unsafe tracked path: ${relativePath}`);
  }
  const source = resolve(repoRoot, relativePath);
  if (!isInside(repoRoot, source)) {
    throw new Error(`Git reported a tracked path outside the template: ${relativePath}`);
  }

  let current = repoRoot;
  const directories = [];
  for (const part of relativePath.split('/')) {
    current = join(current, part);
    let info;
    try {
      info = await lstat(current);
    } catch (error) {
      if (error.code === 'ENOENT') return null;
      throw error;
    }
    if (info.isSymbolicLink()) {
      throw new Error(`Template source contains an unsupported symbolic link: ${current}`);
    }
    if (current !== source) {
      if (!info.isDirectory()) {
        throw new Error(`Tracked path has a non-directory parent: ${relativePath}`);
      }
      directories.push({ path: current, mode: info.mode });
    } else if (!info.isFile()) {
      throw new Error(`Tracked path is not a regular file: ${relativePath}`);
    }
  }
  return { source, info: await lstat(source), directories };
}

async function copyTrackedTree(workspace) {
  const directoryModes = new Map();
  for (const relativePath of await trackedFiles()) {
    const inspected = await inspectTrackedPath(relativePath);
    if (inspected === null) continue;

    for (const directory of inspected.directories) {
      const rel = relative(repoRoot, directory.path);
      const destination = join(workspace, rel);
      await mkdir(destination, { recursive: true, mode: 0o700 });
      directoryModes.set(destination, directory.mode);
    }
    const destination = resolve(workspace, relativePath);
    if (!isInside(workspace, destination)) {
      throw new Error(`Git reported an unsafe tracked path: ${relativePath}`);
    }
    await copyRegularFile(inspected.source, destination, inspected.info);
  }

  const directories = [...directoryModes.entries()]
    .sort(([left], [right]) => right.length - left.length);
  for (const [directory, mode] of directories) {
    await chmod(directory, mode & 0o777);
  }
}

async function copyTemplate(workspace) {
  let gitMetadata;
  try {
    gitMetadata = await lstat(join(repoRoot, '.git'));
  } catch (error) {
    if (error.code === 'ENOENT') {
      await copyPublishedTree(workspace);
      return;
    }
    throw error;
  }
  if (gitMetadata.isSymbolicLink()) {
    throw new Error(`Template source contains an unsupported symbolic link: ${join(repoRoot, '.git')}`);
  }
  await copyTrackedTree(workspace);
}

async function validationEnvironment(runtimeRoot) {
  const home = join(runtimeRoot, 'home');
  const temp = join(runtimeRoot, 'tmp');
  const cache = join(runtimeRoot, 'cache');
  const config = join(runtimeRoot, 'config');
  const data = join(runtimeRoot, 'data');
  await Promise.all([home, temp, cache, config, data].map(
    (path) => mkdir(path, { recursive: true, mode: 0o700 }),
  ));

  const env = {
    HOME: home,
    TMPDIR: temp,
    TMP: temp,
    TEMP: temp,
    XDG_CACHE_HOME: cache,
    XDG_CONFIG_HOME: config,
    XDG_DATA_HOME: data,
    PATH: process.env.PATH || '/usr/bin:/bin:/usr/sbin:/sbin',
  };
  for (const name of [
    'LANG',
    'LC_ALL',
    'LC_CTYPE',
    'LOGNAME',
    'NIX_REMOTE',
    'NIX_SSL_CERT_FILE',
    'SSL_CERT_FILE',
    'USER',
  ]) {
    if (process.env[name]) env[name] = process.env[name];
  }
  return env;
}

async function makeWritable(path) {
  const info = await lstat(path);
  if (info.isSymbolicLink()) return;
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
  let runtimeRoot;
  try {
    runtimeRoot = await mkdtemp(join(tmpdir(), 'cl-web-template-runtime-'));
    await copyTemplate(workspace);
    const childEnv = await validationEnvironment(runtimeRoot);
    const commands = [
      ['nix', ['develop', '-c', 'sbcl', '--script', 'scripts/validate-docs.lisp']],
      ['nix', ['develop', '-c', 'sbcl', '--script', 'scripts/validate-assets.lisp']],
      ['nix', ['develop', '-c', 'sbcl', '--script', 'scripts/test.lisp']],
      ['nix', ['develop', '-c', 'sbcl', '--script', 'scripts/validate-architecture.lisp']],
    ];
    for (const [command, args] of commands) {
      await run(command, args, workspace, childEnv);
    }
    console.log(`Template smoke passed in ${workspace}`);
  } finally {
    if (runtimeRoot) {
      await makeWritable(runtimeRoot).catch(() => {});
      await rm(runtimeRoot, { recursive: true, force: true });
    }
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
