// Body factors: the body's stats. See doc/rewrite/proposals/stat_layer.md, code/contracts/ids/body_stats.dm (the stats: STAT_SLOWDOWN and the rest)
// and code/modules/body/factors.dm.
//
// A body factor is a named quantity that any number of sources contribute to (afflictions, reagents, modifiers, species and traits, forms, worn
// equipment) and any number of consumers read as a var of the mob (`L.slowdown`). Every factor is a stat on /mob/living with one combine rule, a
// base and bounds, declared once with STAT. Sources declare static alist tables keyed by the stats' ids, e.g.
// `factors = alist(STAT_SLOWDOWN = 1, STAT_ACCURACY = -20)`.

// --- Stabilisation ----------------------------------------------------------------------
/// Stasis deeper than this keeps the patient asleep (the stasis stat: share of life processes suspended, 0..1; stasis bags, sleepers, cryopods).
/// The body's stasis clock (code/modules/medical/stabilisation/stasis.dm) reads it once per Life() cycle; afflictions, metabolism, breathing and
/// blood skip paused cycles.
#define STASIS_SLEEP_THRESHOLD 0.5

// --- Action blocks (the action_blocks stat) ------------------------------------------------
/// Can't speak (airway closed, respiratory failure).
#define ACTION_BLOCK_SPEECH     (1<<0)
/// Can't perform surgery.
#define ACTION_BLOCK_SURGERY    (1<<1)
/// Can't hold anything in the left hand.
#define ACTION_BLOCK_HOLD_LEFT  (1<<2)
/// Can't hold anything in the right hand.
#define ACTION_BLOCK_HOLD_RIGHT (1<<3)

/// Afflictions only trigger a factor refresh when severity crosses a band
/// this wide (the contribution uses the severity at the refresh).
#define FACTOR_SEVERITY_BAND 10

/// Highest per-tick chance (%) that poor motor control drops a held item.
#define FACTOR_MAX_DROP_CHANCE 25
