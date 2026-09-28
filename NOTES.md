# Notes

Non-obvious things the code depends on. Kept here because the code itself
carries no comments.

## GitHub API

**Review comments live in two places.** `PullRequest.comments` returns only the
conversation timeline. Inline comments on code live under `reviewThreads`, a
separate connection. Reading one and not the other makes the app blind to the
case it exists for: someone replying to you on a line of code. Across 38 open
PRs, zero had a human comment in `comments` alone.

**`diffHunk` comes free.** Every `PullRequestReviewComment` carries the code
excerpt GitHub already cut. The detail pane needs no extra request to show the
snippet around a comment.

**Bots are the majority.** In practice the last comment on a PR is almost always
`coderabbitai` or `github-actions`. Filtering by `author.__typename == "Bot"`
is not enough — several bots present as `User`, so there is also a name list.

**`baseRefOid`, never `origin/HEAD`.** A local clone with a stale `origin/main`
makes `git diff origin/HEAD...HEAD` return the whole repository: 2638 files on a
PR that actually changes 12. The base commit must come from GraphQL and be
fetched explicitly, because it may not exist locally.

**`contributionsCollection` excludes private repositories.**
`totalPullRequestReviewContributions` returns 0 for someone with hundreds of
reviews in private repos. The activity grid is built from each review's real
`submittedAt` instead.

**Cost.** One aggregated query with three aliased searches costs 1 point of
5000/hour. The reviewer ranking is one search per person, all aliased into a
single request — thirty people still cost 1 point.

## The notch panel

**The window never resizes.** It is always the open size, pinned to the top.
What animates is the shape drawn inside it. Resizing the window on every
transition was the source of both the stuttering animation and a hover
feedback loop.

**Hover is decided by pointer position, not by events.** SwiftUI's `onHover`
fires during the resize itself: open, layout changes, exit fires, close,
re-enter. The 30 Hz tick that drives the eye also decides hover, with
asymmetric hysteresis — enters tight, leaves with 14pt of slack.

**Never schedule the close from that tick.** Calling a delayed close 30 times a
second cancels and reschedules it forever, so it never fires. The grace period
is measured against a timestamp instead.

**An LCD cannot match the bezel.** On Liquid Retina the black is backlit and
never reaches zero, while the notch cutout is physical bezel. No pixel value
matches. The seam is hidden by shape instead: the panel is exactly the notch
width when closed, and flares outward with concave fillets when open.

**Concave versus convex is the control point.** Pulled toward the inner corner
the curve is concave; toward the outer corner it is convex. A convex radius at
the top cuts material and leaves wallpaper showing in the corner.

**`fullScreenAuxiliary`** in the panel's collection behavior is what keeps it
visible over a fullscreen app. `becomesKeyOnlyIfNeeded` is what stops a
non-activating panel from eating the first click on every button.

## Notifications

**Quiet hours silence the test too.** The rule lets only direct replies through
outside working hours, which is correct for real events and wrong for a test
button — a test that does not fire because of the clock looks like a broken
app. The test path bypasses it explicitly.

**`threadIdentifier`** groups several notifications from one PR into a single
banner. **`UNTextInputNotificationAction`** is what puts a reply field in it.

## The PR map

**Two layers, two speeds.** Domains and modules come from the GraphQL file list
and appear the moment it returns, at no token cost. Only what needs judgement
(intent, edges, what feels the change, context) waits for `claude`. A map that
never gets the second layer is still a correct map, marked "diff only".

**`files(first: 100)` truncates silently.** A PR with 300 files returned the
top 100 and the map looked complete. The file list is paginated now, up to the
3000 GitHub itself caps at.

**The skill ships inside the bundle.** `Resources/plugin` is copied to
`Contents/Resources/plugin` and passed with `--plugin-dir`, so the prompt and the
parser that reads its JSON always come from the same build. A personal copy at
`~/.claude/skills/diple-map/SKILL.md` wins over the bundled one. `Skill` has to be
in `--allowed-tools`, or the session loads the skill and cannot run it.

**A stack is one map.** Each PR in the stack is fetched against its own base and
the file lists are merged, so every node carries the PRs that touched it. The
worktree is the head of the top PR and the diff base is the base of the bottom
one.

**The worktree outlives the map.** Clicking a node opens the file at the PR head,
which only exists in the worktree. It is not discarded after drawing;
`pruneStale` removes it an hour later, and the click falls back to the clone and
then to GitHub at `headRefOid`.

**Domains are guessed from paths.** Leading containers (`src`, `lib`,
`features`, …) are skipped and workspaces (`apps/x`, `packages/x`, `Sources/x`)
consume two segments. The first segment left is the domain, the next one the
module. It is a heuristic and the skill is told not to trust it blindly.

**Speed comes from not letting the model search.** Measured on a 12-file PR:
170s, 14 sequential tool calls and 6k thinking tokens with the first skill; 44s,
2 rounds and 138 thinking tokens after three changes. A local `git grep` for
each changed file's `parent/stem` and `stem` finds the files that mention it in
under a second, and they go in the input as `candidates`. The skill tells the
model to batch independent calls in one turn and never repeat a search. And the
session runs with `--effort low` and `--strict-mcp-config`, so none of the user's
MCP servers start just to draw a map.

**`--bare` is not an option.** It would skip hooks and plugins, which is exactly
the startup cost left, but it only authenticates with `ANTHROPIC_API_KEY` and
never reads the OAuth login, which breaks "your own Claude".

**The link of a module is never a test.** The file a module box opens is the
most-changed file that is not a spec; tests only win when the module has
nothing else.

**The estimate is a sum you can read.** Session start, worktree fetch when there
is none, files, thousand lines and domains, each with its own rate, then scaled
by the median of actual over predicted for the last ten maps on this machine
(`map-timings.json`). While the session runs, the remaining time blends toward
the pace measured in tool calls against the expected budget.

**New settings are optional on purpose.** `StoredState` decodes with synthesized
`Codable`, and a non-optional field missing from an older `state.json` fails the
whole decode, which moves the file aside as unreadable. Every field added after
the first release is optional with a computed accessor.

## The deep review

**It exists only where the skill does.** When `~/.claude/skills/diple-review/SKILL.md`
is on the machine, the AI review runs it; otherwise it falls back to the plain
prompt. The skill is not in this repository on purpose: the feature is for the
people who have it, and shipping the app does not ship it.

**The app fetches the comments, not the model.** The session has no `gh`, so
the PR body, every review thread (resolved and outdated included), the
conversation and the reviews come from one GraphQL query and go in the input.
Reading them in the session would mean giving it a token.

**`Skill` and `Agent` are allowed only in deep mode.** The skill runs
`mattpocock-skills:code-review`, which fans the two axes out as subagents. The
disallowed list still applies to them, so they stay read-only.

**A bad entry never sinks the answer.** Findings and verdicts are decoded one
by one, so a single malformed item is dropped instead of failing the whole
review into an empty list. The enums read the exact values the prompts ask
for and fall back to a neutral case on anything else. Before, the prompt asked
for `correctness`/`confirmed` while the enums held other raw values, and every
review decoded to nothing.

## Signing

The bundle is assembled by hand and ad-hoc signed, with no Xcode project and no
paid Apple account. The icon must be a squircle on the official grid — 824
artwork on a 1024 canvas — because macOS applies no mask of its own, and a
circular corner radius reads visibly squarer than Apple's superellipse.

## Measuring

**Two kinds of proof, on purpose.** `swift test` gates CI on counts —
requests per refresh, bytes, `gh` spawns, `state.json` writes — because those
are deterministic. Wall-clock numbers live in `make bench`, which runs the real
app against real GitHub and writes `bench/results/<LABEL>/*.json`. A CI runner's
clock is too noisy to fail a build on.

**`DIPLE_STATE_DIR` is not optional for benchmarks.** The bench refuses to run
without it, so it never reads or rewrites the `state.json` of the Diple you use
every day.

**Baseline first.** `bench/results/baseline` was captured on the commit that
only added the instruments, before any optimization. Compare anything against
it with `make bench-compare LABEL=<folder>`.

**Scenarios.** `refresh` is ten steady-state cycles after a warm-up. `launch`
is `start()` until the queue is non-empty, over a state primed by one refresh.
`notch-idle` runs `--demo` with a synthetic pointer circling below the notch,
counting `body` evaluations and process CPU. `review-start` is everything
before `claude` starts: the review context and the worktree, cold and warm —
it needs `PR=owner/repo#number` of a repository cloned on the machine.

**Signposts.** Every request, refresh and store write is an `OSSignposter`
interval under `com.chagas42.diple`, visible in Instruments' Points of Interest.
