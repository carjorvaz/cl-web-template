# Close Review Findings

Status: completed

## Goal

Close every confirmed review finding without weakening the template's security headers, architecture boundaries, or copyability contract.

## Reliability implementation

- Make template copying operate on the published tracked file set, decode module URLs correctly, isolate HOME/environment, and reject or safely preserve symlinks without following them during cleanup.
- Make stylesheet generation collision-safe and replace the published CSS only after successful generation.
- Replace raw architecture checks with Lisp/ASDF-aware validation across all lower-layer source files.
- Validate real Markdown structure and recurse through Lisp sources for SPDX headers.
- Use a compliant focus outline and disable htmx's blocked inline indicator stylesheet.
- Replace the local `cp -R` workflow with a tracked-file export.

## Contract coverage

- Make browser smoke prove required asset responses and exact link destinations.
- Cover rendered summary, configured version/source values, and public static routes in Lisp tests.
- Exercise the documented default Woo backend end to end while retaining fallback-backend coverage.

## Completion

The authored and generated assets agree, validators reject the reproduced false-green cases without rejecting valid formatting, both server backends satisfy the documented HTTP contract, the copied template is hermetic, and the repository's public validation loop is green.
