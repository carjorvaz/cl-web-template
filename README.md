# CL Web Template

A public, copyable Common Lisp web-app template for small server-rendered
hypermedia projects. It uses SBCL, ASDF, Nix, Clack/Lack/Ningle, Spinneret,
LASS, FiveAM, htmx, and Playwright.

This repository was split out of
[`carjorvaz/cl-ultimate-tic-tac-toe`](https://github.com/carjorvaz/cl-ultimate-tic-tac-toe)
after its in-repo scaffold self-smoke and CI stayed green. The default starter
is intentionally small: a domain layer, a web adapter, static assets, docs,
validators, tests, and browser smoke.

## Use It For A New App

Recommended path after this repository is marked as a GitHub template:

```sh
gh repo create my-common-lisp-app \
  --template carjorvaz/cl-web-template \
  --public \
  --clone
```

Or copy it locally:

```sh
cp -R /path/to/cl-web-template /path/to/my-common-lisp-app
cd /path/to/my-common-lisp-app
rm -rf .git
git init -b main
```

After copying, rename the app/system/package values listed in
[Template Parameters](#template-parameters), then run the validation loop before
adding product behavior.

## Run

```sh
direnv allow
sbcl --script scripts/run.lisp
```

or without enabling direnv:

```sh
nix develop -c sbcl --script scripts/run.lisp
```

The app listens on `http://127.0.0.1:4242/` by default. Set `PORT` to change
the port, `SERVER=hunchentoot` to use the fallback backend, `SOURCE_CODE_URL` to
change the footer link, and `APP_VERSION` to change `/version` output.

## Test

```sh
sbcl --script scripts/test.lisp
sbcl --script scripts/validate-docs.lisp
sbcl --script scripts/validate-architecture.lisp
sbcl --script scripts/validate-assets.lisp
node scripts/browser-smoke.mjs
node scripts/template-smoke.mjs
```

Regenerate CSS after editing `assets/style.lass`:

```sh
sbcl --script scripts/build-assets.lisp
```

Run all deterministic Nix checks with:

```sh
nix flake check
nix run .#template-smoke
nix run .#browser-smoke
```

## Template Parameters

The first copyable version is intentionally literal. Rename these values after
creating a real app from the template:

- app name: `Common Lisp Web App`;
- ASDF systems: `app`, `app/assets`, and `app/test`;
- package prefix: `app`, with packages such as `app.web`;
- executable/package name: `common-lisp-web-app`;
- default port: `4242`;
- source URL: default `https://github.com/carjorvaz/cl-web-template`, overridable
  by the `SOURCE_CODE_URL` environment variable;
- license: `AGPL-3.0-or-later` SPDX headers;
- optional features: Coalton, SQLite, WebSockets, and htmx SSE are not enabled
  by default.

## Required Shape

Keep the starter as an inspectable repository, not a hidden generator output:

- `.envrc`, `flake.nix`, `flake.lock`, `app.asd`, `README.md`, `LICENSE`, and
  `AGENTS.md`;
- focused docs under `docs/`;
- validation and run scripts under `scripts/`;
- Lisp source under `src/` and tests under `t/`;
- authored CSS in `assets/style.lass` and generated CSS in `static/style.css`;
- small static browser assets in `static/`;
- CI under `.github/workflows/` that runs the same public validation loop.

## Template Contract

`node scripts/template-smoke.mjs` copies this repository into a temporary app and
runs the local validation loop there. The copied app must pass without relying
on private paths, Ultimate Tic Tac Toe packages, generated chat history, or
credentials.

If a future generator replaces literal copying, it must preserve the same public
file layout and validation commands before adding parameter substitution.

See `docs/TEMPLATE.md` for the fuller design contract and deviation policy.

## Non-Goals

- Do not include Ultimate Tic Tac Toe rules, room state, or product behavior.
- Do not enable Coalton, SQLite, WebSockets, or SSE in the default starter.
- Do not hide normal Common Lisp files behind a clever generator.
- Do not make this a framework; keep it a small, inspectable starting point.

## Repository Knowledge

`AGENTS.md` is the short agent map. Durable project knowledge lives under
`docs/`.
