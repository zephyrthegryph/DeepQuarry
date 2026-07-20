# TGUI performance profiling

Run `bun run tgui:benchmark` from `tgui/`. It renders a deliberately large button
interface, performs repeated updates, reports React commit timing, and checks cursor
stability. Happy DOM does not perform real paint or OS cursor composition, so this
detects React/DOM regressions but cannot prove BYOND's compositor is healthy.

For live profiling, start `bin/tgui-dev.cmd` and open any TGUI in a development
client. Expand the `TGUI PERF` panel in the lower-right. It reports React commits,
backend payload/application cost, action-to-update latency, frame stalls, and cursor
or hit-target changes under a stationary pointer. Reset before reproducing, then
export JSON. Visible flicker with zero stationary changes implicates the embedded
browser compositor. The panel and observers are excluded from production builds.

For startup captures, export immediately after the target's first cold open. For a
warm comparison, reset that target's profiler, close it, and reopen it. The export records backend receipt,
route resolution, async chunk load, content commit, first paint, geometry completion,
and window reveal. The overlay also shows the largest nested payload fields and flags
updates above 100 KB or commits longer than one 60 Hz frame.

The startup panel identifies warm versus cold pooled shells, whether the shell came
from the hidden native template, and records the early geometry probe. A small idle
reserve is replenished as windows are acquired. Geometry and visibility are sent in
one native transaction, guarded by a per-acquisition generation token. Interfaces
that expose `dq_server_profile` (currently Preferences)
also report pre-backend, catalog-build, and preview-render costs. Other interfaces
still begin at first backend receipt unless they add equivalent server phase data.
