// Containment config (roadmap C10, doc/rewrite/containment.md §4.7).

/// Kill switch: off, can_be_latent() always refuses and the sweep is inert,
/// so behaviour matches pre-C10 always-real holders byte for byte.
/datum/config_entry/flag/latency_policy_enabled
	default = TRUE

/// Live-server safety net: materializing a collapsed atom compares its state
/// against the blob taken just before collapse and logs loudly on a
/// mismatch. Always on in UNIT_TESTS regardless of this flag.
/datum/config_entry/flag/latency_round_trip_audit
	default = FALSE
