/// Cache of the states of icon files
GLOBAL_LIST_EMPTY(icon_states_cache)
/// Cache of the states of icon files, stored associatively with TRUE for lookup
GLOBAL_LIST_EMPTY(icon_states_cache_lookup)

// DQ icon pipeline caches — see resolve_icon_dmi_path(), icon_metadata(), and
// invalidate_icon_cache() in code/_helpers/icons.dm. All four caches are keyed by
// the original source path; use invalidate_icon_cache(path) to clear them together.

/// Resolved on-disk paths for DMI files (maps source path -> icons/gen/ path when needed).
GLOBAL_LIST_EMPTY(dq_resolved_icon_path_cache)
/// Full rustg DMI metadata cache (maps source path -> metadata assoc list).
GLOBAL_LIST_EMPTY(dq_icon_metadata_cache)
