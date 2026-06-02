# Harness And Engineering Taste

Last reviewed: 2026-06-02

This repository is an agent-first Common Lisp web-app scaffold.

## Agent-First Harness

- Keep `AGENTS.md` as a map, not a manual.
- Treat code, docs, tests, validators, and scripts as the system of record.
- Make validation commands obvious and runnable locally.
- Keep `justfile` as the ergonomic front door into scripts and Nix checks.
- Prefer short-lived, reviewable changes.
- Convert recurring review feedback into tests, docs, or validators.

## Local History

- Use Jujutsu (`jj`) as the default local history/editing interface for this
  personal template repo.
- Start agent runs with `nix develop -c just jj-status` and inspect local
  changes with `nix develop -c just jj-diff`.
- Keep Git/GitHub as the publication and compatibility layer: remotes, tags,
  CI visibility, and GitHub operations.
- After committing with JJ, explicitly move the publish bookmark before pushing,
  for example `nix develop -c jj bookmark move main --to @-`.

## Common Lisp Taste

- Prefer server-rendered HTML and ordinary form/link semantics.
- Keep domain logic independent from HTTP and rendering.
- Prefer plain functions, structs, and conditions before macros or frameworks.
- Keep package boundaries meaningful and mechanically checked.
- Use `test/` for the default test module in this template. This is a common,
  compact ASDF-era Lisp convention, but not a universal one; the important
  public affordance is that `app/test` and `just test` make the test suite
  obvious.
- Use dependencies when they improve clarity more than local code would.

## Feedback Loops

A good change updates the relevant test, validator, or document when it changes a durable rule.
