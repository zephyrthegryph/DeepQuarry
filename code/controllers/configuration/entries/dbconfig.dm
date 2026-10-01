/datum/config_entry/flag/sql_enabled // for sql switching
	protection = CONFIG_ENTRY_LOCKED

/datum/config_entry/string/address
	default = "localhost"
	protection = CONFIG_ENTRY_LOCKED | CONFIG_ENTRY_HIDDEN

/datum/config_entry/number/port
	default = 3306
	min_val = 0
	max_val = 65535
	protection = CONFIG_ENTRY_LOCKED | CONFIG_ENTRY_HIDDEN

/datum/config_entry/string/feedback_database
	default = "test"
	protection = CONFIG_ENTRY_LOCKED | CONFIG_ENTRY_HIDDEN

/datum/config_entry/string/feedback_login
	default = "root"
	protection = CONFIG_ENTRY_LOCKED | CONFIG_ENTRY_HIDDEN

/datum/config_entry/string/feedback_password
	protection = CONFIG_ENTRY_LOCKED | CONFIG_ENTRY_HIDDEN

/datum/config_entry/number/async_query_timeout
	default = 10
	min_val = 0
	protection = CONFIG_ENTRY_LOCKED

/datum/config_entry/number/blocking_query_timeout
	default = 5
	min_val = 0
	protection = CONFIG_ENTRY_LOCKED

/datum/config_entry/number/pooling_min_sql_connections
	default = 1
	min_val = 1

/datum/config_entry/number/pooling_max_sql_connections
	default = 25
	min_val = 1

/datum/config_entry/number/max_concurrent_queries
	default = 25
	min_val = 1

/datum/config_entry/number/max_concurrent_queries/ValidateAndSet(str_val)
	. = ..()
	if (.)
		SSdbcore.max_concurrent_queries = config_entry_value

/// The exe for mariadbd.exe.
/// Shouldn't really be set on production servers, primarily for EZDB.
/datum/config_entry/string/db_daemon
	protection = CONFIG_ENTRY_LOCKED | CONFIG_ENTRY_HIDDEN

/// Per-query execution timeout in milliseconds for async queries sitting in queries_active.
/// A query that remains in-flight longer than this is forcibly abandoned and its slot freed.
/// This prevents a small number of slow/hung queries from exhausting the max_concurrent_queries
/// pool and blocking all database access. Set to 0 to disable enforcement.
/// Default: 30000 (30 seconds). Minimum: 1000 ms.
/datum/config_entry/number/slow_query_timeout_ms
	default = 30000
	min_val = 0

/datum/config_entry/flag/enable_stat_tracking
	protection = CONFIG_ENTRY_LOCKED | CONFIG_ENTRY_HIDDEN

/// Record server metrics and events (code/modules/metrics/) to the metric_* tables.
/// Needs the database; does nothing without it.
/datum/config_entry/flag/metrics_enabled
	protection = CONFIG_ENTRY_LOCKED

/// Base URL of the admin viewer (tools/admin-viewer), e.g. http://127.0.0.1:8090.
/// Empty hides the "Admin Viewer" verb's link.
/datum/config_entry/string/metrics_viewer_url
	protection = CONFIG_ENTRY_LOCKED

/// Shared secret the game signs admin viewer links with; the viewer verifies them with the
/// same value (VIEWER_SECRET). Without it no link is issued.
/datum/config_entry/string/metrics_viewer_secret
	protection = CONFIG_ENTRY_LOCKED | CONFIG_ENTRY_HIDDEN

/// Minutes an admin viewer link stays valid.
/datum/config_entry/number/metrics_viewer_link_minutes
	default = 720
	min_val = 1
	protection = CONFIG_ENTRY_LOCKED

/// When set, the localhost-only diagnostic world/Topic probes (mcdiag, omsteps, mcprof_*, ...)
/// also require `key=<this>` in the topic.
/datum/config_entry/string/diag_topic_key
	protection = CONFIG_ENTRY_LOCKED | CONFIG_ENTRY_HIDDEN
