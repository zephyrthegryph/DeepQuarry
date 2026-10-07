// The stat layer's constants and declaration forms (doc/rewrite/final_api.html, section 5 "Stats, holds, grants and overrides" and section 7
// "Change tracking and dependencies"; section 19 "E3, stats").
//
// STAT(T, name, RULE, base =, reapply =, units =, formula = PROC_REF(x), reads = list(...), schema = num(...)) declares a stat on a type: its
// rule, its base, its options. The marker expands to nothing in DM; `analyze gen stats` writes the stat's var and registration
// (code/engine/_generated/stats.dm) and `analyze gen declare_ids` its id, STAT_<NAME>. Stat ids start at STAT_ID_BASE and capability-key ids
// (CAPKEY_ID) at CAPKEY_ID_BASE, both far above any number a contribution's constant value will be, so a bare id in
// contributes(STAT_X, STAT_Y) is told from a value by its range and by being registered.

/// Stat ids are STAT_ID_BASE + n.
#define STAT_ID_BASE 100000
/// A status's companion immunity stat (STAT_<NAME>_IMMUNE) is the status id plus this.
#define STAT_IMMUNE_OFFSET 10000
/// STAT_IMMUNE(STATUS_STUN): the companion boolean stat of a status.
#define STAT_IMMUNE(status_id) ((status_id) + STAT_IMMUNE_OFFSET)
/// A status id is its stat's id: STATUS_STUN is STAT_STUN.
#define STATUS_ID(stat_id) (stat_id)

/// The combine rules (section 5 "The combine rules"). Text, so a dump and a table-driven test read as the declaration does.
#define STAT_RULE_ALL "ALL"
#define STAT_RULE_ANY "ANY"
#define STAT_RULE_SUM "SUM"
#define STAT_RULE_PRODUCT "PRODUCT"
#define STAT_RULE_MAX "MAX"
#define STAT_RULE_MIN "MIN"
#define STAT_RULE_TOP "TOP"
#define STAT_RULE_SET "SET"
#define STAT_RULE_MASK_AND "MASK_AND"
#define STAT_RULE_MASK_OR "MASK_OR"
#define STAT_RULE_FORMULA "FORMULA"

/// reapply =: holding again from the same source.
#define REAPPLY_MAX 1
#define REAPPLY_EXTEND 2
#define REAPPLY_REPLACE 3

/// The clock a hold's `lasts` and `until` are written in.
#define HOLD_CLOCK_WORLD 0
#define HOLD_CLOCK_OWN 1
#define HOLD_CLOCK_BIO 2

/// A source holding more than this many holds releases in slices (phase G), coalesced per target.
#define HOLD_RELEASE_BATCH 256
/// Static contributions of one type to one stat, and the width of a mask stat (DM numbers are exact to 24 bits).
#define STAT_MAX_STATIC 24

/// How a stat reached by a write is settled (section 7 "How the build decides").
#define SETTLE_INLINE 1
#define SETTLE_MARKED 2

/// The rule name a stat report carries.
#define RULE_STAT "stat"

// A hold row (code/engine/stats/store.dm): list(stat id, source, value, expires, priority, flags, clock, reason, serial, key, spec).
#define H_STAT 1
#define H_SOURCE 2
#define H_VALUE 3
/// The deadline on the hold's clock, or 0 for a hold that has none.
#define H_EXPIRES 4
#define H_PRIORITY 5
#define H_FLAGS 6
#define H_CLOCK 7
#define H_REASON 8
#define H_SERIAL 9
/// A second hold key beside (stat, source): a contributes_to entry's own row ("ct:<serial>").
#define H_KEY 10
/// A contribution applied by an activation: the compiled contribution evaluated at recompute time (its condition and value are live).
#define H_SPEC 11

/// The hold outlives its datum source (outlives_source = TRUE); by default it is released when the source dies.
#define HF_OUTLIVES (1<<0)
/// The hold replaces the composed value instead of joining it (hold_override).
#define HF_OVERRIDE (1<<1)

/// A marked drain's budget when the kernel gives none, in microseconds of tick time.
#define STAT_DRAIN_BUDGET_US 4000

/// The report name of a cycle among stats.
#define RULE_STAT_CYCLE "\[stat_cycle]"

/// The values of E5's generated READ_* constants (code/engine/_generated/reads.dm, included after the stat layer): the holder root, a plain var read, a system read.
#define SREAD_ROOT_HOLDER 1
#define SREAD_KIND_VAR 0
#define SREAD_KIND_ACCESSOR 1
#define SREAD_KIND_SYSTEM 3

/// What the next marked evaluation is expected to cost, for the budget check before it runs: a fixed charge in test builds (TEST_EVAL_COST), an estimate in
/// microseconds otherwise.
#if defined(UNIT_TESTS)
#define STAT_EVAL_CHARGE TEST_EVAL_COST
#else
#define STAT_EVAL_CHARGE 20
#endif
