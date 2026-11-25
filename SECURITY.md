# Security Policy

Kept is a local-only clipboard manager designed to protect sensitive data. We
take privacy and security reports seriously.

## Supported versions

Security fixes are applied to the latest release on `master`:

| Version | Supported |
| --- | --- |
| 0.1.x | Yes |

## Reporting a vulnerability

**Please do not report security or privacy vulnerabilities in public GitHub
issues.**

Instead, report them privately on GitHub via the repository's **Security** tab
→ **Advisories** → **Report a vulnerability**.

Examples of issues to report privately:

- Sensitive or password-manager copies bypassing `CapturePolicy` or excluded-app
  filtering
- Unintended exposure of clipboard history or blob files outside the App Sandbox
- Release artifact, code signing, or supply-chain issues

Please include steps to reproduce, affected macOS and Kept versions, and any
relevant details. We aim to acknowledge reports within 72 hours and coordinate
a fix before public disclosure.
