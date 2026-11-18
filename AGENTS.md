# Working on Sisu for macOS

Read README.md and docs/checkpoint.md first. The Windows implementation lives at https://github.com/gurusciuc/sisu. This repository is the native AppKit/system-WebKit Mac implementation with Rust tab/address policy and content-rule conversion. Version 0.1.0-alpha.3 is an engineering alpha.

The user authorizes separate platform engines and installers. Direct Chrome Web Store installation is now required for the next Mac foundation. Compare memory among candidates that meet the extension requirement and keep the working WebKit preview available during the evaluation. Keep one engine per session. Do not add an extra web runtime for controls, an AI sidebar, cloud sync or a marketing website.

Use neutral monochrome OKLCH lightness in 5% steps, Helvetica/Arial-family text, conventional geometric icons, top tabs by default and optional left tabs. Use short interaction transitions that respect Reduce Motion and settle at rest. Top and left layouts move the same live views and use the same Rust model.

Preserve TLS validation, WebKit content-process sandboxing, origin boundaries, ordinary logins and active work. Private stores and preferences must stay out of ordinary records. No automatic tab discard. The isolated edit-state reporter has no privileged browser commands. Do not expose a webpage settings bridge or enable remote debugging to pass tests.

Keep the complete pinned filter list order in one converted list so exceptions retain scope. Report unsupported conversion and runtime compile failures honestly. Never equate parser tests, a smaller binary or the main UI process alone with accepted behavior or full-browser memory savings.

Use the pinned toolchain and Cargo.lock. Run cargo fmt --all -- --check, cargo test --release --locked --features mac-core --lib --test policy --test import --test cookies, and tools/build-macos.sh with a fresh output directory. Runtime acceptance must use dedicated BROWSER_TEST_HOME identifiers and controlled local fixtures, with native UI checks for keyboard, edit protection and quit. Do not inspect personal profiles, vaults or decrypted browser databases.

Measure macOS physical footprint for all attributable UI, WebContent, GPU and networking processes. Deduplicate shared mappings and record workload, viewport, blocking, profile and sampling settings. Preserve historical results. Safari is a comparator, not an assumed performance target already beaten.

Keep Apache-2.0, NOTICE and third-party licenses. Source publication is authorized. No production public binary release; Developer ID signing, notarization, secure updates and broader runtime acceptance remain release gates. Keep checkpoint and evidence current.
