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

## Signing

The bundle is assembled by hand and ad-hoc signed, with no Xcode project and no
paid Apple account. The icon must be a squircle on the official grid — 824
artwork on a 1024 canvas — because macOS applies no mask of its own, and a
circular corner radius reads visibly squarer than Apple's superellipse.
