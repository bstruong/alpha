# Security Policy

## Supported versions

Security fixes are applied on the default branch of this repository.

## Reporting a vulnerability

Please **do not** open a public issue for security-sensitive reports.

Email the maintainer via the address on your GitHub profile for [bstruong](https://github.com/bstruong), or use GitHub’s private vulnerability reporting if enabled on this repository.

Include:

- A description of the issue and impact
- Steps to reproduce
- Affected commit or release, if known

## Operational notes

- Alpha talks to an OpenAI-compatible inference endpoint you configure. Treat that network path as part of your trust boundary.
- Do not commit `.env`, API keys, or credentials. `config`-style secrets for scenario apps must keep master keys gitignored.
- Scenario fixtures may contain fictional domains and emails; do not replace them with real personal data in contributions.
