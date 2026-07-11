#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-or-later

import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

const timeoutMs = Number.parseInt(process.env.BROWSER_SMOKE_TIMEOUT_MS || '15000', 10);
const firstPort = 43000 + Math.floor(Math.random() * 900);
const sourceCodeUrl = 'https://example.invalid/browser-smoke-source';
const appVersion = 'browser-smoke-version';
const requiredAssets = ['/style.css', '/app.js', '/htmx.min.js'];
const expectedContentSecurityPolicy = "default-src 'self'; base-uri 'none'; connect-src 'self'; form-action 'self'; frame-ancestors 'none'; img-src 'self'; object-src 'none'; script-src 'self'; style-src 'self'";

function loadPlaywright() {
  const explicitPath = process.env.PLAYWRIGHT_CORE_PATH;
  if (explicitPath) return require(explicitPath);

  try {
    return require('playwright-core');
  } catch (_coreError) {
    return require('playwright');
  }
}

const { chromium } = loadPlaywright();

function wait(ms) { return new Promise((resolve) => setTimeout(resolve, ms)); }

function startServer({ name, port, server }) {
  const env = {
    ...process.env,
    PORT: String(port),
    SOURCE_CODE_URL: sourceCodeUrl,
    APP_VERSION: appVersion,
  };
  if (server === undefined) delete env.SERVER;
  else env.SERVER = server;

  const child = spawn('sbcl', ['--script', 'scripts/run.lisp'], {
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  let exit = null;
  let spawnError = null;
  let closed = false;
  child.once('exit', (code, signal) => { exit = { code, signal }; });
  const closedPromise = new Promise((resolve) => {
    child.once('close', (code, signal) => {
      if (!exit) exit = { code, signal };
      closed = true;
      resolve();
    });
  });
  child.stdout.on('data', (chunk) => { output += chunk; });
  child.stderr.on('data', (chunk) => { output += chunk; });
  child.once('error', (error) => { spawnError = error; });
  return {
    name,
    child,
    output: () => output,
    exit: () => exit,
    spawnError: () => spawnError,
    closed: () => closed,
    closedPromise,
  };
}

async function stopServer(server) {
  if (server.exit() || server.closed()) return;
  server.child.kill('SIGTERM');
  const stopped = await Promise.race([
    server.closedPromise.then(() => true),
    wait(2000).then(() => false),
  ]);
  if (stopped || server.exit() || server.closed()) return;

  server.child.kill('SIGKILL');
  const killed = await Promise.race([
    server.closedPromise.then(() => true),
    wait(2000).then(() => false),
  ]);
  if (!killed && !server.exit() && !server.closed()) {
    throw new Error(`Server process did not stop after SIGKILL: ${server.name}`);
  }
}

async function waitForHealth(server, baseUrl) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (server.spawnError()) {
      throw new Error(`Failed to start server: ${server.spawnError().message}`);
    }
    if (server.exit()) {
      throw new Error(`Server exited before becoming healthy: ${JSON.stringify(server.exit())}`);
    }
    try {
      const response = await fetch(`${baseUrl}/health`, { signal: AbortSignal.timeout(1000) });
      if (response.ok && (await response.text()) === 'ok\n') return;
    } catch (_error) {}
    await wait(250);
  }
  throw new Error(`Timed out after ${timeoutMs}ms waiting for ${baseUrl}/health`);
}

function assertEqual(actual, expected, message) {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}
function assertMainNavigationResponse(response, name) {
  if (!response) {
    throw new Error(`${name} main navigation returned no HTTP response`);
  }
  if (!response.ok()) {
    throw new Error(`${name} main navigation returned HTTP ${response.status()} ${response.statusText()}`);
  }

  const headers = response.headers();
  const policy = headers['content-security-policy'];
  if (!policy) {
    const reportOnly = headers['content-security-policy-report-only'];
    const detail = reportOnly
      ? `; report-only policy does not enforce protection: ${JSON.stringify(reportOnly)}`
      : '';
    throw new Error(`${name} main navigation missing enforced Content-Security-Policy header${detail}`);
  }
  assertEqual(
    policy,
    expectedContentSecurityPolicy,
    `${name} main navigation enforced Content-Security-Policy`,
  );
}

async function runScenario({ name, port, server: serverBackend }) {
  const baseUrl = `http://127.0.0.1:${port}`;
  const server = startServer({ name, port, server: serverBackend });
  let browser;
  let failure;
  const diagnostics = [`Scenario: ${name} (${baseUrl})`];

  try {
    await waitForHealth(server, baseUrl);
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport: { width: 1024, height: 768 } });
    const unexpected = [];
    const requestedAssets = new Set();
    const assetFailures = [];

    await page.addInitScript(() => {
      globalThis.__browserSmokeCspViolations = [];
      document.addEventListener('securitypolicyviolation', (event) => {
        globalThis.__browserSmokeCspViolations.push({
          blockedURI: event.blockedURI,
          violatedDirective: event.violatedDirective,
        });
      });
    });
    page.on('request', (request) => {
      const url = request.url();
      if (!url.startsWith(`${baseUrl}/`) && url !== baseUrl) unexpected.push(url);
      try {
        const parsed = new URL(url);
        if (parsed.origin === baseUrl && requiredAssets.includes(parsed.pathname)) {
          requestedAssets.add(parsed.pathname);
        }
      } catch (_error) {}
    });
    page.on('requestfailed', (request) => {
      const parsed = new URL(request.url());
      if (parsed.origin === baseUrl && requiredAssets.includes(parsed.pathname)) {
        assetFailures.push(`${parsed.pathname} request failed: ${request.failure()?.errorText || 'unknown error'}`);
      }
    });
    page.on('response', (response) => {
      const parsed = new URL(response.url());
      if (parsed.origin === baseUrl
          && requiredAssets.includes(parsed.pathname)
          && (response.status() < 200 || response.status() >= 300)) {
        assetFailures.push(`${parsed.pathname} returned HTTP ${response.status()}`);
      }
    });

    const navigationResponse = await page.goto(baseUrl, { waitUntil: 'networkidle', timeout: timeoutMs });
    assertMainNavigationResponse(navigationResponse, name);
    await page.getByRole('heading', { name: 'Common Lisp Web App' }).waitFor({ timeout: timeoutMs });

    const expectedLinks = [
      ['Health', `${baseUrl}/health`],
      ['Version', `${baseUrl}/version`],
      ['Source', sourceCodeUrl],
    ];
    for (const [label, expectedHref] of expectedLinks) {
      const link = page.getByRole('link', { name: label, exact: true });
      await link.waitFor({ timeout: timeoutMs });
      assertEqual(await link.evaluate((element) => element.href), expectedHref, `${name} ${label} destination`);
    }

    const endpoints = await page.evaluate(async () => {
      const read = async (path) => {
        const response = await fetch(path);
        return {
          status: response.status,
          contentType: response.headers.get('content-type'),
          body: await response.text(),
        };
      };
      return { health: await read('/health'), version: await read('/version') };
    });
    assertEqual(endpoints.health.status, 200, `${name} Health status`);
    assertEqual(endpoints.health.contentType, 'text/plain; charset=utf-8', `${name} Health content type`);
    assertEqual(endpoints.health.body, 'ok\n', `${name} Health body`);
    assertEqual(endpoints.version.status, 200, `${name} Version status`);
    assertEqual(endpoints.version.contentType, 'text/plain; charset=utf-8', `${name} Version content type`);
    assertEqual(endpoints.version.body, `${appVersion}\n`, `${name} Version body`);

    for (const asset of requiredAssets) {
      if (!requestedAssets.has(asset)) assetFailures.push(`${asset} was not requested`);
    }
    if (assetFailures.length > 0) throw new Error(assetFailures.join('; '));

    const clientState = await page.evaluate(() => ({
      appReady: document.documentElement.dataset.appReady,
      htmxLoaded: Boolean(globalThis.htmx) && typeof globalThis.htmx.on === 'function',
      cspViolations: globalThis.__browserSmokeCspViolations,
    }));
    assertEqual(clientState.appReady, 'true', `${name} first-party app.js marker`);
    assertEqual(clientState.htmxLoaded, true, `${name} htmx API availability`);
    if (clientState.cspViolations.length > 0) {
      throw new Error(`${name} CSP violations: ${JSON.stringify(clientState.cspViolations)}`);
    }

    const box = await page.locator('.shell').boundingBox();
    if (!box || box.width < 300 || box.height < 180) {
      throw new Error(`${name} shell rendered too small: ${JSON.stringify(box)}`);
    }
    if (unexpected.length > 0) {
      throw new Error(`${name} unexpected external requests: ${unexpected.join(', ')}`);
    }
  } catch (error) {
    failure = error;
  } finally {
    const cleanup = await Promise.allSettled([
      browser ? browser.close() : Promise.resolve(),
      stopServer(server),
    ]);
    for (const result of cleanup) {
      if (result.status === 'rejected') diagnostics.push(`Cleanup failure: ${result.reason}`);
    }
    if (!failure) {
      const cleanupFailure = cleanup.find((result) => result.status === 'rejected');
      if (cleanupFailure) failure = cleanupFailure.reason;
    }
  }

  if (failure) {
    diagnostics.push(`Recent server output:\n${server.output()}`);
    console.error(diagnostics.join('\n'));
    throw failure;
  }
  console.log(`Browser smoke passed: ${name}.`);
}

async function main() {
  const scenarios = [
    { name: 'default Woo', port: firstPort },
    { name: 'Hunchentoot fallback', port: firstPort + 1, server: 'hunchentoot' },
  ];
  const failures = [];

  for (const scenario of scenarios) {
    try {
      await runScenario(scenario);
    } catch (error) {
      failures.push(error);
    }
  }

  if (failures.length > 0) {
    throw new AggregateError(failures, `${failures.length} browser smoke scenario(s) failed`);
  }
}

main().catch((error) => { console.error(error); process.exitCode = 1; });
