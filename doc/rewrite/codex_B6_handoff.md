# B6 remaining system boundaries

system_boundary146→123:22 private-state rows (46 source-audited accesses) and one holomaps row (nine renderer methods) removed. The macro-scoped holomap renderer moves unchanged to its owner folder at the original manifest position. Owner APIs cover shuttles, media, persistence, catalogs, flight/radiation, events, DB concurrency and administrative controls. Additional unbaselined optional/private callers converted without aliases or new shared state. Mutable painting token identity, duplicate entries and nested initialization blocking preserve their original semantics.

Added six focused owner-boundary tests in dq_misc_system_boundary_tests.dm, including actual persistence validation/aging. No residual external private references found in source audit. Final analyzer/gate verification pending. Protected declarations/setters and tracing unchanged. No push or merge.
