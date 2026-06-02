# Common Lisp Web Template Contract

Last reviewed: 2026-06-01

This document is the source-of-truth contract for the template. It records the
stack, repository shape, feedback loop, and deviation policy that future apps
inherit when they start from this repository.

## Purpose

The template makes the boring parts of a serious small Common Lisp web app
repeatable:

- start from a pinned local development shell;
- render real HTML on the server;
- keep domain logic independent from HTTP and CSS;
- author CSS in Lisp source form and serve generated static assets;
- validate boundaries, docs, assets, behavior, and browser output with a
  deterministic feedback loop;
- keep repo-local guidance legible to future agents.

The goal is not to put every byte in Lisp. The goal is to keep the application
model, HTML rendering, CSS source, and verification harness close to Lisp while
using small browser-native pieces where they are the simpler public contract.

## Stack

- `SBCL` as the primary implementation.
- `ASDF` systems for app, assets, and tests.
- `Nix` for a reproducible shell, checks, and CI.
- `Clack` for the HTTP application boundary.
- `Lack` for middleware.
- `ningle` for small route dispatch.
- `Spinneret` for server-rendered HTML.
- `LASS` for authored CSS, compiled into `static/style.css`.
- `Woo` as the default local/deployed backend.
- `Hunchentoot` as a fallback backend and browser-smoke target.
- Vendored `htmx` for progressive enhancement.
- Small vanilla JavaScript only for browser behaviors HTML cannot provide.
- `FiveAM` for Lisp behavior tests.
- Playwright-driven browser smoke for layout and unexpected-request checks.

Coalton is optional. Use it for a compact pure rules slice only when types
clarify a domain kernel. Keep mutable app state and HTTP boundaries in ordinary
Common Lisp unless the typed island is pulling real weight.

## Repository Shape

A new app should begin with this layout:

```text
.
├── .envrc
├── .github/workflows/ci.yml
├── .gitignore
├── AGENTS.md
├── LICENSE
├── README.md
├── app.asd
├── justfile
├── assets/style.lass
├── docs/
│   ├── README.md
│   ├── ARCHITECTURE.md
│   ├── HARNESS.md
│   ├── PRODUCT.md
│   ├── QUALITY.md
│   ├── RELIABILITY.md
│   ├── PLANS.md
│   ├── TEMPLATE.md
│   └── technical-debt.md
├── flake.lock
├── flake.nix
├── scripts/
│   ├── asset-tools.lisp
│   ├── browser-smoke.mjs
│   ├── build-assets.lisp
│   ├── run.lisp
│   ├── template-smoke.mjs
│   ├── test.lisp
│   ├── validate-architecture.lisp
│   ├── validate-assets.lisp
│   └── validate-docs.lisp
├── src/
│   ├── domain.lisp
│   ├── package.lisp
│   └── web.lisp
├── static/
│   ├── app.js
│   ├── htmx.min.js
│   └── style.css
└── test/
    ├── domain-tests.lisp
    ├── package.lisp
    └── web-tests.lisp
```

Larger apps may split `src/domain.lisp` into more files, but keep layer order
and dependency direction explicit. The default layer order is:

`domain -> web`

If there is a pure rules kernel, use:

`rules -> domain -> web`

Compile-time dependencies point from adapters toward lower layers: web may use
domain, domain may use rules, and lower layers must not import web concerns.

## CSS Policy

Author CSS in `assets/style.lass`, compile it with
`scripts/build-assets.lisp`, and serve only generated CSS from `static/`.

Template defaults:

- keep selectors class-based and semantic;
- keep accessibility utility classes, such as `.visually-hidden`, in the base
  stylesheet;
- validate that `static/style.css` matches `assets/style.lass`;
- do not let web source files call `lass` or emit ad hoc inline styles.

## Hypermedia Contract

The template treats HTML as the public application protocol:

- `GET /` returns the full page.
- `GET /health` returns a plain readiness response.
- `GET /version` returns app identity and version.
- `POST` routes mutate server-side state and redirect for plain forms.
- htmx requests may receive fragments, but those fragments must remain valid
  server-rendered HTML.

Request parsing belongs at the web boundary. Domain functions should receive
validated Lisp values, not raw query strings, form strings, cookies, Clack envs,
or htmx headers.

## Verification Harness

The template is useful only if it carries the feedback loop with it:

- `scripts/test.lisp` runs unit and HTTP rendering tests.
- `scripts/build-assets.lisp` generates CSS.
- `scripts/validate-assets.lisp` rejects stale generated assets.
- `scripts/validate-architecture.lisp` enforces package direction and forbidden
  boundary references.
- `scripts/validate-docs.lisp` keeps the human map current.
- `scripts/browser-smoke.mjs` starts the app, probes `/health`, renders the home
  page, and rejects unexpected external requests.
- `scripts/template-smoke.mjs` copies the repository into a temporary app and
  runs that copied app's docs, assets, Lisp tests, and architecture checks.
- `justfile` is the ergonomic command menu; recipes call the same scripts and
  checks rather than duplicating validation logic.
- `nix flake check` runs the deterministic suite expected in CI.
- `nix run .#browser-smoke` and `nix run .#template-smoke` exercise browser and
  copyability paths from Nix-packaged source.

## Extraction And Reuse Rules

When starting a real app from this template:

- replace placeholder package/system/app names deliberately;
- keep `assets/style.lass` and `static/style.css` as the CSS source/generated
  pair;
- keep conservative security headers at the Clack boundary;
- keep the Hunchentoot backend smoke even when Woo is the default;
- keep docs validation from the start;
- keep `docs/HARNESS.md` as the place for agent-first feedback loops and Common
  Lisp taste rules;
- keep `scripts/template-smoke.mjs` green before changing the template surface;
- remove optional technology from the default starter unless a real product need
  justifies it;
- make the first screen the actual application, not a generic landing page, once
  the template is copied into a product repository.

## When To Deviate

Use a different stack only when the app has a real pressure this template does
not serve:

- use Parenscript only when browser-side behavior grows enough to need generated
  JavaScript or shared Lisp macros;
- use a database when session state is no longer enough;
- use richer routing only when route composition becomes a real maintenance
  problem;
- use WebSockets/SSE only when server-rendered HTML plus ordinary htmx/polling
  cannot provide the interaction model cleanly;
- use a frontend framework only when server-rendered HTML plus htmx cannot
  provide the interaction model cleanly.

Until then, prefer the small Common Lisp hypermedia stack. It is inspectable,
debuggable, and easy for future agents to validate.
