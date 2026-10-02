// Declared dependencies (doc/rewrite/dx_conventions.md, "Declared dependencies").
// Runtime: code/datums/capabilities/derived.dm and refresh.dm.
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
/// on_state_changed(bits). Only a plain changed(E) (no var named) raises it.
#define DEP_LEGACY (1<<4)
/// Every output a declaration can name.
#define DEP_OUTPUTS (DEP_RUN | DEP_DRAW | DEP_UI | DEP_PUSH)
/// derive() value number i (0-based, declaration order) is bit DEP_VALUE_SHIFT + i.
#define DEP_VALUE_SHIFT 5
/// The most derive() values one type can declare.
#define DEP_VALUE_MAX 12
/// Every derive() value bit.
#define DEP_VALUES (((1 << DEP_VALUE_MAX) - 1) << DEP_VALUE_SHIFT)
/// A plain changed(E): everything is re-derived.
#define DEP_ALL (DEP_OUTPUTS | DEP_LEGACY | DEP_VALUES)

// ---- derived() entry kinds ----
#define DKIND_RUNS 1
#define DKIND_DRAWN 2
#define DKIND_UI 3
#define DKIND_DERIVE 4
#define DKIND_PUSH 5
/// reaction_reads(handler, ...): more reads of the on_change() reaction with that handler (generated reads).
#define DKIND_REACTION 6

// Outputs must not write state: in test builds a tracked write while an output runs is reported.
#if defined(UNIT_TESTS)
#define DERIVED_EVAL_BEGIN GLOB.derived_evaluating++
#define DERIVED_EVAL_END GLOB.derived_evaluating--
#else
#define DERIVED_EVAL_BEGIN
#define DERIVED_EVAL_END
#endif
