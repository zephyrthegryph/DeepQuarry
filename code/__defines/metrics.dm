// Server metrics (code/modules/metrics/, SQL/metrics_schema.sql, tools/admin-viewer).

/// How often the metrics lane samples every source.
#define METRICS_SAMPLE_INTERVAL (10 SECONDS)
/// Samples buffered before a flush to the database (one batched write per flush).
#define METRICS_SAMPLES_PER_FLUSH 6
/// Most event rows kept per flush; past it events are only counted (metrics/events_dropped).
#define METRICS_EVENT_CAP 400
/// Overrun ticks recorded in full per flush (the worst ones); every overrun is still counted.
#define METRICS_OVERRUNS_PER_FLUSH 5
/// A behaviour is sampled once it spends at least this many ms per second.
#define METRICS_BEHAVIOUR_MIN_MS_PER_S 0.05

// Event kinds (metric_event.kind).
#define METRICS_EVENT_RUNTIME "runtime"
#define METRICS_EVENT_OVERRUN "overrun"
#define METRICS_EVENT_TICKET "ticket"
#define METRICS_EVENT_ADMIN_VERB "admin_verb"
#define METRICS_EVENT_ROUND "round"

// Metric categories (metric_key.category).
#define METRICS_CAT_SERVER "server"
#define METRICS_CAT_MC "mc"
#define METRICS_CAT_SERVICE "service"
#define METRICS_CAT_LANE "lane"
#define METRICS_CAT_BEHAVIOUR "behaviour"
#define METRICS_CAT_PLAYERS "players"
#define METRICS_CAT_STAFF "staff"
#define METRICS_CAT_ERRORS "errors"
#define METRICS_CAT_IO "io"
/// What keeps an idle server busy (code/modules/metrics/metrics_churn.dm).
#define METRICS_CAT_CHURN "churn"
/// Keys of each churn kind reported per sample, busiest first.
#define METRICS_CHURN_TOP 8
/// Counts one `kind` event (draws, timers, signals, lights, power_edits) under `key` for the churn metrics.
#define CHURN_COUNT(kind, key) GLOB.churn_census.kind[key] += 1

/// Records an event if metrics are running; safe to call from anywhere, at any point of boot.
#define METRICS_EVENT(kind, category, signature, ckey, message, payload) GLOB?.metrics_service?.event(kind, category, signature, ckey, message, payload)

// Names in an overrun tick's breakdown (Master.performance_tick_breakdown()) besides the subsystems.
/// Work that ran this tick before the MC's iteration: resumed sleeping procs, verbs run on the spot,
/// Topic calls, clicks, world/Tick callbacks.
#define PERF_OUTSIDE_MC "Outside MC"
/// Object-model work the tick meter charged (behaviours, world service lanes, the scheduler core).
#define PERF_OBJECT_MODEL "Object model"
/// The rest of the MC's iteration: kernel phases and bookkeeping nothing charged.
#define PERF_MC_OTHER "MC other"

/// A tick this far over (percent of a tick) starts a profile capture (metrics_capture.dm).
#define METRICS_SPIKE_USAGE 300
/// Least time between two spike captures.
#define METRICS_PROFILE_COOLDOWN (5 MINUTES)
/// The first steady-play profile starts this long after the round start (metrics_profile_steady).
#define METRICS_PROFILE_STEADY_FIRST (5 MINUTES)
/// Procs kept in a profile capture's event, by self time.
#define METRICS_PROFILE_TOP 40
/// Call stack lines kept with a runtime.
#define METRICS_RUNTIME_STACK_LINES 12
#define METRICS_EVENT_PROFILE "profile"
