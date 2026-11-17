# Security reporting and engine maintenance

Use the repository's private vulnerability reporting form for security disclosures. Include the affected build, OS, engine version, observable impact and a minimal controlled reproduction. Remove personal profile data, passwords, browsing history and tokens. [Report a vulnerability privately](https://github.com/gurusciuc/sisu/security/advisories/new)

For an upstream Chromium or CEF issue, follow the upstream project's disclosure process. [Chromium security](https://www.chromium.org/Home/chromium-security/reporting-security-bugs/) · [CEF project](https://github.com/chromiumembedded/cef)

Every runtime release requires tracking supported upstream branches, checking advisories, verifying archive provenance and hashes, updating matching Rust bindings and sandbox bootstrap, and repeating platform and compatibility checks. Document any local engine patches, their upstream status and their security owner. A pinned prototype receives fixes when rebuilt and redistributed. There is no deployed automatic updater.
