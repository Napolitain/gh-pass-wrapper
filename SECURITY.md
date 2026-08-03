# Security Policy

## Reporting

Do not include real PATs, password-store entries, GPG keys, shell histories, or
other credentials in an issue, pull request, test fixture, or log excerpt.

Use GitHub's private vulnerability-reporting flow when it is available for this
repository. Otherwise, contact the maintainer privately before publishing
details that would make exploitation materially easier. Non-sensitive bugs and
hardening suggestions may use public issues.

## Supported version

Security fixes target the latest tagged release and `main`. Consumers remain
responsible for updating their locked flake input to receive a fix.

## Boundary

This project protects how a PAT is retrieved and passed to stock `gh`. It does
not protect a compromised user account or root, sandbox `gh` or its extensions,
control PAT permissions, or keep a credential encrypted while the GitHub CLI is
actively using it.
