<div align="center">

<img src="docs/icon.png" width="128" alt="Diple" />

# Diple

**The pull requests waiting on you, one glance away.**

Lives in the MacBook notch. Stays invisible while there is nothing to do.
Tells you when someone replies to you on a line of code — and lets you
answer without opening anything.

<img src="https://img.shields.io/badge/macOS-14%2B-000?style=flat-square" alt="macOS 14+" />
<img src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square" alt="Swift 6" />
<img src="https://img.shields.io/badge/dependencies-none-2ea043?style=flat-square" alt="no dependencies" />
<img src="https://img.shields.io/badge/AI-your%20own%20Claude-8A63D2?style=flat-square" alt="your own Claude" />

<br /><br />

<!-- DEMO — delete these two comment markers and paste the URL below.
     Record it, drag the file into any GitHub issue comment box, and copy the
     https://github.com/user-attachments/assets/… URL GitHub hands back.

<img src="PASTE_URL" width="820" alt="Diple" />
-->

</div>

---

## Why

Most review tools are a second inbox: everything is equally loud, nothing tells
you what is actually waiting on you, and setting them up is its own afternoon.

Diple takes one position — **a review queue is a list of obligations, not a
list of events**. If nobody is waiting on you, it shows nothing. When somebody
is, it grows out of the bezel and says who, where, and why.

---

## What it does

**The notch is the app.** Nothing waiting: an eye and a dimmed zero, sitting
inside the bezel. Something waiting: the count lights up. Hover and it opens —
the queue, your team, the ranking, your streak. On a Mac without a notch the
same panel floats under the menu bar.

**Answer without leaving what you are doing.** When someone replies to you on a
line of code, the banner carries the reply box and a Resolve button. You answer
from the notification; the thread updates on GitHub.

**A different sound per kind of event.** Glass when someone replied to you. Pop
for a comment. Purr for a review request. Basso when a check breaks. Approvals
arrive silently. You learn what happened before you look.

**Obligations only.** The queue holds reviews someone asked of you and replies
waiting on your answer. Your own PR shows up only when somebody actually
replied to you on it — a broken check is status, not review work, so it stays
in Your PRs and raises a notification instead.

**Stacks stay stacks.** Dependent branches are grouped, numbered, and labelled
bottom to top, because the order is the information.

**Every repository you belong to.** Grouped by organisation, searchable, each
one opening its own list of open pull requests split into Ready and Draft. Star
any of them to watch it.

**Your rhythm.** A ranking over the last week, month or quarter — you and the
people you follow, not the whole company. A contribution grid of the days you
reviewed, and the streak.

---

## Review with your own Claude

Diple has no AI of its own. It drives **your** Claude Code session, with your
skills and your repository's CLAUDE.md, in a throwaway worktree. The findings
come back anchored to the diff as drafts.

Nothing is published, and that is structural rather than a promise:

```
--allowed-tools     Read Grep Glob Bash(git diff|log|show|status)
--disallowed-tools  Write Edit Bash(gh) Bash(git push) Bash(git commit) WebFetch
```

It does not choose not to publish. It cannot.

Before the findings there is a map: what the PR changes comes from the diff,
what it does not change but will feel comes from reference search, and only the
expensive question — *what would someone need to know to judge this, that is
not here* — goes to the model.

---

## Install

Requires **macOS 14+**, **Xcode 16+** and the [GitHub CLI](https://cli.github.com)
already signed in (`gh auth login`). Diple borrows that token — there is no
setup screen and nothing to paste.

```bash
git clone https://github.com/chagas42/diple.git
cd diple
make install
```

That builds, signs, copies to `/Applications` and prints where it found each
tool it needs.

> **The app is signed ad-hoc.** On a machine that did not build it, macOS will
> refuse to open it the first time: right-click → Open, or
> `xattr -dr com.apple.quarantine /Applications/Diple.app`. Notarising needs a
> paid Apple Developer account, which this does not have.

---

## Development

```bash
make run        # build, bundle, launch — the fast loop
make install    # /Applications; use this when testing notifications
make tools      # show which binaries were found, and where
make probe      # print the queue in the terminal, no UI
make film       # run a scripted take over the demo fixtures
make stop
```

`--demo` serves fixtures instead of GitHub, so the app can be demonstrated with
a queue in it. `--alert <kind>` fires one notification and exits:

```bash
open /Applications/Diple.app --args --demo
/Applications/Diple.app/Contents/MacOS/Diple --alert repliedToYou
```

No `.xcodeproj`. The whole project is Swift Package Manager plus a Makefile
that assembles and signs the bundle, so everything is plain text.

---

## How it is built

| | |
|---|---|
| UI | SwiftUI, with AppKit for the panel and the windows |
| Notch | `NSPanel`, non-activating, `.statusBar` level, `.fullScreenAuxiliary` |
| Data | One aggregated GraphQL query, 1 point per sync |
| Storage | A versioned JSON file in Application Support |
| Auth | The token `gh` already holds |
| AI | Your `claude` binary, `--output-format stream-json` |
| Dependencies | None |

`NOTES.md` carries the API traps this cost real time to find — `reviewThreads`
being a separate channel from `comments`, `baseRefOid` versus a stale
`origin/HEAD`, why a GUI app cannot see your `PATH`.

---

## Not there yet

- [ ] Device flow, so `gh` is not required
- [ ] Watched repositories feeding new PRs into the queue
- [ ] Rate-limit state when your Claude plan runs out mid-review
- [ ] A license file — pick one before this goes public

---

## The name

*Diple* (διπλῆ, "double") is the mark `⟩` that scholars at the Library of
Alexandria drew in the margin of a manuscript to say **look at this line**.
Aristarchus used it alongside the obelus † for a suspect line and the asterisk ※
for a duplicate — the first formal system of review marks we know of, third
century BC. Our quotation marks descend from it.

The app does the same job: it points, in the margin, at what deserves your
attention.
