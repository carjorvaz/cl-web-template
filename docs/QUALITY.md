# Quality

Last reviewed: 2026-06-01

## Current Grade

Separated template baseline: enough tests and validators exist to prove the
neutral app runs, renders, validates docs/assets/source boundaries, passes a
browser smoke check, and remains copyable as a standalone template.

## Verification Matrix

- Domain behavior: `test/domain-tests.lisp`.
- Web rendering: `test/web-tests.lisp`.
- Full Lisp suite: `scripts/test.lisp`.
- Asset freshness: `scripts/validate-assets.lisp`.
- Source boundaries: `scripts/validate-architecture.lisp`.
- Repository guidance: `scripts/validate-docs.lisp`.
- Browser behavior: `scripts/browser-smoke.mjs`.
- Template copyability: `scripts/template-smoke.mjs`.
- Packaged deterministic checks: `nix flake check`.
- Packaged browser/template checks: `nix run .#browser-smoke` and
  `nix run .#template-smoke`.

## Known Gaps

- This scaffold intentionally starts small; add app-specific tests as product behavior grows.
- Manual screen-reader review is not a routine gate for private scaffold work.
- The default template is literal, not a parameter-substituting generator.
