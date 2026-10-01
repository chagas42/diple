# Security

## Reporting a vulnerability

Please don't open a public issue. Report it privately instead:
**[Security → Report a vulnerability](https://github.com/chagas42/diple/security/advisories/new)**.
Only the maintainers see it, and we can talk it through and fix it there before
anything is public.

What helps the most: what you found, the steps to reproduce it, the Diple
version (`brew list --cask --versions diple`, or Get Info on Diple.app), and the
macOS version.

## What counts

Diple runs on your Mac and talks to GitHub with the token `gh` already holds,
so these are the parts that matter most:

- **The GitHub token.** Anything that makes Diple send it somewhere other than
  GitHub's API, write it to disk, or log it.
- **The local state.** `state.json` and the review worktrees under
  `~/.diple/worktrees`, if another app or user could read or change them in a
  way they shouldn't.
- **The AI review.** It runs your own `claude` in a worktree of the pull
  request, so a pull request that can make it run commands or reach files it
  shouldn't is in scope.
- **Telemetry.** Anything beyond the anonymous counts described under Privacy in
  the README reaching PostHog, like a repository name, a title or a login.
- **Updates.** The release workflow and the Homebrew cask: anything that could
  ship a build that didn't come from this repository.

## Supported versions

Only the latest release gets fixes. If you installed with Homebrew,
`brew upgrade --cask diple` gets you there.
