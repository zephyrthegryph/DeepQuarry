# Wet leather native dependency handoff

Branch: `codex/wetleather-native-key-1012`.
Verified commit: `b9e7351db7f3`, merged master `bfac2aaea6`.

The wetness producer uses `TRACKED` rather than `TRACKED_BRIDGED`: one
`CHANGE_EXPLICIT` bridge becomes zero. The tanning rack watches the actual
leather while drawing, following its tracked wetness and detaching when the
relation changes. Merely reading through the typed relation was insufficient;
the first gate caught that missing subscription and the repaired gate passes.
No manual redraw or substitute channel was added.

Lane-ready passed: 30 tests, zero failures, production compile zero errors,
DreamChecker zero diagnostics, analyzer and ratchets clean. The focused list
was `dq_tanning_rack_tracks_leather_wetness dq_requirement_protocol_pin
dq_conversion_pin`; lane-ready added its normal smoke and incremental look
checks. The new regression warms the real rack, changes real leather wetness
through its setter, and checks both replacement of the wet overlay and
preservation of the drying relation.

The 29 requirement captures refreshed on this branch are the previously
audited master changes from `f5007aa10f5f`, with the per-class causes recorded
in `intended_changes.md`. No conversion or appearance golden was blessed for
the wetness migration. Generated dependency files remain uncommitted.
