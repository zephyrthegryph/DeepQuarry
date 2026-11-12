// Declared dependencies (doc/rewrite/dx_conventions.md, "Declared dependencies").
// Runtime: code/engine/change/derived.dm and refresh.dm.
//
// should_run(), draw() (with hidden_verbs()), tgui_data() and push_to_rust() are derived from state. A
// type lists what each one reads in derived(); a change to one of those reads re-derives only that
// output, once per frame.

// ---- outputs: the bits of a queued entity's refresh_queued ----
/// should_run(): wake or park the periodic cadence.
#define DEP_RUN (1<<0)
/// draw() and hidden_verbs(): the look and the verb hides.
#define DEP_DRAW (1<<1)
/// Open tgui windows: tgui_data() is pushed.
#define DEP_UI (1<<2)
/// push_to_rust(): the coalesced Rust sync.
#define DEP_PUSH (1<<3)
/// on_state_changed(bits). Only a plain state_changed(E) (no var named) raises it.
#define DEP_LEGACY (1<<4)
/// Open tgui windows: ui_static_data() is resent (a full update). Read-driven like DEP_UI (ui_static_from()).
#define DEP_UI_STATIC (1<<19)
/// Every output a declaration can name.
#define DEP_OUTPUTS (DEP_RUN | DEP_DRAW | DEP_UI | DEP_PUSH | DEP_UI_STATIC)
/// derive() value number i (0-based, declaration order) is bit DEP_VALUE_SHIFT + i.
#define DEP_VALUE_SHIFT 5
/// The most derive() values one type can declare.
#define DEP_VALUE_MAX 12
/// Every derive() value bit.
#define DEP_VALUES (((1 << DEP_VALUE_MAX) - 1) << DEP_VALUE_SHIFT)
/// A plain state_changed(E): everything is re-derived.
#define DEP_ALL (DEP_OUTPUTS | DEP_LEGACY | DEP_VALUES)
/// Beside DEP_ALL on a fresh atom's creation mark (caps_init()); any real mark clears it (refresh_mark()). An entity still carrying it is in
/// its type's default state, so a type whose default look is empty skips it (the default-look stamp, code/engine/change/look_stamp.dm).
#define DEP_CREATED (1<<17)
/// A fresh atom whose first draw is deferred until a client is near it or something marks it (refresh_park_backlog(), code/engine/change/look_stamp.dm).
/// It is out of GLOB.refresh_queue and owes its whole first refresh: refresh_mark() puts it back with DEP_ALL, interest_enter() queues its draw when a client holds the chunk. Alone in
/// refresh_queued it means "nothing pending", so a first-mark test reads REFRESH_IDLE().
#define DEP_PARKED (1<<18)
/// TRUE when nothing is pending on E: not queued, or only parked (its first draw owed but not queued).
#define REFRESH_IDLE(E) (!((E).refresh_queued & ~DEP_PARKED))

// ---- derived() entry kinds ----
#define DKIND_RUNS 1
#define DKIND_DRAWN 2
#define DKIND_UI 3
#define DKIND_DERIVE 4
#define DKIND_PUSH 5
/// reaction_reads(handler, ...): more reads of the on_change() reaction with that handler (generated reads).
#define DKIND_REACTION 6
/// ui_static_from(...): what the window's ui_static_data() reads.
#define DKIND_UI_STATIC 7

// Outputs must not write state: in test builds a tracked write while an output runs is reported.
#if defined(UNIT_TESTS)
#define DERIVED_EVAL_BEGIN GLOB.derived_evaluating++
#define DERIVED_EVAL_END GLOB.derived_evaluating--
#else
#define DERIVED_EVAL_BEGIN
#define DERIVED_EVAL_END
#endif

// ---- the change graph's plan bits (code/engine/change/plan.dm, generated in code/engine/_generated/plans.dm) ----
/// The type's own draw() reads the key on the holder.
#define PLAN_DRAW (1<<0)
/// The type's draw() reads the key one container, turf or area hop away ("<hop>.<var>").
#define PLAN_DRAW_HOP (1<<1)

// ---- the change graph's reader classes (step 3d: who reads a key besides the outputs; plan_reader_bits(), code/engine/change/plan.dm) ----
/// A static reaction (on_change / on_cross / every gate), a derived() or generated read, or a sequence step of some type may read the key.
#define PLAN_READ_REACT (1<<0)
/// An on_change() hook of some type's declarations may read the key (on the holder or as the far end of a hop).
#define PLAN_READ_HOOK (1<<1)
/// A lifecycle form (registry key, radio frequency, derives, lives_while, adjacency) of some type may follow the key.
#define PLAN_READ_LIFEFORM (1<<2)
#define PLAN_READ_ALL (PLAN_READ_REACT | PLAN_READ_HOOK | PLAN_READ_LIFEFORM)

/// The look-drift audit (refresh_sweep_step(), refresh_check_drift()) exists only in debug and test builds: those that define DEBUG or CITESTING (BYOND ignores
/// -DDEBUG on the command line, so the build passes both) or UNIT_TESTS. A production build compiles none of it. A benchmark build compiles the procs (the test files it carries call them) but never steps the audit, so it measures production.
#if defined(UNIT_TESTS) || defined(DEBUG) || defined(CITESTING)
#define DQ_LOOK_AUDIT
#endif
