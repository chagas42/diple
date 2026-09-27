<div align="center">

# Diple

**Your pull requests, in the notch.**

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000?style=flat-square)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![No dependencies](https://img.shields.io/badge/dependencies-none-2DA44E?style=flat-square)](Package.swift)

</div>

Diple keeps the pull requests that are waiting on you one glance away. It lives
in the MacBook notch, stays invisible while there is nothing to do, and grows
out of the bezel when there is. When someone replies to you on a line of code,
it tells you — and only then.

It can also review a PR for you, using **your own Claude**, and draw a map of
what the PR touches before you start reading it.

---

## The name

A *diple* (διπλῆ) is the mark `⟩` that philologists at the Library of Alexandria
drew in the margin of a manuscript to say **look at this line**. It is the
oldest review annotation on record, and the ancestor of our quotation marks.
Two thousand years later the job has not changed.

---

## What it does

### The notch

At rest with nothing pending, the panel is exactly the size of the notch and
you cannot tell it is there. With something waiting, it grows two small wings
at menu bar height: an eye that follows your pointer, and a count. Hover and it
opens.

On a Mac without a notch it becomes a floating pill under the menu bar, and the
menu bar item appears instead — you never get two icons saying the same thing.

### Four queues that mean different things

| | |
|---|---|
| **Needs you** | A review was requested, a check broke on one of yours, or someone replied and you have not read it |
| **Your PRs** | You opened them |
| **To review** | Somebody asked you specifically |
| **Following** | You are involved, but nobody asked you for anything |

### A sound per kind of event

| Event | Sound | Interrupts |
|---|---|---|
| Someone replied to you | Glass | yes, even during quiet hours |
| Someone commented on your PR | Pop | yes |
| Someone requested your review | Tink | yes |
| A check failed on your PR | Basso | yes |
| Someone approved your PR | — | no |

`Basso` is the classic macOS error sound: your ear already knows what it means.
Alerts from the same PR are grouped by `threadIdentifier`, so three comments in
a row arrive as one banner, and you can reply straight from it.

Quiet hours mute everything outside your working hours except a direct reply to
you — the only event worth waking someone for.

### A window for actually reviewing

Three columns. The detail pane shows each open thread with the code excerpt
around it, and you reply and resolve without leaving. Stacked PRs are grouped
and numbered, because the reading order is the information a stack carries.

### Team, ranking, activity

Pick the teammates whose PRs matter to you. See who reviewed how much over the
last three months, scoped to you and the people you picked. And a contribution
grid of the days you actually reviewed — which, unlike GitHub's own, counts
private repositories.

---

## Review with your own Claude

Diple has **no AI of its own and no server**. It runs the `claude` already
installed on your machine, with your account and your skills — so the review
knows your repository's `CLAUDE.md`, speaks in your voice, and your code never
leaves your computer.

Each review runs in a throwaway worktree under `~/.diple/worktrees`, created
from `refs/pull/N/head` so it works even when the PR comes from a fork. Your
checkout is never touched.

**Nothing is ever published.** That is structural, not a promise:

```
--allowed-tools     Read Grep Glob Bash(git diff|log|show|status)
--disallowed-tools  Write Edit Bash(gh) Bash(git push) Bash(git commit) WebFetch
```

The session starts without the tools. It does not choose not to publish — it
cannot. Findings come back as drafts with a category, a verdict, and the
concrete scenario that breaks; you copy or discard each one yourself.

### The PR map

Before reading a diff, see what it touches. The **changed** layer is
deterministic and comes from the diff at no token cost. Only the question that
needs judgement goes to the model: what *feels* the change without changing,
and what you need to know to judge it that is not in the diff at all — an
implicit business rule, a vendor contract, a state machine the code assumes.

---

## Requirements

- macOS 14 or later, Apple Silicon or Intel
- [`gh`](https://cli.github.com) authenticated — Diple borrows its token and
  stores none of its own
- [`claude`](https://claude.com/claude-code) on your `PATH`, for the AI review
  only. Everything else works without it.

## Build and install

There is no Xcode project. The bundle is assembled by a Makefile and ad-hoc
signed, which means **no paid Apple Developer account is needed**.

```sh
git clone https://github.com/chagas42/diple.git
cd diple
make install     # builds, bundles, signs, copies to /Applications
```

> [!IMPORTANT]
> Install to `/Applications` rather than running from `build/`. Notification
> Center resolves an app's icon by bundle id and caches the path it found; a
> bundle that is deleted and recreated on every compile leaves that record
> pointing at a dead inode, and banners arrive with no icon.

For the fast development loop:

```sh
make run                    # build, bundle, sign, launch from build/
make app                    # bundle only
make icone                  # regenerate the .icns from the master PNG
./.build/release/Diple --probe    # dump the queue in the terminal
./.build/release/Diple --notch    # measure the screen: insets, notch width, frames
```

`--probe` and `--notch` exist to debug the data and geometry layers without
bringing up the UI.

---

## How it works

One aggregated GraphQL query covers all three queues and costs **1 point** of
the 5000 per hour, so polling every 60 seconds spends 60. Everything renders
from a local cache first and refreshes behind it, so nothing blocks on the
network.

A few things the GitHub API does not make obvious are written down in
[NOTES.md](NOTES.md) — among them that review comments live in two separate
places, and that reading only one of them makes the app blind to the case it
exists for.

## Roadmap

- [x] Notch panel with queue, team, ranking and activity
- [x] Sound per event kind, quiet hours, reply from the banner
- [x] Three-column window with inline threads and stacked PR grouping
- [x] AI review on your own Claude, draft-only
- [x] PR map
- [ ] OAuth device flow instead of borrowing the `gh` token
- [ ] Signed and notarized release, so it installs without a Gatekeeper detour
- [ ] Watched repositories: alert on new PRs in repos you choose
- [ ] Per-repository review rules

## Not there yet

The app is ad-hoc signed. On a machine that is not the one that built it,
macOS will complain. Notarization needs a paid Apple Developer account, which
this project deliberately does not require.

There is no license file yet. Decide on one before making the repository
public.

## Credits

The notch behaviour was learned by reading
[boring.notch](https://github.com/TheBoredTeam/boring.notch), whose approach of
keeping the window fixed and animating only the shape inside it is what makes
the panel feel like it belongs to the hardware.
