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
after that only the last two days are, and older days come from the saved
query, which lives on disk for the six months it covers.

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

**The ranking is opt-in, and can be just you.** Settings → General → Ranking
picks Off (the default, also for anyone upgrading), My pace or Team board. Off
hides the trophy tab. My pace compares only you with your own usual: this
period's reviews from the activity log (dated by the review, not the PR)
against the average of the last complete periods it holds (8 weeks, 5 months
or 1 quarter), scaled by how much of the period has passed, so a Monday morning
reads as "just started" rather than behind. It never shows anyone else. Only
Team board fetches or preloads the team's ranking. The demo turns Team board on,
so films still show it.

**Ranking periods are calendar periods.** Week runs from Monday 00:00, month
from the 1st, quarter from the first day of its calendar quarter (Jan, Apr,
Jul, Oct), all in the Mac's time zone, so each starts again from zero instead
of sliding over the last 7 or 30 days.

**A review counts in the period it was made.** GitHub search has no
review-date filter, so the board used to count PRs *created* in the period
that the person reviewed: on a Monday, reviewing last week's PRs moved Month
but never Week (4 against the 7 reviewed that morning). Each person's search is
now `reviewed-by:<login> updated:>=<exact start>` with `first: 100` and
`reviews(author:, last: 1) { submittedAt }`, and a PR counts when that last
review is inside the period. A review updates the PR, so nothing reviewed in
the period is left out of `updated:>=`. All people stay in one aliased query
at 1 point each; a person with more than 100 such PRs gets up to 4 more pages.

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

**Notifications are a free doorbell.** Diple cannot receive webhooks, so it
polls REST `GET /notifications?per_page=5` with `If-Modified-Since` and
`If-None-Match` from the previous answer. A `304` does not count against the
rate limit: over three rounds of one `200` and three `304`s, `X-RateLimit-Used`
moved only on the `200`s. A `200` costs 1 point of the REST `core` budget,
never a GraphQL point, and weighs ~23 KB. `X-Poll-Interval` answered `60`
every time and is the floor between polls. Only a pull request thread newer
than the last one seen wakes the sync — one you are involved in anywhere, or
any thread in a watched repository — and the wake pushes the next regular
tick back, so it moves a sync earlier instead of adding one. `401`, `403` and
`404` switch the feed off until relaunch; the regular timer carries on.
Diple never marks a thread read.

**`URLSession` hides the `304`.** With the default cache policy a repeated
`GET /notifications` is answered from `URLCache` in 2 ms with old data, and a
hand-written `If-Modified-Since` comes back as a `200` carrying the cached
body. The feed request uses `.reloadIgnoringLocalCacheData`, which passes the
real `304` through.

**The unread list's `Last-Modified` is its newest unread thread**, not the
newest thread: with three read threads updated later that day, it still
matched the `updated_at` of the newest unread one. That is why the feed reads
the unread list — a thread you already read only shows up again once new
activity makes it unread.

**Three small searches beat one aggregated one.** GitHub runs aliased searches
one after another; three requests in parallel return in ~1.4 s instead of
~2.4 s, for 3 points a cycle instead of 1 — about 180 of the 5000 an hour.

## The query cache

Everything read from GitHub goes through `QueryClient`, modelled on React Query:
a key holds every input the data depends on, identical requests share one
fetch, and a reply that lands after its entry was cleared is dropped.

**Changing an input means asking for a different key.** The ranking key carries
the period, the day it started and the picked logins, so a new week is a new
key on Monday morning rather than last week's numbers until they go stale; per-PR data carries the PR's last update, and
AI reviews and maps carry its head commit. Nothing is cleared by hand; old keys
are forgotten once nobody has looked at them for their `forgetAfter`.

**Observers are the screens on screen.** The notch tab, the main window's
repositories and an open review or map hold their queries; everything else
reads the cache directly. Opening the notch, reconnecting, focusing the window
or a refresh button refetch only what is observed, which keeps the request
budget where it was.

**The queue query only syncs.** `SyncEngine` runs one sync at a time, owns the
pending full re-read and takes the watch list from the key. The diff,
notifications and saving run in `onSuccess`, once per result and only for the
current watch list, so a sync that finishes after the list changed is ignored.

**AI reviews and maps follow the head commit, not the update time.** A comment
bumps `updatedAt`; keyed by it, a finished review vanished the moment a
teammate replied. A push is what makes a review or a map out of date.

**Memory and disk forget on different clocks.** `forgetAfter` drops an unused
entry from memory only; the saved row stays and is read back the next time the
key is asked for. Saved rows have their own `persistFor` (30 days, six months
for activity) and are pruned at launch once past it, since forget timers live
only in memory. TanStack's persister keeps the same split with `maxAge`.

**Saved queries write only when something changed.** An unchanged refetch
writes nothing unless the saved copy is already stale, so a relaunch can trust
its time.

**Coming back online syncs afresh.** A `refresh()` asked for while the queue
is being fetched joins that fetch. When the network dropped mid-sync and came
back, the sync `setOnline(true)` asked for joined the one that was failing, so
it failed too and the error stayed on screen ("could not update", or the
offline error) until the next timer tick. Coming back now forces the fetch,
which cancels the failing one and starts over.

## Syncing after a push

Diple cannot receive webhooks, so it watches the clones it already knows
(`Worktree.localPath` for every repository in the queue, the watched list and
Settings) and treats a local push as the webhook.

**A push moves the remote-tracking ref; a commit does not.** `git push` rewrites
`refs/remotes/<remote>/<branch>` (or `packed-refs`) in the clone, so one
FSEventStream over each clone's common git dir sees it about a second later. A
linked worktree's `.git` is a file (`gitdir:`), and its refs live in the folder
its `commondir` names, so that folder is what gets watched.

**The reflog tells a push from a fetch.** A fetch moves the same refs. The last
line of `logs/refs/remotes/<remote>/<branch>` ends in `update by push` for a
push and `fetch: …` for a fetch; a fetch that brings nothing writes no ref.

**The rule.** A push to the default branch (the remote's `HEAD`, else main or
master) syncs once. A push to a branch that already has a PR in the queue syncs
at ~3 s and again ~12 s later, because GitHub takes seconds to update the PR.
A push to any other branch does not touch GraphQL: it asks REST
`pulls?head=<owner>:<branch>&state=open&per_page=1` after 10, 20 and 30 s, then
every minute for 15 minutes, and syncs once when a PR appears (`gh pr create`
or the web often comes minutes after the push). The head owner is the pushed
remote's owner; the base is the watched repository owned by someone else when
there is one, so a fork's PR is looked for upstream. At most five branches are
watched; another push to the same branch starts its window over. A fetch syncs
once only when it moved a branch that has a PR. Syncs are at least 10 s apart.

**A 304 is free.** With `If-None-Match`, an unchanged answer is 304 and leaves
`X-RateLimit-Used` where it was (measured: 200 → 8, ten 304s → 8, next 200 →
9). REST `core` is also a separate budget from the GraphQL points. URLSession's
own cache would answer 304s for us, so the request skips it
(`reloadIgnoringLocalCacheData`) and keeps the ETag itself.

**`resolvingSymlinksInPath` drops `/private`.** It turns `/private/tmp/x` into
`/tmp/x`, while FSEvents reports `/private/tmp/x`, so no event ever matched.
Watched roots go through `realpath(3)`.

## The notch panel

**There is no menu bar item.** The notch is drawn on every screen, with or
without a physical notch, so a `MenuBarExtra` shown on screens without one put
Diple there twice: the drawn notch and a `⟩ 3` item next to it. The app's only
scene is an empty `Settings` that carries the menu commands.

**The window never resizes.** It is always the open size, pinned to the top.
What animates is the shape drawn inside it. Resizing the window on every
transition was the source of both the stuttering animation and a hover
feedback loop.

**Hover is decided by pointer position, not by events.** SwiftUI's `onHover`
fires during the resize itself: open, layout changes, exit fires, close,
re-enter. The 30 Hz tick that drives the eye also decides hover, with
asymmetric hysteresis — enters tight, leaves with 16pt of slack.

**Opening waits for the pointer to mean it.** The notch sits right where the
pointer crosses on its way to menu bar items, so opening on the first tick
inside opened it on every pass. `HoverIntent` opens only after the pointer
has stayed inside for 150 ms while moving slower than 700 pt/s, measured over
the last ~100 ms of tick samples. A pointer homing in on a target slows to a
few hundred pt/s in its last stretch, while a sweep across the bar is well
over 1000 pt/s as it crosses, so the threshold sits between the two; at 30 Hz
the dwell is five ticks. A press that begins inside opens at once, read from
`NSEvent.pressedMouseButtons` on the same tick, since the idle panel ignores
mouse events and never sees the click. The zone that opens is the resting
shape plus the cutout, one point taller so the top pixel counts: the lean
toward the pointer only changes how the notch looks, or it would reach out and
grab a passing pointer. Settings → Appearance → Notch → Open on hover →
Instantly drops the wait. Time comes from `clock`, so films and tests run it
on their own time.

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

**Reduce Motion turns movement into fades.** With the system setting on,
springs become short ease-in-outs without bounce, slides and scale-ins become
cross-fades, the count swaps digits instead of rolling them, and the flame
stands still. The eye stops following the pointer, blinking and looking
around on its own. Views read `accessibilityReduceMotion`; the controller,
which drives the eye outside SwiftUI, reads `Motion.reduced`.

**The panel is always dark.** It is black whatever the system appearance, so
it sets `darkAqua` on itself; without it a light system appearance draws the
legacy scroller (a mouse attached, or *Show scroll bars: Always*) with a
white track down the side of the lists, where the system scroller is still
used (`ThinScrollView` on macOS 14). The app's windows are not forced and
follow the system.

**The pointer glows where the cutout hides it.** The camera housing has no
pixels, so the pointer vanishes inside it while the panel is open. The pointer
is a light source: a thin rim around the cutout and a faint spill into the
panel, both lit by a radial light centred on the pointer, so there is no
bottom or side sprite to flip between. The rim fades in as the pointer comes
within 40pt, so it never switches on at the edge. The light's reach grows by
the pointer's distance to the nearest visible edge, so a pointer hugging the
top of the screen still lights the rim. `CGRect.contains` excludes the max
edge, and the cutout's top is the screen's, so the top pixel is counted as
inside by hand. The glow lives in its own observable object, like the eye, so
the 30 Hz updates redraw only the glow; with Reduce Motion it moves without
animating.

**A tooltip in the panel is drawn, not asked for.** `.help()` becomes an AppKit
tooltip, and AppKit shows tooltips only while the app is active; the panel is
non-activating, so Diple almost never is. The activity grid reads the pointer
with `onContinuousHover`, which a tracking area delivers to inactive windows,
and draws its own bubble over the grid so nothing moves. The bubble sits in a
`ZStack` inside the overlay: an overlay alone places its content by the
overlay's alignment and ignores the bubble's own alignment guides.

**`fullScreenAuxiliary`** in the panel's collection behavior is what keeps it
visible over a fullscreen app. `becomesKeyOnlyIfNeeded` is what stops a
non-activating panel from eating the first click on every button.

**Diple goes quiet in Focus.** A macOS Focus is read through
`INFocusStatusCenter` (after the Focus permission, which works on an ad-hoc
signature) and polled every 5 s, since it posts no change notification.
Clicking the eye in the open panel focuses from Diple too, with no macOS
Focus. The idle notch's eye is not clickable on purpose: making it a target
meant hovering it could no longer open the panel, and the notch felt smaller
and slower to open. While focused, the notch drops no alerts, notifications are
posted `.passive` with no sound (they land in Notification Center), the eye
stops blinking, half closes and turns a pale indigo, and the panel's body is
covered and takes no clicks, showing how long the focus has lasted; only the
top strip stays live, so the eye can end it. The cover arrives and leaves
with a line of its own: the terminal one, a small zsh window of fixed size (so lines appearing never shift it), types `heads-down`, prints that
notifications are paused and waits at a blinking prompt; leaving types `exit`
and prints how long the focus lasted. The cover lingers 1.8 s for that goodbye
before fading. The time counts seconds for the first minute, so it never sits
at 0. It lives in memory only. Settings → Appearance → Focus → Screen while focused picks the cover
(Terminal by default, Breathing moon, Pomodoro timer). Clicking the eye during a macOS
Focus sets that Focus aside, since Diple cannot end it: Diple stays out of focus
until the macOS Focus ends, and the next one is followed again. The eye in the open panel
follows the pointer from where it sits (top left, 41pt in, halfway down the
menu bar), over a shorter range than the idle eye. The click hurts: the eye
squints shut, turns pink and shakes for about half a second, then opens into
the new state, while a bubble below it complains (`💢 ow!`, `hey!`, `my eye!`,
`rude.`, `ouch!`, `why?!`, in turn) for about a second. With the eye turned off, a moon button takes its place in the
open panel's top strip, and the notch's right-click menu always has Focus /
Stop Focusing, so focus can be entered and left without the eye. The moon is a tap gesture, not a
`Button`: as a plain `Button` in the panel it fired by itself a fraction of a
second after focus ended, turning focus straight back on. Settings → Notifications → Focus turns following macOS off. `--scene focus` films the terminal cover coming and going, and
`focus-breathing` and `focus-pomodoro` the other two; film them at `--fps 8`, since the cover's typing
and the poke run on the wall clock and a 60 fps capture falls behind them.
Films and benches never ask: they run
the binary straight from a shell, so TCC holds the shell responsible, finds no
`NSFocusStatusUsageDescription` in its Info.plist, and kills the process.

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

**A request you already answered leaves Needs you.** GitHub drops a review
request when you submit a review, but a conversation comment or a reply on a
line leaves it standing, so the PR kept counting as waiting on you after you
had spoken. The PR query carries the last five `REVIEW_REQUESTED_EVENT`s, each
review's `submittedAt`, each thread comment's `state` and the head commit's
`committedDate`. A request counts as answered when your latest submitted
review or comment is newer than both the latest request to you (by name, or
to any team, since team membership is not fetched) and the head commit. A new
request or a new commit brings the PR back, and so does a reply to you, through
unread. It stays in Reviewing, where GitHub still lists it. Without a request
time (a PR cached before these fields) nothing is hidden. `committedDate` is
the author's clock, not the push: a commit made before your comment and pushed
after it does not bring the PR back. Merged and closed PRs need no rule: every
search is `is:open`.

**A dismissal lasts until the pull request moves.** Hovering a row in the
notch shows an ×, and its right-click menu has Dismiss. Diple saves the PR's
`updatedAt` beside its key and hides it from every tab and the count while
GitHub reports that same time. A new comment, push or review request moves
`updatedAt`, so the PR comes back by itself; so does a bot comment, which errs
toward showing too much rather than hiding a request. The entry is dropped
once the PR has moved on, or a month after it left the queue.

## The main window

**The list opens wide, and a row says one thing per line.** The list column
opens at 520pt (380 to 680). A row is the title with a short time (`7h`,
`3d`) on the first line, and `repo #n`, the last commenter and a trail of
indicators on the second: approvals, open threads, and a dot for the checks.
A stack is one card, collapsed until its header is clicked (or a PR in it is
selected), with a sheet peeking below it for each branch it hides (up to 3). The
whole stack is a single `List` row that draws its own branches: as list rows,
a custom background hid the system selection but left the text white, and the
selection fought the card. Selection in a card is a light accent tint with a
bar. Opening does not animate, since a `List` row animating its height drew the
old and new content over each other; only the chevron turns. The header names
the repository once, so the rows show only `#n`, and a rail gives the order
instead of `1/4`, which read like an approval count next to `1/2`. The base
comes first and merges first (`groupedIntoStacks` reverses the chain from the
tip). The list's selection binding skips stacked PRs, so it never clears a
selection it has no row for. Reviews show as marks: approvals against the
requirement, change requests in red, comment reviews in blue, open threads. Numbers go through `Text(verbatim:)`: a
`LocalizedStringKey` groups them by locale, and Portuguese turned `#7966` into
`#7.966`. The detail keeps its content to 780pt so long text has a measure,
its badge says only Open, Draft or Approved (checks and threads have their
own pills), and an empty conversation is a centered card. `--select repo#n`
opens the window on a PR, which is how its screenshots are taken in `--demo`.

## Approvals

**A row shows its approvals against what the branch needs.** Approvals come
from `latestReviews` in the queue's own query (one review per person, bots and
the author left out), so they cost no extra request. What the base branch needs
is looked up once per repository and branch and cached for 6 hours: the strictest
`pull_request` rule from `GET /repos/{repo}/rules/branches/{branch}` (rulesets,
readable with read access) and classic branch protection's
`requiredApprovingReviewCount` over GraphQL, which GitHub hides from anyone below
maintain. A reader therefore sees rulesets only: `1/2` when a rule is known,
`1` when it is not, nothing for a PR nobody approved and no rule. It is only
looked up while the main window shows a list, since the notch never shows the
count: running it on every sync cost requests nobody saw, and the extra work on
the main actor right after a sync was enough to make two tab-loading tests miss
their wait on CI. The lookup
never throws, so a repository that errors is not asked again every sync, and it
goes through `QueryClient.prefetch` so the cache can settle it. Holding a key
before its first fetch makes an entry with no staleness and refetches it
forever, which is why there is no `hold` here. "No reviews yet" lists PRs with
no approval, change request or comment review from anyone but the author and
bots.

## The PR detail

**Resolve with Claude is a fixed pipeline with Claude in two slots.** GitHub's
`mergeable` rides in the PR and in the heartbeat (`UNKNOWN`, which GitHub
answers while it computes, never counts as a change), so a branch that starts
conflicting is read again on the next beat. Resolving runs in its own worktree
(`<pr>-resolve`, next to the AI review's), in this order: fetch the base, run
the project's checks on the PR as it is, `git merge --no-ff`, Claude resolves
the conflicted files (up to 3 tries until no marker is left), the checks run
again and Claude fixes what the merge broke (up to 3 tries), then Diple
commits and pushes to the head branch, never with force. Checks that already
failed before the merge are reported and not used, so Claude is never asked to
"fix" a test that needs a database. The checks come from the project:
`Package.swift`, a `package.json` test script (installing first when there is
no `node_modules`), `Cargo.toml`, `go.mod`, or a `test:` target in a
`Makefile`. Claude may edit files and read git there, and is denied commit,
push, merge, rebase, reset, checkout, `gh`, `curl` and the web. A fork is
pushed to its own repository, by swapping the repo in the origin URL. With
"Push resolved conflicts without asking" off, it stops after the commit and
waits for Push. The button shows on your own pull requests and on anyone's you can push to:
the head repository gives you write, or the author allows maintainer edits
and you can write to the base (a fork like danilofuchs/diple into
chagas42/diple). On someone else's pull request it always stops before the
push and waits for you, whatever the setting, so a teammate's branch does not
move under them unannounced. Two people resolving the same pull request
cannot overwrite each other, because the push never forces: the second push is
rejected. Diple then fetches the branch again; when the base is already in it,
the card says "Someone already resolved it" with that commit, and when the
branch moved for another reason (the author pushed meanwhile) it starts once
more from the new tip and gives up only if it moves again. On one Mac, a
`<worktree>.lock` file holding the pid keeps a second Diple (a dev build next
to the installed one) from removing the worktree mid-run; a lock whose process
is gone is taken over. `viewerCanUpdateBranch` is not a push permission:
it backs GitHub's "Update branch" button, which is off exactly when the branch
conflicts, so it said false to the repository's admin on their own PR. Tested with the real claude on a realistic conflict (a
discount on one side, rounding to cents on the other): 3 runs, all kept both.

**A thread's code is parsed once, and shows only what the comment marks.** On
a new file GitHub's `diffHunk` is the whole file down to the commented line,
hundreds of lines. `DiffHunkView` used to split and highlight it in `init`, and
since the detail observes the whole `AppModel`, every publish rebuilt every
thread and highlighted every line again: about 10 ms per 300 lines in a debug
build, per thread, per publish. `HunkCache` now keeps the parsed rows (cleared
past 300 hunks), and a hunk shows what GitHub's own page shows: the comment's
`startLine` through `line`, or the line and the 3 above it for a one-line
comment, with the rest behind "Show N more lines", which turns into "Hide N lines" once open. The threads sit in a
`LazyVStack` so off-screen ones are not built. `startLine` is fetched with the
thread; threads cached before it decode with none.

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

**SwiftPM stamps the deployment target as the SDK.** `swift build` links with
`sdk 14.0` in `LC_BUILD_VERSION` even when it compiled against the macOS 27
SDK, and AppKit reads that field to decide whether an app gets Liquid Glass:
below 26 it keeps the old controls, toolbar and sidebar in compatibility mode.
`make app` rewrites the field with `vtool` to the SDK actually used, keeping
`LSMinimumSystemVersion` as the minimum. `otool -l <binary> | grep -A4
LC_BUILD_VERSION` shows what a build got.

**Every build is a different app to Accessibility.** An ad-hoc signature has
no certificate, so its designated requirement is the code hash (`codesign -d
-r- Diple.app` prints `cdhash H"…"`), and TCC stores that requirement with the
grant. A new build or an update no longer matches it: `AXIsProcessTrusted()`
returns false while System Settings → Privacy & Security → Accessibility still
shows Diple switched on. Removing Diple from the list with − and asking again
(`AXIsProcessTrustedWithOptions` with the prompt) records the running build. Settings → Appearance → Menu bar says so
while it waits, and re-reads the trust every second until it is granted.

**Start at login registers this copy.** `SMAppService.mainApp` records the
bundle that called it, at the path it ran from, so turning it on from a build
in `build/` starts that build at login. Its status, not a stored setting, is
the source of truth: removing Diple in System Settings → Login Items turns the
switch off the next time Settings is shown.

## Releasing

**Actions are pinned to a commit, not a tag.** The release job can write to the
repository and holds `TAP_TOKEN`, and a tag like `v2` can be moved to other
code at any time, so every `uses:` names a commit with its version beside it.
Dependabot opens one grouped `ci:` pull request a week when a newer version of
any of them is out, which keeps the pins from going stale.

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
which is what the timer calls. The notch's `clock` is the frame's time too, so
the hover wait is measured against the scripted pointer.

**Updating through Homebrew refreshes the tap first.** `brew upgrade` only
refreshes taps when its last refresh is older than a day, so right after a
release it can see no new version and exit 0 having done nothing. The update
runs `brew update` first. Homebrew quits a running cask app before replacing
it and reopens it after, so Diple does not kill itself; a final `open` covers
a run where it did not. If the command ends and this Diple is still running,
the version on disk decides: newer means relaunch into it, unchanged means
the install failed and Settings says so, instead of spinning forever.

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
