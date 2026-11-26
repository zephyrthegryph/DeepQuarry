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
#define KM_MAX_SYSTEMS 192
/// Ticks the flight recorder keeps (60 s at 20 fps).
#define KM_RING_LEN 1200
/// A gap this long (real ms) between two ends of tick is a freeze, whatever ran in it.
#define KM_STALL_MS 1000
/// How many freezes the meter keeps for the Server page.
#define KM_STALL_KEEP 10
/// Systems named in a tick record and its overrun log line.
#define KM_TOP_N 8
/// How many callbacks or redrawn types an overrun line names per system.
#define KM_ATTR_TOP_N 3
/// A charge smaller than this counts as this much, so a system that ran at all is marked active for the tick.
#define KM_MIN_CHARGE_MS 0.0001
/// The running-total accumulators flush this many ms into their high part (BYOND numbers are single precision:
/// a total above ~1e6 ms can no longer take a 0.05 ms increment).
#define KM_FLUSH_MS 1000
/// A single callback this long (ms) is logged by name with its holder and where it was (km_slow_call()), beyond the totals the settle table keeps.
#define KM_SLOW_CALL_MS 100
/// A tick over this percentage of a tick is an overrun (the same definition as Kernel.record_performance_tick).
#define KM_OVERRUN_USAGE 100
/// Overrun log lines: every overrun of a streak up to this long is logged, then at most one per KM_LOG_MIN_GAP.
#define KM_LOG_FULL_STREAK 10
#define KM_LOG_MIN_GAP (1 SECONDS)
/// The slow-tick trace (code/world/kernel/measure/slow_tick.dm): a tick over config slow_tick_trace_percent is written to the debug log with its
/// ranked spans. Spans kept per tick, the rows written, the smallest span worth keeping, the smallest unitemised remainder worth a row, and
/// the most traces written per real minute.
#define KM_SLOW_TRACE_PERCENT 200
#define KM_SLOW_SPANS 192
#define KM_SLOW_TRACE_TOP 16
#define KM_SLOW_SPAN_MIN_MS 0.25
#define KM_SLOW_TRACE_REST_MS 1
#define KM_SLOW_TRACE_PER_MINUTE 12
/// The threshold is re-read from config this often (ticks): the live meter is built before config loads.
#define KM_SLOW_TRACE_REFRESH_TICKS 200
/// What a span is.
#define KM_SPAN_ITEM 1
#define KM_SPAN_SYSTEM 2
#define KM_SPAN_ATTR 3
#define KM_SPAN_NATIVE 4
#define KM_SPAN_LOOP 5
#define KM_SPAN_REST 6
#define KM_SPAN_STEP 7
#define KM_SPAN_DRAIN 8
/// Work inside another span (one stat evaluation, one on_change hook, one late notice inside a drain): ranked, never counted as covering its phase.
#define KM_SPAN_INNER 9
/// Adds an inner span named `name_expr` (evaluated only when it is recorded) if the work that began at `started` (a TICK_USAGE) took KM_SLOW_SPAN_MIN_MS or more.
#define KM_SLOW_INNER(started, name_expr) if(TICK_USAGE_TO_MS(started) >= KM_SLOW_SPAN_MIN_MS) km_meter().slow.span(KM_SPAN_INNER, name_expr, TICK_USAGE_TO_MS(started))

/// How fast the measured BYOND reserve (maptick peak) forgets a spike, per tick.
#define KM_MAP_PEAK_DECAY 0.98

// Pseudo systems, registered first so hot paths use the constant instead of a lookup (see /datum/km_systems/New()).
/// engine scheduler work no behaviour owns: the derived-value queue, services, and the remainder of a
/// Behaviours fire (deadline wheel walking, audits, bookkeeping).
#define KM_SYS_SCHED_CORE 1
/// The Rust world step and its native wake delivery.
#define KM_SYS_NATIVE_STEP 2
/// Clicks handled outside the MC (atom/Click), charged where they run.
#define KM_SYS_INPUT 3
/// Work charged to a behaviour or subsystem with no system bound, and overflow past KM_MAX_SYSTEMS.
#define KM_SYS_OTHER 4
/// The presentation lane's declared-appearance and refresh drain, change reactions included, and the
/// refresh drift audit (strict on every frame in test builds).
#define KM_SYS_APPEARANCE 5
#define KM_SYS_PSEUDO_COUNT 5
/// A subsystem whose own cost is decomposed into other systems (SSbehaviours) and so is not charged as one.

#define KM_KEY_SCHED_CORE "sched_core"
#define KM_KEY_NATIVE_STEP "native_step"
#define KM_KEY_INPUT "input"
#define KM_KEY_OTHER "other"
#define KM_KEY_APPEARANCE "appearance_drain"

/// What a system is.
#define KM_KIND_PSEUDO 0
#define KM_KIND_SCHED 1
#define KM_KIND_MC 2

/// Kinds of player input the latency record separates.
#define KM_INPUT_CLICK 1
#define KM_INPUT_VERB 2

// Attribution inside sched_core and appearance_drain (code/world/kernel/measure/attribution.dm).
/// Rows the attribution table holds; a key past it lands on a per-kind overflow row and the cheaper half is dropped at the end of the tick.
#define KA_MAX_ROWS 4096
/// A budgeted table walk (km_attr walk_step(), km_ledger walk_step()) looks at the clock every this many rows.
#define KA_WALK_CHECK_ROWS 32
/// What a row is: a timer callback and a change reaction (both reported as callbacks), or a redraw of an atom type.
#define KA_KIND_CALLBACK 1
#define KA_KIND_REACTION 2
#define KA_KIND_DRAW 3
#define KA_CALLBACK_KINDS ((1 << KA_KIND_CALLBACK) | (1 << KA_KIND_REACTION))
/// How select_top() ranks: this tick's ms, all ms, ms since "Initializations complete".
#define KA_BY_TICK 1
#define KA_BY_TOTAL 2
#define KA_BY_POST 3
// A row's fields (a fixed-length list). Totals are lo + hi (see KM_FLUSH_MS).
#define KA_KIND 1
#define KA_SYS 2
#define KA_A 3
#define KA_B 4
#define KA_COUNT 5
#define KA_MS 6
#define KA_MS_HI 7
#define KA_MAX 8
#define KA_TMS 9
#define KA_TSER 10
#define KA_POST_COUNT 11
#define KA_POST_MS 12
#define KA_POST_MS_HI 13
#define KA_LAST 14
#define KA_LATE_COUNT 15
#define KA_LATE_MS 16
#define KA_LATE_MS_HI 17
/// SETTLE: summaries are logged this long and KA_SETTLE_SECOND after init complete (deciseconds); work past the first counts as "late".
#define KA_SETTLE_FIRST (2 MINUTES)
#define KA_SETTLE_SECOND (10 MINUTES)

// The tick ledger (code/world/kernel/measure/ledger.dm): every ms of a tick, up to the end of the kernel's iteration, belongs to exactly one category.
/// Categories. KM_CAT_KERNEL is the kernel loop's own walking (a phase's list walk, deadline wheel and slot bookkeeping); KM_CAT_UNATTRIBUTED is the
/// residual, the time inside the kernel iteration that no marked region covers.
#define KM_CAT_UNATTRIBUTED 1
#define KM_CAT_BYOND_PRE 2
#define KM_CAT_INPUT 3
#define KM_CAT_KERNEL 4
#define KM_CAT_SYSTEM 5
#define KM_CAT_TIMER 6
#define KM_CAT_STAT_DRAIN 7
#define KM_CAT_STAT_EVAL 8
#define KM_CAT_ON_CHANGE 9
#define KM_CAT_NOTICE 10
#define KM_CAT_REACTION 11
#define KM_CAT_DRAW 12
#define KM_CAT_NATIVE 13
#define KM_CAT_NATIVE_DELIVERY 14
#define KM_CAT_LIGHTING 15
#define KM_CAT_MOVEMENT 16
#define KM_CAT_GARBAGE 17
#define KM_CAT_SCHED 18
#define KM_CAT_COUNT 18
/// Nesting the ledger follows; a deeper enter is counted and ignored.
#define KM_LEDGER_DEPTH 24
/// Names kept per category (owner type -> proc rows); the cheaper half is dropped at the end of a tick that finds a category past it.
#define KM_LEDGER_ROWS 320
/// Weight of the newest tick in each category's moving average (about 10 s at 20 ticks a second).
#define KM_LEDGER_EMA 0.005
/// Names a category's drill-down lists in the panel and in PERF_PROFILE.
#define KM_LEDGER_TOP 8
// A name row's fields.
#define KL_COUNT 1
#define KL_MS 2
#define KL_MS_HI 3
#define KL_MAX 4
