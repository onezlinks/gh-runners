# Security Policy

## Reporting a Vulnerability

Please report security issues privately via GitHub's
[private vulnerability reporting](../../security/advisories/new) instead of
opening a public issue. We will acknowledge and respond as soon as possible.

## Scope Notes

- Runners mount the host Docker socket by design. Treat every job as having
  host-level access and only run trusted workflows.
- Never commit `.env` files, PATs, or registration tokens — they are
  gitignored by default; keep them that way.
