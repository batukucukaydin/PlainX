# Security Policy

## Supported versions

Security fixes are provided for the latest released version of PlainX Editor.

## Reporting a vulnerability

Please do not open a public issue for security problems. Instead, use
GitHub's private vulnerability reporting ("Security" → "Report a vulnerability")
on the repository, or email the maintainers listed in the repository profile.

Include:

- PlainX version and macOS version,
- a description of the issue and its impact,
- reproduction steps or a proof of concept,
- any suggested mitigation.

You can expect an initial response within a few days. Coordinated disclosure is
appreciated; we will credit reporters in the release notes unless you prefer to
stay anonymous.

## Security design notes

- PlainX opens untrusted files, so parsing is conservative: XML validation
  never resolves external entities or fetches the network.
- Large File Mode maps files read-only.
- Saves are atomic; a failed save never destroys the original file.
- The app has no telemetry, no accounts, and performs no automatic network
  access. Update checks (GitHub Releases) are opt-in.
- Distribution builds use Hardened Runtime; releases are signed and notarized
  when certificates are available.
- Plugin/script execution of downloaded code is intentionally out of scope for
  v1.0.
