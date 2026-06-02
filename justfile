# Command menu for local development. Run inside `nix develop` or with `nix develop -c just <recipe>`.

_default:
    just --list

test:
    sbcl --script scripts/test.lisp

docs:
    sbcl --script scripts/validate-docs.lisp

architecture:
    sbcl --script scripts/validate-architecture.lisp

assets:
    sbcl --script scripts/validate-assets.lisp

build-assets:
    sbcl --script scripts/build-assets.lisp

jj-status:
    jj status

jj-diff:
    jj diff

jj-ops:
    jj op log

browser-smoke:
    node scripts/browser-smoke.mjs

template-smoke:
    node scripts/template-smoke.mjs

validate: test docs architecture assets

full: validate browser-smoke template-smoke
    nix flake check --print-build-logs
    nix run .#browser-smoke
    nix run .#template-smoke
