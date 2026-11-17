# Contributing to Sisu for macOS

Build from the instructions in README.md. Use a disposable browser profile and local fixtures when testing changes. Keep source contributions under Apache-2.0 and preserve third-party attribution.

For a change to navigation, permissions, storage, extension handling, tab layout or filtering, describe a real user workflow and exercise it through the browser. Include a positive network or DOM control when claiming blocking or isolation. Record the host, engine version, profile, build mode and any skipped platforms in the change description.

Run `cargo fmt --all -- --check` and the Rust and browser-driven checks in README.md. Keep Cargo.lock and pinned filter-list digests in sync with intentional upgrades. Regenerate the locked dependency notices after dependency changes. Use the release baseline only with equivalent workloads.

AI coding assistants should start with AGENTS.md and docs/checkpoint.md. Use GitHub issues for ordinary bug reports and SECURITY.md for private disclosures.
