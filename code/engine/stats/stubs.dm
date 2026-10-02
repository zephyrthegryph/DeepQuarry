// E0 stubs for E3's public surface (doc/rewrite/final_api.html, section 5; section 19 "E3, stats"): holds and the reactive system
// accessors. Signatures are the final ones; a body reports what it needs through ENGINE_STUB and returns null until E3 lands.
// No runtime behaviour here. The status_* family is live on master and unchanged.

/// A runtime contribution to a stat, kept by `source`; `lasts` is a duration on `clock`.
/proc/hold(datum/E, stat, value, source, lasts, priority = PRIORITY_DEFAULT, clock, reason, bound = FALSE)
	ENGINE_STUB(ENGINE_E3, "stat layer: hold")
	return null

/// A hold that ends at an exact deadline on `clock`.
/proc/hold_until(datum/E, stat, value, source, until, priority = PRIORITY_DEFAULT, clock, reason, bound = FALSE)
	ENGINE_STUB(ENGINE_E3, "stat layer: hold_until")
	return null

/// Replaces the composed value of a stat until released.
/proc/hold_override(datum/E, stat, value, source, priority = PRIORITY_ADMIN)
	ENGINE_STUB(ENGINE_E3, "stat layer: hold_override")
	return null

/// Releases `source`'s hold on a stat (SRC_ALL drops every source's).
/proc/release(datum/E, stat, source)
	ENGINE_STUB(ENGINE_E3, "stat layer: release")
	return null

/// Releases everything one source holds on `E`.
/proc/release_all(datum/E, source)
	ENGINE_STUB(ENGINE_E3, "stat layer: release_all")
	return null

/// The sources holding a stat: a fresh list.
/proc/held_by(datum/E, stat)
	ENGINE_STUB(ENGINE_E3, "stat layer: held_by")
	return null

/// TRUE if `source` holds the stat.
/proc/held_by_source(datum/E, stat, source)
	ENGINE_STUB(ENGINE_E3, "stat layer: held_by_source")
	return FALSE

/// Time left on a timed hold, in deciseconds of the hold's clock.
/proc/hold_left(datum/E, stat, source)
	ENGINE_STUB(ENGINE_E3, "stat layer: hold_left")
	return null
