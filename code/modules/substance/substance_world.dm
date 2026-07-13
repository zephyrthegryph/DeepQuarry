// In-world consequences of substances — the shared family -> world effect map.
//
// Two callers use this:
//   * a hazard from an overpushed combination (substance_hazard_detonate), and
//   * a substance built into a carried form firing on its trigger (Phase 3,
//     effects-as-material-property: blade strike, charge throw, etc.).
// Both go through substance_apply_effect() so a substance behaves the SAME in the
// lab and in the field, downsides included — the whole point of §9. Magnitude
// scales the punch; volatility is the downside knob: a volatile effect spreads
// wider and can catch the wielder.

// Fire `family`'s effect on turf T, scaled by magnitude (0..100). High volatility
// widens the area and risks blowback. `cause` is the atom responsible (for logs).
/proc/substance_apply_effect(turf/T, family, magnitude, volatility = 0, atom/cause = null)
	if(!isturf(T))
		return
	var/mag = clamp(magnitude, 0, 100)
	var/power = mag / 100
	// Volatility widens the blast and makes it less controllable.
	var/radius = clamp(round(1 + power * 2 + (volatility >= SUB_HAZARD_V_THRESHOLD ? 1 : 0)), 1, 5)

	// Sparks always mark a firing.
	var/datum/effect/effect/system/spark_spread/s = new
	s.set_up(round(1 + power * 4), 1, T)
	s.start()

	switch(family)
		if(SUBFAM_DISCHARGE)
			empulse(T, round(power * 2), round(power * 4))
			_substance_damage_mobs(T, radius, round(10 + mag * 0.4), BURN)
		if(SUBFAM_RADIANT)
			empulse(T, round(power * 1), round(power * 3))
			_substance_damage_mobs(T, radius, round(8 + mag * 0.3), BURN)
		if(SUBFAM_THERMAL)
			var/datum/gas_mixture/env = T.return_air()
			if(env)
				env.set_temperature(env.return_temperature() + mag * 20)
			T.hotspot_expose(mag * 20, 200)
			_substance_damage_mobs(T, radius, round(5 + mag * 0.35), BURN)
		if(SUBFAM_CORROSIVE)
			_substance_damage_mobs(T, radius, round(6 + mag * 0.45), BURN)
			// Damaging an obj can destroy it; if it is itself a substance material,
			// that fires substance_on_destruction -> substance_apply_effect again.
			// Defer off this call stack so a room of substance structures can't
			// recurse synchronously through one call (matches the infusion idiom).
			INVOKE_ASYNC(GLOBAL_PROC_REF(_substance_corrode_objs), T, radius, round(mag * 0.5))
		if(SUBFAM_FORCE)
			_substance_throw_movables(T, radius, round(1 + power * 4))
		if(SUBFAM_VOID)
			_substance_throw_movables(T, radius, round(1 + power * 3))
			_substance_damage_mobs(T, radius, round(4 + mag * 0.2), BURN)
		if(SUBFAM_SPORE)
			_substance_damage_mobs(T, radius, round(4 + mag * 0.4), TOX)
		if(SUBFAM_FIELD)
			// A barrier pulse: shoves everything one step out and resists for a moment.
			_substance_throw_movables(T, radius, 1)

	// High-magnitude eruptions throw a real (small) blast on top. Deferred: the
	// blast can destroy substance-material objs (-> re-entrant substance_apply_effect),
	// so keep it off the current call stack.
	if(mag >= SUB_HAZARD_M_THRESHOLD)
		INVOKE_ASYNC(GLOBAL_PROC_REF(explosion), T, -1, round(power * 1), round(2 + power * 3))

// Corrode every integrity-backed obj in range. Runs deferred (see caller): a
// destroyed substance-material obj re-enters substance_apply_effect, so this must
// not run inside the firing call stack.
/proc/_substance_corrode_objs(turf/T, radius, amount)
	if(!isturf(T) || amount <= 0)
		return
	for(var/obj/O in range(radius, T))
		if(O.uses_integrity)
			O.take_damage(amount, BRUTE)

// Damage living mobs in range by a flat amount of a damage type.
/proc/_substance_damage_mobs(turf/T, radius, amount, damtype)
	if(amount <= 0)
		return
	for(var/mob/living/L in range(radius, T))
		L.apply_damage(amount, damtype)

// Throw movables away from the centre, strength scaling the distance.
/proc/_substance_throw_movables(turf/T, radius, strength)
	for(var/atom/movable/AM in range(radius, T))
		if(AM.anchored)
			continue
		var/turf/edge = get_edge_target_turf(AM, get_dir(T, AM) || pick(GLOB.alldirs))
		AM.throw_at(edge, strength, 1)

// ---- Hazard wrapper --------------------------------------------------------
// A hazard is just a high-volatility application themed to the dominant family.
/proc/substance_hazard_detonate(turf/T, datum/substance_hazard/H)
	if(!T || !H)
		return
	T.visible_message(span_danger("The reaction erupts into [H.desc]!"))
	substance_apply_effect(T, H.family, H.severity, 100)
