# Notes

Non-obvious things the code depends on. Kept here because the code itself
carries no comments.

## GitHub API

**Review history comes from search, not `contributionsCollection`.** For an
org's private repositories `pullRequestReviewContributions` reported 0 reviews
over six months that search counted in the thousands, so it cannot feed the
Activity grid. The grid pages `reviewed-by:` search instead, one point per 100
PRs, in non-overlapping 30-day `updated:` windows because a search stops at
1000 results. A PR shows up in the window of its last update, and only its
reviews submitted inside the grid count. The full six months is fetched once;
after that only the last two days are, and older days come from the cache.

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
eye would have to shrink against the corner, so the right wing goes away and
the count moves to a full left wing, with the eye beside it; the shape is then
shifted left. With the eye turned off its wing is dropped, not left empty, and
the wake-ups are skipped, being all eye. The left wing is not measured: an app's menus are
drawn inside one full-width menu bar window, and reading their extents takes
Accessibility permission. `DIPLE_FREE_RIGHT=<points>` overrides the measured
gap, to see each layout without arranging the menu bar.

**On macOS 27 the status items are not windows any more.** One `MenuBarAgent`
window draws the whole bar, so the window list shows no item at all and the
gap cannot be measured from it. Without a measurement Diple assumes the bar is
full: no right wing, the count on the left. The one other source is
Accessibility (`AXExtrasMenuBar` of every running app), behind the opt-in
*Fit the notch to the menu bar*. It reports positions only as laid out on the
main display, and each display lays items out differently (a title that
truncates on one is wider on another), so it is used only when the notch
display is the main display. A window at the status level taller than the
menu bar is not a status item: another Diple's panel sits there too.

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

**The wings spread from the notch.** The window is placed before the hosting
view exists, and the shape starts at the notch's own size, black on black, so
the first frame shows nothing new. 60 ms later both wings open outward together
over 0.55 s on an ease-out curve with no overshoot. Before, the panel started
at a zero frame in the corner and the content grew in from the left.

**It also wakes after the Mac rests.** Going to sleep or the screens sleeping
shuts the eye; coming back plays a wake-up sized by how long the Mac was
away: under 2 minutes (the lid closed and opened) it dozes for 1 s with quicker z's
(the first after 0.1 s, one every 0.28 s, each gone in 1.3 s) and opens and
blinks, about 2.3 s, so even a short rest reads as sleep; up to an hour it dozes for 1.6 s, blinks once and looks
around; an hour or more is the full launch wake-up. The rest is measured from
sleep to wake, not to unlock, and when the screen is locked the wake-up waits
for the unlock, since behind the lock screen nobody would see it. Sleep and the
screens sleeping arrive as separate notifications for one rest, so the first
one starts it and the rest are ignored. To rehearse one, the dev build's
right-click menu on the notch has Rehearse Nap → Short, Medium or Long; it waits
for the pointer to leave the notch, shuts the eye for 1.5 s and wakes.
`--nap short|medium|long` does the same 9 s after launch.

**Gravity is smoothed twice and must never overshoot.** *Lean toward the
pointer* (on by default, off under Reduce Motion) bulges the idle notch toward
the pointer. The pointer is only sampled at 30 Hz, so an exponential
moving average takes the jitter out and an
interpolating spring draws the bulge at display rate between samples; a
retargeted spring keeps its velocity, so a new sample never shows as a step.
The spring is critically damped because a negative bulge dents the notch
upward and shows the cutout's edge. The pull lives in its own observable
object, like the eye, so only the fill redraws.

**`fullScreenAuxiliary`** in the panel's collection behavior is what keeps it
visible over a fullscreen app. `becomesKeyOnlyIfNeeded` is what stops a
non-activating panel from eating the first click on every button.

## Notifications

**A review you send slides a strip out of the notch.** When a PR leaves your
review requests, Diple asks GitHub whether you reviewed it since the request
first showed up (one small query per PR, at most five per sync). A PR opened
from Diple is also checked every 10 s for 30 minutes, at most three at a time,
so the strip shows seconds after you review; that PR leaves Needs you at once,
before the next sync. The count keeps its old number until the strip plays,
drops the moment a sheet leaves it, and the sheet falls into a small drawer
whose number (today's reviews) goes up as it lands, so the two numbers move
together. The drawer always sits at the strip's right end; when the count is on
the left (a tight menu bar), the sheet first drops to the strip and glides
under the cutout, since anything drawn at wing height there is hidden by the
camera housing. The drawer opens a little as the sheet comes, stays open while
it lands, then shuts and shakes, so the shake reads as the drawer closing, not
the sheet falling. It shows more sheets inside as the day's reviews pile up
(one, then two from 3, three from 7, four from 15). The bar beside it fills from empty to full as the sheet travels and
glows when it lands: each review reads as one finished piece of work, whatever
the verdict. A request that
goes away without a review of yours (reassigned, PR closed) lets the count go
with no strip; a hold nobody answers lets go after 20 s. Today resets at local
midnight. Settings → Notifications → Your reviews turns it off, and
`--demo --rehearse-review` plays three.

**Quiet hours silence the test too.** The rule lets only direct replies through
outside working hours, which is correct for real events and wrong for a test
button — a test that does not fire because of the clock looks like a broken
app. The test path bypasses it explicitly.

**`threadIdentifier` only when asked.** Notification Center makes one stack per
thread, so a thread per PR leaves one entry per PR — five PRs, five entries.
Without it, every Diple notification stacks under the app, the way Slack's do
(Slack sets none either). That is the default; "One stack per pull request"
brings the per-PR thread back. **`UNTextInputNotificationAction`** is what puts a reply field in the
banner.

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

## Filming

**The film is the panel, not the screen.** `cacheDisplay` renders the panel's
content view, so no Screen Recording permission is needed, and nothing outside
the panel exists: no cursor, no menu bar, no camera cutout. The cursor, the
cutout and the desktop are composited on afterwards (`FilmStage`). The cutout
is drawn last, in pure black with rounded bottom corners, so a cursor entering
it disappears the way it does on the hardware.

**Time is the frame's, not the clock's.** Capturing is slower than real time
at high frame rates, so a pointer driven by the wall clock would jump. The
scripted pointer is placed from `frame / fps`, and each frame waits for its
own deadline; SwiftUI animations still run on the wall clock, so if capture
falls behind (the recorder says so) they look faster than the pointer. The
pointer timer does not run while filming: each frame calls `followPointer()`,
which is what the timer calls.

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
