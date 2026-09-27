# Contributing

Thanks for looking. Diple is a small, opinionated app; the fastest way to get a
change merged is to keep it that way.

## Before you build

```bash
git clone https://github.com/chagas42/diple.git
cd diple
make tools     # says where gh, claude and git were found
make run       # build, bundle, launch
```

You need macOS 14+, Xcode 16+, and `gh auth login` already done — Diple borrows
that token rather than asking for one.

`make probe` prints the queue in the terminal without any UI, which is the
quickest way to tell a data problem from a rendering one. `--demo` serves
fixtures instead of GitHub, so you can work on the UI with a full queue and
without touching your real pull requests.

## House rules

**No dependencies.** Not a slogan — a constraint. If something needs a package,
the change probably needs a different shape. Say so in the PR and we will talk
about it before you write it.

**No comments in the code.** Name things so the comment is unnecessary. What
does not fit in a name goes in `NOTES.md`, which exists for the API traps that
cost real time to find and that nobody would deduce from reading the code.

**English in the code, and in the interface.** The AI review's *output* language
is a setting, because teams review in their own language; everything else is
English.

**One concern per pull request.** A rename and a bug fix in the same diff is two
pull requests.

## Commits and pull requests

Write the commit message for someone who will read it in a year with no memory
of the conversation: what changed, and why it had to. If a bug had a
non-obvious cause, the cause is the most valuable line in the message.

PRs need one approving review before merge — including mine. CI has to be
green: it builds release, and fails on any Portuguese identifier or `//`
comment sneaking back in.

## Reporting a bug

`make tools` output and the exact macOS version help more than anything else.
If it is a notch or panel bug, say whether the Mac has a notch and whether an
external display was attached — most of the hard ones have lived there.
