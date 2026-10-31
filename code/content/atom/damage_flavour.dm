// Generated damage flavour text (damage.md §6). A band is derived from the
// atom's integrity ratio (no rule, no stored state); examine() shows its line. This replaces the hand-written per-type lines.

/// The examine line for `band` (DAMAGE_BAND_*), or null for none.
/atom/proc/damage_flavour_text(band)
	var/they = gender == PLURAL ? "They" : "It"
	var/have = gender == PLURAL ? "have" : "has"
	var/look = gender == PLURAL ? "look" : "looks"
	switch(band)
		if(DAMAGE_BAND_LIGHT)
			return span_notice("[they] [have] a few [shielding_of(src).damage_wear].")
		if(DAMAGE_BAND_MODERATE)
			return span_warning("[they] [look] seriously damaged.")
		if(DAMAGE_BAND_HEAVY)
			return span_danger("[they] [look] about to fall apart!")
	return null

/// The line onlookers see when this atom drops into `band`.
/atom/proc/damage_band_announcement(band)
	switch(band)
		if(DAMAGE_BAND_LIGHT)
			return "\The [src] starts to show [shielding_of(src).damage_wear]!"
		if(DAMAGE_BAND_MODERATE)
			return "\The [src] looks seriously damaged!"
		if(DAMAGE_BAND_HEAVY)
			return "\The [src] looks like it's about to break!"
	return null

/// Announces a drop into a worse damage band between two integrity values.
/// Called from on_update_integrity() for types that set announce_damage_bands.
/atom/proc/announce_damage_band(old_value, new_value)
	if(new_value <= 0 || new_value >= old_value || max_integrity <= 0)
		return
	var/new_band = dq_damage_band_at(new_value / max_integrity)
	if(new_band > dq_damage_band_at(old_value / max_integrity))
		visible_message(damage_band_announcement(new_band))

/// The damage band (DAMAGE_BAND_*) for an integrity ratio: below 3/4 light, below 1/2 moderate, below 1/4 heavy.
/proc/dq_damage_band_at(ratio)
	var/static/list/levels = list(0.75, 0.5, 0.25)
	. = DAMAGE_BAND_NONE
	for(var/band in 1 to length(levels))
		if(ratio < levels[band])
			. = band

/// The damage band `A` is in, derived from its integrity: nothing is stored or bound.
/proc/dq_damage_band_for(atom/A)
	if(!A.uses_integrity || A.max_integrity <= 0)
		return DAMAGE_BAND_NONE
	return dq_damage_band_at(A.get_integrity() / A.max_integrity)

/// Whether examine shows a damage band for objects of `path`: the types that declare damage flavour.
/proc/dq_damage_flavour_declared(path)
	return CACHED(damage_flavour_declared, path)

DECLARE_SHARED_CACHE(damage_flavour_declared, GLOBAL_PROC_REF(build_damage_flavour_declared), SC_NEVER)

/proc/build_damage_flavour_declared(path)
	var/atom/A = path
	if(!initial(A.uses_integrity) || initial(A.max_integrity) <= 0)
		return FALSE
	var/static/list/roots = list(
		/obj/structure/window,
		/obj/structure/railing,
		/obj/structure/low_wall,
		/obj/structure/table,
		/obj/machinery/door,
		/obj/structure/expedition_demo_target,
	)
	for(var/root in roots)
		if(ispath(path, root))
			return TRUE
	return FALSE
