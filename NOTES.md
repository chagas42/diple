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

**Points are not the problem, bytes are.** The full queue costs 1 point but
weighs ~430 KB and takes 4–6 s, almost all of it comment bodies and diff
hunks that did not change since the last minute. The refresh is therefore a
heartbeat — ids, `updatedAt`, draft, review decision and the check rollup —
and only pull requests whose heartbeat differs are fetched in full, by id,
with `nodes(ids:)`. A steady cycle is ~6.7 KB.

**A check finishing does not touch `updatedAt`.** Neither does a review
decision computed from branch protection. Both are in the heartbeat for that
reason. New comments, inline replies and pushes do move `updatedAt`: across
36 real pull requests, no comment was newer than its PR's `updatedAt`, and on
15 of them the latest activity was an inline comment.

**The heartbeat is trusted for thirty minutes.** After that, and on wake, the
sync does one full fetch anyway, so anything GitHub changes without moving
`updatedAt` is at most half an hour stale.

**Three small searches beat one aggregated one.** GitHub runs aliased searches
one after another; three requests in parallel return in ~1.4 s instead of
~2.4 s, for 3 points a cycle instead of 1 — about 180 of the 5000 an hour.

## The notch panel

**The window never resizes.** It is always the open size, pinned to the top.
What animates is the shape drawn inside it. Resizing the window on every
transition was the source of both the stuttering animation and a hover
feedback loop.

**Hover is decided by pointer position, not by events.** SwiftUI's `onHover`
fires during the resize itself: open, layout changes, exit fires, close,
re-enter. The 30 Hz tick that drives the eye also decides hover, with
asymmetric hysteresis — enters tight, leaves with 14pt of slack.

**Hovering an alert holds it, it does not open the panel.** Opening on hover
replaced the alert with the queue before its buttons could be reached, and the
event was gone from view. While the pointer is over an alert its 6 s timer is
paused; leaving closes it 1.5 s later.

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

**The wings give way to the menu bar.** macOS lays status items out from the
notch's right edge knowing nothing of Diple's wings, so a full menu bar puts
its leftmost item about 28pt from the notch, under a 42pt wing. The wing is
fitted to the gap instead, measured from `CGWindowListCopyWindowInfo`: status
items are windows at `kCGStatusWindowLevel`, and their bounds need no Screen
Recording permission. Items change width as they tick (a meeting countdown),
so the fit is re-checked every 2 s while idle. When less than 27pt fits, the
eye would have to shrink against the corner, so the right wing goes away, the
eye is hidden, and the count moves to a full left wing; the shape is then
shifted left by half a wing. The left wing is not measured: an app's menus are
drawn inside one full-width menu bar window, and reading their extents takes
Accessibility permission. `DIPLE_FREE_RIGHT=<points>` overrides the measured
gap, to see each layout without arranging the menu bar.

**The panel springs out and settles back in.** Growing uses an underdamped
spring; shrinking uses a critically damped one. A bounce on the way in
overshoots past the resting size, and the resting size hugs the notch, so the
overshoot pulls the shape inside the cutout and shows its raw edges.

**Over a fullscreen app the notch idles hidden.** It shrinks to the cutout
itself and draws nothing, but the cutout is still the hot zone, so hovering
opens it and leaving hides it again; alerts still drop down. The window list
cannot tell fullscreen apart: the `Menubar` window stays listed on a fullscreen
display, and a fullscreen window's frame equals a zoomed one's when the Dock
lives on another display. The Space can: `CGSCopyManagedDisplaySpaces` gives
each display's current Space, and type 4 is a fullscreen one. It is private, so
it is looked up with `dlsym` and a missing symbol reads as not fullscreen. With
"Displays have separate Spaces" off there is one entry, named `Main`, for all
displays. It is re-read on every Space change and on the 2 s menu-bar tick.

**A fullscreen Space is caught as it slides in, not when it lands.** The
current Space and `activeSpaceDidChangeNotification` change together, at the
end of the switch: about 600 ms after a swipe starts, or never while the swipe
is held halfway. The panel is not drawn during the slide, and when the switch
lands it comes back with the state it had, so the eye and count showed over the
fullscreen app for a frame before the Space change hid them, a blink. The
incoming Space's windows are on screen from the first frame of the swipe,
though, so the windows of the display's fullscreen Spaces are mapped (`CGSCopySpacesForWindows`,
one window at a time, ~35 ms for 150 windows, off the main thread, redone when
the fullscreen Spaces change or on a Space change) and the 30 Hz tick asks
whether any of them is on screen (~0.2 ms). If one is, the notch hides; if the
swipe is given up, they leave the screen and the wings come back. A switch
never takes longer than about 600 ms, so that signal counts for 1.5 s at most:
windows of a fullscreen Space seen on screen for longer, with the current Space
still not fullscreen, are not a switch, and the wings come back rather than
staying hidden until the next Space change.

**The first frame already knows about fullscreen.** The panel used to be drawn
in `.active` and only then check the Space, so launching over a fullscreen app
flashed the wings for a frame. `mount` settles the idle state before the
hosting view exists.
`CGWindowListCreateDescriptionFromArray` wants the window ids as raw values in
a callback-less `CFArray`: an array of `NSNumber` returns nothing.

**The fullscreen menu bar is followed by the pointer.** Pushing against the top
edge slides the menu bar down over a fullscreen app, and Diple comes back with
it. Nothing in the window list changes when that happens (the `Menubar` window
is listed throughout, and no status item windows appear), so Diple applies the
rule macOS does: the top edge reveals it, and it stays while the pointer is
within the bar's height.

**Diple wakes up at launch.** It opens with its wings out and the eye shut,
dozing for 3.2 s, the shut eye a visible sliver, while z's drift slowly off it
along three alternating paths once the eye has faded in (0.9 s). Then it opens
the eye halfway, blinks twice slowly, yawns (the eye squeezes shut, squints,
and reopens over 1.3 s), blinks once more, looks left and right, and only then
shows the count, about 7.5 s in all. A slow blink shuts the lid in 0.12 s and
opens it in 0.35 s, like a real one. It makes no sound: a recorded yawn read
as someone groaning, the system "Pop" as an interface sound, and the wake
reads better silent. Every step checks that the wake is still on, so
hovering mid-blink cannot leave the eye half shut. It is skipped over a
fullscreen app, under Reduce Motion, in `--film` and in benches, and hovering
or an alert ends it at once.

**The count says how it changed.** Whenever it moves, a small "+N" (green) or
"−N" (dimmed) rises beside it for a second. The label is always in the view,
empty at rest: a `keyframeAnimator` only runs when its trigger changes on a
view that already exists, so inserting the label and bumping the trigger in
the same update never animated.

**`fullScreenAuxiliary`** in the panel's collection behavior is what keeps it
visible over a fullscreen app. `becomesKeyOnlyIfNeeded` is what stops a
non-activating panel from eating the first click on every button.

## Rewards (beta)

**A review is noticed when its request leaves the list.** GitHub drops you
from a pull request's requested reviewers as soon as you review it, so a PR
whose snapshot had `reviewRequested` and now does not is a candidate. That
alone is not proof (the request may have been withdrawn, or a section may have
failed to sync), so each candidate is confirmed with one query for a review of
yours submitted after the request was first seen (`requestSeenAt`). Reviews
done anywhere count, not only from Diple, within a sync.

**Stickers wait along a quarterly trail, not after every review.** Someone
doing 300 reviews a quarter would drown in one sticker per review, so each
review is one step on the season's trail (a season is a calendar quarter) and
stickers wait at 10, 30, 60, 100, 180 and 300, common to legendary: about six
a quarter at that pace, three for someone doing 60. A review is counted once
(`countedReviews` keeps the last one per PR), whatever its verdict, and Diple
never judges how you review: time, length or verdict say nothing reliable
about quality, so none of them changes what you get.

**A review is a thin strip, not a show.** For someone reviewing all day,
anything louder is noise, so the notch opens an 18 pt strip for 1.5 s:
`› approved  orders-api#7867` on the left, a short bar with "12/30" towards
the next sticker on the right. At a milestone it stays 2.3 s, the sticker pops
at the end of the bar and the eye squints; only then does the dot by the count
ask you to claim it. With the strip, a small sheet of paper either flies up
into the notch ("filed") or slips out and falls ("dropped off the pile"), a
choice in Settings → Rewards while both are being tried.

**Opening a PR from Diple watches it for your review.** The sync notices a
review only on its next pass, up to a minute late, so a PR opened from Diple is
checked every 10 s for 30 minutes and the strip shows within seconds of the
review.

**Claiming zips the sticker into a backpack.** The gift button opens the card
mid-screen, 120 pt below the notch; clicking it shrinks the card into a
pixel-art backpack with a MacBook peeking out, which squashes as it lands.
The sound is `Resources/Sounds/zipper.*` when there is one, the 8-bit coin
from `tools/coin.py` until then, at 35% volume; it plays even in quiet hours,
since the click asked for it. While a card is up, hovering the notch does not
open the panel.

**Onboarding asks two things, once.** Turning Rewards on asks what you do and
why you want to review more, for the characters that will come later; the
answers stay on this Mac.

**The collection lives in the main window.** With Rewards on, the sidebar
gets a Collection row: the season's trail with its six milestones, the
stickers by rarity, and the Journey, every sticker by day with the verdict,
the PR and whether it is in the backpack yet.

`--celebrate [rarity]` rehearses three reviews up to the milestone for that
rarity, and `--tour` walks the whole flow over demo data.

**Stickers look like vinyl, flat or inspected.** Everywhere in 2D a sticker is
the sprite with a one-cell white die-cut border, tilted a degree or two (from
its id, so it stays put), with a short and a long shadow; rare and up get a
faint holographic gradient masked to the sticker, and nothing sweeps across
it, since the earlier shine band read as an interface effect. Clicking one in
the collection opens it in SceneKit (no dependency): the outline is traced from
that dilated sprite and extruded 0.14 cells with a small chamfer, the front is
the sprite under a clear coat, the back is the printed backing paper, and it
floats just above a cutting mat that catches its shadow. SceneKit is
deprecated, so this stays small until the MacBook lid replaces it.
`DIPLE_RENDER_STICKERS=<dir> swift test --filter StickerRenderProbe` renders
every sticker front, back and flat to PNGs.

**Each season has its own sheet of six.** 2026-Q3 is "AI Season" (Strawberry
to The Last Human Reviewer), 2026-Q4 "Dev Folklore" (It Was DNS to the
Load-Bearing TODO), later quarters rotate through the sheets, and the first
seven artifacts are the "Classics". A milestone gives the sheet's sticker for
that step, so a sheet always runs common to legendary. The jokes are about the
memes and the culture, never a real person by name or face, and they poke at
every AI lab alike.

**The lid is where stickers live (prototype, 2D).** The collection opens on a
brushed-aluminium MacBook lid with every sticker earned stuck on it. Each lands
where its id puts it (a seeded position, a tilt within ±18° and a size), so a
lid stays the same between launches, stickers overlap like real ones, and the
centre stays clear for the logo: Diple's `›` glowing through a Space Gray lid
like the backlit logos of older MacBooks, since Apple's logo is a trademark
third-party apps may not use, Mac-only or not. A new sticker waits lifted above
the lid, bobbing with its shadow; drag it where you want it and press "Stick
it", and it settles with a spring and stays there (`lidSpots`), since a real
sticker does not move once stuck. With "Preview every sticker" on,
"Stick one" adds a random sticker to place, without saving. This is the 2D trial before a
modelled MacBook: the lid is meant to become one composed texture on a 3D
model, and only there, never in the notch.

**Artifacts are drawn in code.** Each is a 16×16 grid of characters and a
palette, painted with `Canvas`, so the beta ships no image assets. Rare and up
get a holographic foil (an `AngularGradient` in `.overlay`, masked by the
sprite), epic a sweeping shine, legendary sparks.

## Notifications

**Quiet hours silence the test too.** The rule lets only direct replies through
outside working hours, which is correct for real events and wrong for a test
button — a test that does not fire because of the clock looks like a broken
app. The test path bypasses it explicitly.

**`threadIdentifier`** groups several notifications from one PR into a single
banner. **`UNTextInputNotificationAction`** is what puts a reply field in it.

**Picks shape review requests only when asked to.** `review-requested:@me`
matches requests to any GitHub team you are on, which is most of the noise.
`reviewRequests` on each pull request tells a request to you by name (a `User`
node with your login) from one to a team, at no extra query. The review filter
(Everyone / Picked first / Only picked) orders requests from picked people and
by-name requests first; Only picked also leaves the rest out of Needs you, the
count and alerts, while keeping them dimmed in Reviewing. A quiet request
speaks up again once someone writes on it, since its unread reason is then
more urgent than `reviewRequested`. With nobody picked, every filter behaves
as Everyone, so an empty team cannot silence everything.

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

**Start at login registers this copy.** `SMAppService.mainApp` records the
bundle that called it, at the path it ran from, so turning it on from a build
in `build/` starts that build at login. Its status, not a stored setting, is
the source of truth: removing Diple in System Settings → Login Items turns the
switch off the next time Settings is shown.

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

## Telemetry

**The type is the allowlist.** `TelemetryEvent` is an enum, and each case
builds its own properties from typed values — counts, booleans, enum raw
values. There is no public way to send a dictionary, so a repository name or a
title cannot reach PostHog by accident; a test snapshots the payload and fails
on any key it does not know.

**Capture is a lock and an append.** The flush runs detached at utility
priority, every 60 s or at 20 events, through the same `Transport` as GitHub.
A failed batch goes back to the front of the queue with the same event uuids,
so PostHog de-duplicates a retry; a 4xx is dropped, so a wrong key cannot loop.
Nothing is written to disk: a crash loses at most a minute of counts.

**No key, no telemetry.** The PostHog project key is stamped into Info.plist
by the release workflow from the `POSTHOG_KEY` secret. Local builds, forks,
`--demo`, `--bench`, tests and `DO_NOT_TRACK=1` never send anything. A debug
build accepts `DIPLE_POSTHOG_KEY` for trying it against a test project.

**Errors go through `AppModel.report`.** It turns an error into an
`ErrorReport` — the operation, the Swift type, the `NSError` domain and code
(the HTTP status for `ClientError.http`) — logs it under the `errors` category
and sends it as PostHog's `$exception`, grouped by that triple. The message
stays out of the payload because it can carry a URL or a repository name; the
log keeps it as `.private`, so `log stream --predicate 'subsystem ==
"com.chagas42.diple"' --level debug` shows it only on this Mac. Cancellation is
not an error: restarting the poll timer while a sync is in flight cancels its
request, and that used to put "cancelled" on screen and count as a failure for
the backoff.

**A network error says what the network was.** `NSURLErrorDomain -1009` alone
does not tell a dead Wi-Fi from a GitHub outage. Each report carries a readable
name (`notConnectedToInternet`, `http_502`), the underlying CFNetwork error, the
host when it is one of ours (anything else is `other`), the path as
`NWPathMonitor` last saw it — status, interface, expensive, constrained — the
failures in a row and a range for the time since the last good sync. Transport
failures go in as `warning`, the rest as `error`, so an evening offline does
not drown the issues that are bugs.

**GitHub gives a GraphQL query about ten seconds.** Past that it answers 502 or
504 — "we couldn't respond to your request in time" — and the cost is the
query's, not the network's. The queue used to be one request with every section
and every thread comment of every PR: about eight seconds for forty PRs, so a
bigger team or a busy hour crossed the line. Now each section is its own request,
run side by side, and `details` goes in batches of ten, two at a time. A section
or batch that still times out keeps what it had, the rest is applied, and the
next cycle tries again (a full one, if a section failed). Queries are retried
twice on 502/503/504 after about 1 s and 3 s; mutations never are, because a 502
does not mean GitHub did not post the comment. Each retry is a `github_retry`
event, so PostHog shows whether the limit is still close.

**A mutation that times out may still have happened.** A 502, 503, 504, a
timeout or a dropped connection on reply, resolve or a finding leaves the result
unknown, so before saying it failed the client asks: is the thread resolved,
is its last comment yours and from the last minute, is there a pending review
of yours with a comment on that path, a COMMENTED review of yours just
submitted. Yes means success; no means the error, and resending is safe. The
minute of slack covers a clock that disagrees with GitHub's; a reply of yours
in the same thread in that minute would read as this one. Each check is a
`github_retry` with `request: mutation` and `landed` or `lost`.

**PostHog adds location unless told not to.** GeoIP runs on the server, from the
request's IP, and fills `$geoip_city_name`, postal code, latitude and more —
none of it sent by the app. `$geoip_disable: true` on every event turns it off
at the source; it is merged last, so no event can switch it back on. The
project's "Discard client IP data" setting is still worth turning on.
