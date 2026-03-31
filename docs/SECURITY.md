# Security

## Supported versions

Security fixes are applied to the default branch (`main`) and released via tags as appropriate. Use the latest tag when deploying from source.

## Reporting a vulnerability

Please **do not** open a public issue for undisclosed security problems.

Preferred: use **[GitHub private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability)** for this repository if it is enabled under **Settings → Security → Code security**.

If that is unavailable, contact the maintainers through a private channel they publish on the organization or project website, or open a minimal public issue asking for a secure contact (without exploit details).

We aim to acknowledge reports within a few business days. Severity and fix timelines depend on impact and maintainer capacity.

## Scope

The **companion** HTTP API and LiveView UI are intended for **local / trusted network** development first. Hardening (authentication, rate limits, production deployment guidance) is tracked as later milestones; see the README **Status** section.
