// Kernel measurement: per-system cost attribution, histograms, the flight recorder and input latency
// (doc: unified plan step 2, code/controllers/measure/). Additive: nothing here changes what runs or when.

/// Bins in every histogram (per-system ms per tick, input wait in ms).
#define KM_HIST_BINS 32
/// Upper edge in ms of bin 1 ("under this"). Bin i >= 2 covers [MIN * R^(i-2), MIN * R^(i-1)); the last bin is open ended.
/// With R = sqrt(2) the last closed edge is 0.02 * 2^15 = 655 ms, well above one tick (50 ms).
#define KM_HIST_MIN_MS 0.02
#define KM_HIST_RATIO SQRT_2
/// 1 / ln(KM_HIST_RATIO): turns ln(ms / MIN) into "how many bins up".
#define KM_HIST_INV_LN_RATIO 2.88539008178
/// The bin a value in ms falls in (1..KM_HIST_BINS). `ms` is evaluated twice: pass a variable.
#define KM_HIST_BIN(ms) ((ms) < KM_HIST_MIN_MS ? 1 : min(KM_HIST_BINS, 2 + floor(log((ms) / KM_HIST_MIN_MS) * KM_HIST_INV_LN_RATIO)))

/// Bins of the "where in the tick did input run" histogram: 5% wide, the last is everything over 100%.
#define KM_DEPTH_BINS 21
#define KM_DEPTH_BIN_WIDTH 5

/// Systems the tables can hold. A system that does not fit is charged to KM_SYS_OTHER.
#define KM_MAX_SYSTEMS 208
/// Ticks the flight recorder keeps (60 s at 20 fps).
#define KM_RING_LEN 1200
/// Systems named in a tick record and its overrun log line.
#define KM_TOP_N 3
/// A charge smaller than this counts as this much, so a system that ran at all is marked active for the tick.
#define KM_MIN_CHARGE_MS 0.0001
/// The running-total accumulators flush this many ms into their high part (BYOND numbers are single precision:
/// a total above ~1e6 ms can no longer take a 0.05 ms increment).
#define KM_FLUSH_MS 1000
/// A tick over this percentage of a tick is an overrun (the same definition as Kernel.record_performance_tick).
#define KM_OVERRUN_USAGE 100
/// Overrun log lines: every overrun of a streak up to this long is logged, then at most one per KM_LOG_MIN_GAP.
#define KM_LOG_FULL_STREAK 10
#define KM_LOG_MIN_GAP (1 SECONDS)
/// How fast the measured BYOND reserve (maptick peak) forgets a spike, per tick.
#define KM_MAP_PEAK_DECAY 0.98

// Pseudo systems, registered first so hot paths use the constant instead of a lookup (see /datum/km_systems/New()).
/// Object-model scheduler work no behaviour owns: the derived-value queue, services, and the remainder of a
/// Behaviours fire (deadline wheel walking, audits, bookkeeping).
#define KM_SYS_OM_CORE 1
/// The Rust world step and its native wake delivery.
#define KM_SYS_OM_NATIVE 2
/// Clicks handled outside the MC (atom/Click), charged where they run.
#define KM_SYS_INPUT 3
/// Work charged to a behaviour or subsystem with no system bound, and overflow past KM_MAX_SYSTEMS.
#define KM_SYS_OTHER 4
/// The presentation lane's declared-appearance and refresh drain, change reactions included, and the
/// refresh drift audit (strict on every frame in test builds).
#define KM_SYS_OM_APPEARANCE 5
#define KM_SYS_PSEUDO_COUNT 5
/// A subsystem whose own cost is decomposed into other systems (SSbehaviours) and so is not charged as one.
#define KM_SYS_DECOMPOSED -1

#define KM_KEY_OM_CORE "om_core"
#define KM_KEY_OM_NATIVE "om_native"
#define KM_KEY_INPUT "input"
#define KM_KEY_OTHER "other"
#define KM_KEY_OM_APPEARANCE "om_appearance"

/// What a system is.
#define KM_KIND_PSEUDO 0
#define KM_KIND_OM 1
#define KM_KIND_MC 2

/// Kinds of player input the latency record separates.
#define KM_INPUT_CLICK 1
#define KM_INPUT_VERB 2
