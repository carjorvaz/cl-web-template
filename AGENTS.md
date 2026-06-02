# Agent Map

This template is optimized for small, verifiable agent runs. Keep this file as
a map, not a manual; durable detail lives in `docs/`.

## Start Here

1. Read `README.md` for run and test commands.
2. Read `docs/README.md` to choose the right deeper document.
3. Prefer the `just` menu from inside the Nix shell: `nix develop -c just --list`.
4. Run `nix develop -c just test` after code changes.
5. Run `nix develop -c just build-assets` after editing `assets/style.lass`.
6. Run `nix develop -c just assets` after changing assets.
7. Run `nix develop -c just architecture` after changing source boundaries.
8. Run `nix develop -c just docs` after changing docs or guidance.
9. Run `nix develop -c just browser-smoke` after UI changes.
10. Run `nix develop -c just template-smoke` after changing template shape, repo metadata, or copyability assumptions.

## Source Of Truth

- `docs/ARCHITECTURE.md` describes module boundaries.
- `docs/HARNESS.md` records agent-first harness and Common Lisp taste.
- `docs/PRODUCT.md` describes the app contract.
- `docs/RELIABILITY.md` describes runtime and validation expectations.
- `docs/QUALITY.md` tracks verification coverage and known gaps.
- `docs/PLANS.md` explains when to create execution plans.
- `docs/TEMPLATE.md` defines the template contract and deviation policy.
- `docs/technical-debt.md` records focused cleanup work.
- `justfile` is the ergonomic command menu; keep the real validation logic in scripts and Nix.

## Architecture Rules

- Keep domain behavior in `src/domain.lisp`.
- Keep request parsing, HTTP responses, rendering, and static assets in `src/web.lisp`.
- Do not make `src/domain.lisp` depend on Clack, Lack, Ningle, Spinneret, CSS, or browser assets.
- Treat `assets/style.lass` as the source for `static/style.css`.

## Feedback Loop

If an agent learns a reusable rule while fixing a bug, encode it in the repo:
update a focused doc, add a test, or extend a validation script.
