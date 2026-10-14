# Typed iterator / emote receiver observation

Prepared independent pure-DM runtime source; no captures or executed expectations yet.
Root must compile and run pinned BYOND first, then compare actual native values using
existing OwnedJob/trusted runtime helpers. No new runner is introduced here.

The source separates filtered typed iteration, `as anything` iteration, the actual
`O.see_emote(src, final_message, mode)` call shape, and a foreign `/screen` receiver.
The mixed unfiltered call intentionally catches a receiver error: its presence is
an observation, not proof of a compiler defect. Numeric arithmetic suggests objects
44, filtered count 2, unfiltered count 3, filtered dispatch 44, and mixed caught 1;
these are proposed independent expectations pending authenticated BYOND capture.

This isolates iterator type filtering versus receiver/cache state. The game failure
at custom_emote.dm:123 calls a proc declared on /obj using a /screen instance;
/screens inherit /atom/movable, not /obj. `as anything` itself does not justify
filtering the receiver. If the game list legitimately contains screens, that is a
source behavior question; only paired receiver/list provenance establishes a
native lowering discrepancy.

`run.py` delegates compilation, pinned acquisition and runtime lifetime entirely
to `bodyless_loop_runtime.run.main`. Pass its existing `--native`, `--template`,
`--dm`, `--dd` and SHA arguments, plus `--output-root
E:/dq-cache/dmb-typed-iterator-emote-runtime`. The observation reader checks the
complete ordered marker roster and preserves runtime errors. It also compares
`isobj`, strict `istype(/obj)`, typed iteration and actual type paths for an object,
a screen and a plain movable. BYOND executes first and supplies the reference.

## Captured divergence, 2026-10-10

Pinned BYOND 516.1687 and immutable native 4f08394f8b both completed this fixture with no uncaught runtimes; all owned children were reaped. Root `/obj` iteration disagrees: BYOND counts 2 versus native 3 for objects plus screen, and 2 versus 4 after adding a plain movable. Strict `istype(value, /obj)` agrees (screen and plain movable are false), while `isobj` agrees true for both. Subtype-filtered dispatch and unfiltered iteration agree. This isolates a native root-type iterator filter defect, not a receiver-label or `istype` intrinsic difference. Receipt: `E:/dq-cache/dmb-typed-iterator-emote-runtime/90bdbbf162d94c9dbc889b9f3d27e3df/receipt.json`. The production correction and its passing capture are pending.
