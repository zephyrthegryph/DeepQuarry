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

/// Records an event if metrics are running; safe to call from anywhere, at any point of boot.
#define METRICS_EVENT(kind, category, signature, ckey, message, payload) GLOB?.metrics_service?.event(kind, category, signature, ckey, message, payload)
