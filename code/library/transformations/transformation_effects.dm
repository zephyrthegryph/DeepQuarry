// sets_off(): the stock effects a reagent step sets off (doc/rewrite/proposals/transformations.md section 6, stock parts for the common tail).
//
//   sets_off(kind = XFORM_FX_SMOKE, clears = TRUE, sfx = SFX_EFFECTS_SMOKE)
//   sets_off(kind = XFORM_FX_FOAM, variant = 0|1|2, tell = "The solution spews out foam!", clears = TRUE)
//   sets_off(kind = XFORM_FX_EXPLOSION, divisor = 10, skip_in_tests = TRUE)
//   sets_off(kind = XFORM_FX_EMP, divisors = list(24, 20, 18, 14), clears = TRUE)
//   sets_off(kind = XFORM_FX_WAVE, range = 5, line_of_sight = TRUE, statuses = list(list(3, STAT_WEAKENED, 15), list(5, STAT_STUNNED, 5)), flash = TRUE)
//   sets_off(kind = XFORM_FX_THERMAL, direction = THERMAL_COLD, joules = -10000000, slime_damage = list(100, 200))
//   sets_off(kind = XFORM_FX_SCATTER, range = 2, distance = 50)
//   sets_off(kind = XFORM_FX_SLICK, range = 5, freeze = TRUE)
//
// Each kind does what the old on_reaction() tail it replaces did, in the same order: the viewers' message, the effect's set_up and start, then the
// holder's clearing. `made` is what the step made (what the tail used to be told as created_volume). `clears` empties the holder unless it is a living
// thing, so a tiny amount of a fast reagent cannot be farmed; an explosion clears (for a non-living holder) before it starts, as it always did.
// A rule may list several sets_off() rows (a list); they run in order after the spawns() rows and before its then() tail.

/// A compiled sets_off() row.
/datum/xform_effect
	var/kind
	var/clears = FALSE
	var/tell
	var/sfx
	var/variant = 0
	var/divisor = 1
	var/list/divisors
	var/skip_in_tests = FALSE
	/// A fixed size for smoke or foam, in place of what the step made; null for the latter.
	var/amount
	/// XFORM_FX_AREA: the radius, the body effect path(s) and how long they last (null: until removed).
	var/range
	/// Percent chance the row goes at all (null: always); rolled before anything else.
	var/chance
	var/list/blast
	var/delay
	var/handler
	var/audit
	var/strength
	var/fire_sfx
	/// XFORM_FX_EMP: four fixed ranges (instead of divisors scaled by what was made).
	var/list/ranges
	var/direction
	var/pulses
	var/empties = FALSE
	var/list/gases
	var/scale_by_made = FALSE
	var/temperature
	var/list/hotspot
	var/line_of_sight = FALSE
	var/floors_only = FALSE
	var/consumes
	var/mood
	var/edit
	var/list/levels
	var/list/symptoms
	var/sfx_volume
	var/list/body_effects
	var/lasts
	/// XFORM_FX_WAVE: the mob type it reaches (default /mob/living); rows of list(max distance, STAT_X, amount), the first whose distance covers the mob
	/// applies (a mob past every row is left alone); flash eyes too (an eye-protected human is passed over); TREAT_X ids mended by mend_amount;
	/// list(per cycle, duration) of lingering poison; a line told to each mob reached; sparks at the subject.
	var/mob_type
	var/list/statuses
	var/flash = FALSE
	var/list/mends
	var/mend_amount
	var/list/poison
	var/tell_each
	var/sparks
	/// XFORM_FX_THERMAL: the joules added to the subject's air (negative: taken), and for the cold the damage a slime takes: list(player slime, other slime).
	var/joules
	var/list/slime_damage
	/// XFORM_FX_SCATTER: how far the mobs are thrown (a random turf within it).
	var/distance
	/// XFORM_FX_SLICK: the floors are frozen as well as wet.
	var/freeze = FALSE

/// The rows of a rule's `effects` argument (one sets_off() or a list of them), or null (reported) when one is wrong.
/proc/xform_effect_rows(type, origin, effects_argument)
	var/list/rows = list()
	for(var/datum/entry/part/effect/sets_off/E as anything in entry_flatten(islist(effects_argument) ? effects_argument : list(effects_argument)))
		if(!istype(E))
			declare_report("[origin]: [type]: effects = takes sets_off(...) rows")
			return null
		var/list/arguments = E.args
		var/kind = arguments["kind"]
		if(isnull(kind))
			// A kind passed positionally whose text equals another parameter name binds as that parameter (BYOND), leaving `kind` empty.
			for(var/name in arguments)
				if(name == XFORM_FX_SMOKE || name == XFORM_FX_FOAM || name == XFORM_FX_EXPLOSION || name == XFORM_FX_EMP || name == XFORM_FX_AREA || name == XFORM_FX_BLAST || name == XFORM_FX_LIGHTNING || name == XFORM_FX_RADIATION || name == XFORM_FX_FROST || name == XFORM_FX_LATER || name == XFORM_FX_WAVE || name == XFORM_FX_THERMAL || name == XFORM_FX_SCATTER || name == XFORM_FX_SLICK)
					declare_report("[origin]: [type]: sets_off() arrived with no kind while it has an argument named \"[name]\", which is also a kind: the kind was passed positionally and bound as that argument. Write sets_off(kind = ...)")
					return null
		if(kind != XFORM_FX_SMOKE && kind != XFORM_FX_FOAM && kind != XFORM_FX_EXPLOSION && kind != XFORM_FX_EMP && kind != XFORM_FX_AREA && kind != XFORM_FX_BLAST && kind != XFORM_FX_FROST && kind != XFORM_FX_LATER && kind != XFORM_FX_LIGHTNING && kind != XFORM_FX_RADIATION && kind != XFORM_FX_GRAVITY && kind != XFORM_FX_BURN && kind != XFORM_FX_MOOD && kind != XFORM_FX_CONTAGION && kind != XFORM_FX_WAVE && kind != XFORM_FX_THERMAL && kind != XFORM_FX_SCATTER && kind != XFORM_FX_SLICK)
			declare_report("[origin]: [type]: sets_off([kind]) is not XFORM_FX_SMOKE, XFORM_FX_FOAM, XFORM_FX_EXPLOSION, XFORM_FX_EMP, XFORM_FX_AREA, XFORM_FX_BLAST, XFORM_FX_FROST, XFORM_FX_LATER, XFORM_FX_LIGHTNING, XFORM_FX_RADIATION, XFORM_FX_GRAVITY, XFORM_FX_BURN, XFORM_FX_MOOD, XFORM_FX_CONTAGION, XFORM_FX_WAVE, XFORM_FX_THERMAL, XFORM_FX_SCATTER or XFORM_FX_SLICK")
			return null
		var/datum/xform_effect/row = new
		row.kind = kind
		row.clears = !!arguments["clears"]
		row.tell = arguments["tell"]
		row.sfx = arguments["sfx"]
		row.variant = arguments["variant"] || 0
		row.divisor = arguments["divisor"] || 1
		row.divisors = arguments["divisors"]
		row.skip_in_tests = !!arguments["skip_in_tests"]
		row.amount = arguments["amount"]
		row.range = arguments["range"]
		row.chance = arguments["chance"]
		row.blast = arguments["blast"]
		row.delay = arguments["delay"]
		row.handler = arguments["handler"]
		row.audit = arguments["audit"]
		row.strength = arguments["strength"]
		row.fire_sfx = arguments["fire_sfx"]
		row.ranges = arguments["ranges"]
		row.direction = arguments["direction"]
		row.pulses = arguments["pulses"]
		row.empties = !!arguments["empties"]
		row.gases = arguments["gases"]
		row.scale_by_made = !!arguments["scale_by_made"]
		row.temperature = arguments["temperature"]
		row.hotspot = arguments["hotspot"]
		row.line_of_sight = !!arguments["line_of_sight"]
		row.floors_only = !!arguments["floors_only"]
		row.consumes = arguments["consumes"]
		row.mood = arguments["mood"]
		row.edit = arguments["edit"]
		row.levels = arguments["levels"]
		row.symptoms = arguments["symptoms"]
		row.sfx_volume = arguments["sfx_volume"]
		var/body_effect = arguments["body_effect"]
		row.body_effects = islist(body_effect) ? body_effect : (body_effect ? list(body_effect) : null)
		row.lasts = arguments["lasts"]
		row.mob_type = arguments["mob_type"] || /mob/living
		row.statuses = arguments["statuses"]
		row.flash = !!arguments["flash"]
		row.mends = arguments["mends"]
		row.mend_amount = arguments["mend_amount"]
		row.poison = arguments["poison"]
		row.tell_each = arguments["tell_each"]
		row.sparks = arguments["sparks"]
		row.joules = arguments["joules"]
		row.slime_damage = arguments["slime_damage"]
		row.distance = arguments["distance"]
		row.freeze = !!arguments["freeze"]
		if(kind == XFORM_FX_WAVE && (!isnum(row.range) || !(length(row.statuses) || length(row.mends) || length(row.poison) || row.tell_each)))
			declare_report("[origin]: [type]: sets_off(kind = XFORM_FX_WAVE) takes range = n and at least one of statuses, mends, poison or tell_each")
			return null
		if(kind == XFORM_FX_WAVE && length(row.mends) && !isnum(row.mend_amount))
			declare_report("[origin]: [type]: sets_off(kind = XFORM_FX_WAVE, mends = ...) takes mend_amount = n")
			return null
		if(kind == XFORM_FX_WAVE && length(row.poison) && length(row.poison) != 2)
			declare_report("[origin]: [type]: sets_off(kind = XFORM_FX_WAVE) takes poison = list(per_cycle, duration)")
			return null
		if(kind == XFORM_FX_WAVE)
			for(var/band in row.statuses)
				if(!islist(band) || length(band) != 3)
					declare_report("[origin]: [type]: sets_off(kind = XFORM_FX_WAVE) takes statuses = list(list(max distance, STAT_X, amount), ...)")
					return null
		if(kind == XFORM_FX_THERMAL && ((row.direction != THERMAL_HEAT && row.direction != THERMAL_COLD) || !isnum(row.joules) || (row.direction == THERMAL_HEAT && !isnum(row.temperature))))
			declare_report("[origin]: [type]: sets_off(kind = XFORM_FX_THERMAL) takes direction = THERMAL_HEAT (with temperature = the kelvin a body is pushed toward) or THERMAL_COLD, and joules = n")
			return null
		if(kind == XFORM_FX_SCATTER && (!isnum(row.range) || !isnum(row.distance)))
			declare_report("[origin]: [type]: sets_off(kind = XFORM_FX_SCATTER) takes range = n and distance = n")
			return null
		if(kind == XFORM_FX_SLICK && !isnum(row.range))
			declare_report("[origin]: [type]: sets_off(kind = XFORM_FX_SLICK) takes range = n")
			return null
		if(kind == XFORM_FX_EMP && !(islist(row.divisors) && length(row.divisors) == 4) && !(islist(row.ranges) && length(row.ranges) == 4))
			declare_report("[origin]: [type]: sets_off(kind = XFORM_FX_EMP) takes divisors = list(a, b, c, d) or ranges = list(a, b, c, d)")
			return null
		if(kind == XFORM_FX_RADIATION && (!isnum(row.range) || !isnum(row.strength)))
			declare_report("[origin]: [type]: sets_off(kind = XFORM_FX_RADIATION) takes range = n and strength = n")
			return null
		if(kind == XFORM_FX_AREA && (!isnum(row.range) || !length(row.body_effects)))
			declare_report("[origin]: [type]: sets_off(kind = XFORM_FX_AREA) takes range = n and body_effect = a path or a list of paths")
			return null
		if(kind == XFORM_FX_BLAST && (!islist(row.blast) || length(row.blast) < 3 || length(row.blast) > 4))
			declare_report("[origin]: [type]: sets_off(kind = XFORM_FX_BLAST) takes blast = list(devastation, heavy, light) or list(devastation, heavy, light, flash)")
			return null
		if(kind == XFORM_FX_LATER && (!isnum(row.delay) || !row.handler))
			declare_report("[origin]: [type]: sets_off(kind = XFORM_FX_LATER) takes delay = n and handler = GLOBAL_PROC_REF(x)")
			return null
		if(kind == XFORM_FX_GRAVITY && ((row.direction != GRAVITY_PULL && row.direction != GRAVITY_PUSH) || !isnum(row.range)))
			declare_report("[origin]: [type]: sets_off(kind = XFORM_FX_GRAVITY) takes direction = GRAVITY_PULL or GRAVITY_PUSH and range = n")
			return null
		if(kind == XFORM_FX_BURN && (!islist(row.gases) || !length(row.gases) || !isnum(row.temperature) || !isnum(row.range)))
			declare_report("[origin]: [type]: sets_off(kind = XFORM_FX_BURN) takes gases = list(gas = amount), temperature = n and range = n")
			return null
		if(kind == XFORM_FX_MOOD && row.mood != MOOD_CALM && row.mood != MOOD_ENRAGE)
			declare_report("[origin]: [type]: sets_off(kind = XFORM_FX_MOOD) takes mood = MOOD_CALM or MOOD_ENRAGE")
			return null
		if(kind == XFORM_FX_CONTAGION && row.edit != CONTAGION_EVOLVE && row.edit != CONTAGION_PICKY && row.edit != CONTAGION_DEVOLVE && row.edit != CONTAGION_NEUTER && row.edit != CONTAGION_FALTER)
			declare_report("[origin]: [type]: sets_off(kind = XFORM_FX_CONTAGION) takes edit = CONTAGION_EVOLVE, _PICKY, _DEVOLVE, _NEUTER or _FALTER")
			return null
		if(kind == XFORM_FX_CONTAGION && row.edit == CONTAGION_EVOLVE && !(islist(row.levels) && length(row.levels) == 2))
			declare_report("[origin]: [type]: sets_off(kind = XFORM_FX_CONTAGION, edit = CONTAGION_EVOLVE) takes levels = list(min, max)")
			return null
		rows += row
	if(!length(rows))
		declare_report("[origin]: [type]: effects = names no sets_off() row")
		return null
	return rows

/// Runs every sets_off() row of `X` for a step of `holder` that made `made`. Called by xform_effects().
/proc/xform_run_effects(datum/xform/X, datum/reagents/holder, made, datum/owner)
	for(var/datum/xform_effect/row as anything in X.effect_rows)
#ifdef UNIT_TESTS
		if(row.skip_in_tests)
			continue
#endif
		var/atom/subject = holder.my_atom
		if(!subject || QDELETED(subject))
			log_world("XFORM: [X.rule_type] sets off [row.kind] nothing: its subject is gone")
			return
		if(GLOB.xform_trace)
			log_world("XFORM: [X.rule_type] sets off [row.kind] for [made] made, in [subject] ([subject.type])")
		if(!isnull(row.chance) && !prob(row.chance))
			continue
		var/turf/location = get_turf(subject)
		switch(row.kind)
			if(XFORM_FX_SMOKE)
				var/datum/effect/effect/system/smoke_spread/chem/S = new /datum/effect/effect/system/smoke_spread/chem
				S.attach(location)
				S.set_up(holder, isnull(row.amount) ? made : row.amount, 0, location)
				if(row.sfx)
					play_sfx(location, row.sfx)
				S.start()
				if(row.clears && !isliving(subject))
					holder.clear_reagents()
			if(XFORM_FX_FOAM)
				if(row.tell)
					for(var/mob/M in viewers(5, location))
						to_chat(M, span_warning(row.tell))
				var/datum/effect/effect/system/foam_spread/s = new()
				s.set_up(isnull(row.amount) ? made : row.amount, location, holder, row.variant)
				s.start()
				if(row.clears && !isliving(subject))
					holder.clear_reagents()
			if(XFORM_FX_EXPLOSION)
				var/datum/effect/effect/system/reagents_explosion/e = new()
				e.set_up(round(made / row.divisor, 1), subject, 0, 0)
				if(isliving(subject))
					e.amount *= 0.5
					var/mob/living/L = subject
					if(L.stat != DEAD)
						e.amount *= 0.5
				else
					holder.clear_reagents() // no powergaming by creating a tiny amount of this
				e.start()
			if(XFORM_FX_BLAST)
				var/list/b = list()
				for(var/part in row.blast)
					b += islist(part) ? rand(part[1], part[2]) : part
				if(row.sfx)
					xform_play_sfx(subject, row.sfx, row.sfx_volume)
				explosion(location, b[1], b[2], b[3], length(b) >= 4 ? b[4] : null)
			if(XFORM_FX_FROST)
				var/datum/effect/effect/system/smoke_spread/frost/F = new (subject)
				F.set_up(row.amount, 0, location)
				F.start()
			if(XFORM_FX_LATER)
				if(row.audit)
					log_and_message_admins("[row.audit] has been activated in [get_area(subject)].  Last fingerprints: [subject.forensic_data?.get_lastprint()]", null)
				if(row.tell)
					subject.visible_message(span_danger("\The [subject] begins to vibrate violently!"))
				if(row.sfx)
					xform_play_sfx(subject, row.sfx, row.sfx_volume)
				after(subject, row.delay, row.handler, with = list(subject))
			if(XFORM_FX_AREA)
				for(var/mob/living/L in range(row.range, subject))
					for(var/effect_path in row.body_effects)
						L.apply_body_effect(effect_path, row.lasts, subject) // the extract is the origin: the old tails passed the rule, which a body effect refuses (an origin is an atom)
			if(XFORM_FX_EMP)
				if(row.ranges)
					xform_effect_timed(subject, row)
				else
					var/list/d = row.divisors
					empulse(location, round(made / d[1]), round(made / d[2]), round(made / d[3]), round(made / d[4]), 1)
					if(row.clears && !isliving(subject))
						holder.clear_reagents()
			if(XFORM_FX_LIGHTNING, XFORM_FX_RADIATION, XFORM_FX_GRAVITY, XFORM_FX_BURN)
				xform_effect_timed(subject, row, made, holder)
			if(XFORM_FX_MOOD)
				xform_effect_mood(subject, row)
			if(XFORM_FX_CONTAGION)
				xform_effect_contagion(holder, row)
			if(XFORM_FX_WAVE)
				xform_effect_wave(subject, row)
			if(XFORM_FX_THERMAL)
				xform_effect_thermal(subject, row)
			if(XFORM_FX_SCATTER)
				xform_effect_scatter(subject, row)
			if(XFORM_FX_SLICK)
				xform_effect_slick(subject, row)

/// The kinds that need no vessel (a fixed EMP, a lightning strike, a radiation pulse): the audit line, message and sound now, then the effect now or `delay` later.
/proc/xform_effect_timed(atom/subject, datum/xform_effect/row, made = 0, datum/reagents/holder = null)
	if(row.audit)
		log_and_message_admins("[row.audit] has been activated in [get_area(subject)].  Last fingerprints: [subject.forensic_data?.get_lastprint()]", null)
	if(row.tell)
		subject.visible_message(span_danger("\The [subject] begins to vibrate violently!"))
	if(row.sfx)
		xform_play_sfx(subject, row.sfx, row.sfx_volume)
	if(row.delay)
		after(subject, row.delay, GLOBAL_PROC_REF(xform_effect_fire), with = list(subject, row, made))
	else
		xform_effect_fire(subject, row, made, holder)

/// Does the effect of a timed row on `subject`: the EMP, the strike or the pulse.
/proc/xform_effect_fire(atom/subject, datum/xform_effect/row, made = 0, datum/reagents/holder = null)
	if(!subject || QDELETED(subject))
		return
	var/turf/location = get_turf(subject)
	switch(row.kind)
		if(XFORM_FX_EMP)
			var/list/r = row.ranges
			empulse(location, r[1], r[2], r[3], r[4])
		if(XFORM_FX_LIGHTNING)
			if(istype(location, /turf))
				lightning_strike(location)
		if(XFORM_FX_RADIATION)
			radiation_pulse(subject, max_range = row.range, threshold = RAD_MEDIUM_INSULATION, chance = 100, strength = row.strength)
		if(XFORM_FX_GRAVITY)
			if(row.direction == GRAVITY_PULL)
#ifndef UNIT_TESTS
				// The pull keeps its timers and its record after it ends, which the end-of-run ownership audit reports as a leak: a test world does not start it.
				var/datum/effect/effect/system/grav_pull/pull = new /datum/effect/effect/system/grav_pull
				pull.set_up(row.range, row.pulses, location)
				pull.start()
#endif
			else
				for(var/thing in orange(row.range, location))
					var/atom/movable/AM = thing
					if(!ismovable(thing) || istype(thing, /obj/effect/overlay))
						continue
					if(isobj(thing))
						var/obj/O = thing
						if(O.anchored)
							continue
					AM.throw_at(get_edge_target_turf(AM, get_dir(location, AM)), 3, 1, subject)
			if(row.empties)
				holder?.clear_reagents()
		if(XFORM_FX_BURN)
			var/list/targets = list()
			if(row.line_of_sight)
				for(var/turf/simulated/T in view(row.range, location))
					targets += T
			else
				for(var/turf/simulated/T in range(row.range, location))
					targets += T
			for(var/turf/simulated/target_turf as anything in targets)
				if(row.floors_only && !istype(target_turf, /turf/simulated/floor))
					continue
				for(var/gas in row.gases)
					target_turf.assume_gas(gas, row.gases[gas] * (row.scale_by_made ? made : 1), row.temperature)
				if(row.hotspot)
					target_turf.hotspot_expose(row.hotspot[1], row.hotspot[2])
			if(row.consumes)
				holder?.del_reagent(row.consumes)
	if(row.fire_sfx)
		xform_play_sfx(subject, row.fire_sfx, row.sfx_volume)

/// XFORM_FX_MOOD: calms or enrages the slimes the subject can see, and slime-bodied people. A player slime always keeps free will.
/proc/xform_effect_mood(atom/subject, datum/xform_effect/row)
	var/turf/location = get_turf(subject)
	var/calm = row.mood == MOOD_CALM
	for(var/mob/living/simple_mob/slime/S in view(location))
		if(S.stat)
			continue
		if(istype(S, /mob/living/simple_mob/slime/xenobio))
			var/mob/living/simple_mob/slime/xenobio/X = S
			if(X.harmless)
				continue
			if(!X.client)
				if(calm)
					X.relax()
				else
					X.enrage()
		if(calm)
			S.remove_body_effect(/datum/body_effect/berserk)
		else
			S.apply_body_effect(/datum/body_effect/berserk, 30 SECONDS)
		if(S.client)
			to_chat(S, span_warning(calm ? "An intense wave of relaxing calm is felt from inside, but you remain in control of yourself." : "An intense wave of rage is felt from inside, but you remain in control of yourself."))
	for(var/mob/living/carbon/human/H in view(location))
		if(H.species?.is_slime_bodied)
			if(calm)
				H.remove_body_effect(/datum/body_effect/berserk)
			else
				H.apply_body_effect(/datum/body_effect/berserk, 30 SECONDS)
			to_chat(H, span_warning(calm ? "An intense wave of relaxing calm is felt from inside, but you remain in control of yourself." : "An intense wave of rage is felt from inside, but you remain in control of yourself."))
	if(row.audit)
		log_and_message_admins("[row.audit] has been activated in [get_area(subject)].  Last fingerprints: [subject.forensic_data?.get_lastprint()]", null)
	if(row.sfx)
		xform_play_sfx(subject, row.sfx, row.sfx_volume)

/// XFORM_FX_CONTAGION: edits the engineered contagion carried in the blood of `holder`, if there is any.
/proc/xform_effect_contagion(datum/reagents/holder, datum/xform_effect/row)
	var/datum/reagent/blood/B = locate_in_list(holder.reagent_list, /datum/reagent/blood)
	if(!B || !B.data)
		return
	var/datum/affliction/contagion/engineered/D = locate_in_list(B.data["viruses"], /datum/affliction/contagion/engineered)
	if(!D)
		return
	switch(row.edit)
		if(CONTAGION_EVOLVE)
			D.Evolve(row.levels[1], row.levels[2])
		if(CONTAGION_PICKY)
			D.PickyEvolve(row.symptoms)
		if(CONTAGION_DEVOLVE)
			D.Devolve()
		if(CONTAGION_NEUTER)
			D.Neuter()
		if(CONTAGION_FALTER)
			D.Falter()

/// Plays a sound at `volume_mult` times its usual volume (null: the usual volume).
/proc/xform_play_sfx(atom/subject, sfx, volume_mult = null)
	play_sfx(subject, sfx, isnull(volume_mult) ? 1 : volume_mult)

/// The audit line every area kind writes, when its row names one.
/proc/xform_effect_audit(atom/subject, datum/xform_effect/row)
	if(row.audit)
		log_and_message_admins("[row.audit] has been activated in [get_area(subject)].  Last fingerprints: [subject.forensic_data?.get_lastprint()]", null)

/// XFORM_FX_WAVE: something done to every mob of `mob_type` around the subject (in range, or in view with line_of_sight), scaled by its distance through
/// the status rows: flash powder's flash and stun, a heal pulse, a cloud of lingering poison.
/proc/xform_effect_wave(atom/subject, datum/xform_effect/row)
	var/turf/location = get_turf(subject)
	if(!location)
		return
	xform_effect_audit(subject, row)
	if(row.sparks)
		fx_sparks(location, row.sparks)
	var/list/reached = row.line_of_sight ? viewers(row.range, location) : range(row.range, location)
	var/hits = 0
	for(var/mob/living/L in reached)
		if(!istype(L, row.mob_type))
			continue
		var/list/band = null
		if(length(row.statuses))
			var/dist = get_dist(L, location)
			for(var/list/candidate as anything in row.statuses)
				if(dist <= candidate[1])
					band = candidate
					break
			if(!band && !length(row.mends) && !length(row.poison) && !row.tell_each)
				continue // past every row, and nothing else to do
		if(row.flash && band)
			if(ishuman(L))
				var/mob/living/carbon/human/H = L
				if(istype(H.get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/sunglasses))
					continue
			L.flash_eyes()
		if(band)
			L.status_at_least(band[2], band[3])
		if(row.tell_each)
			to_chat(L, span_notice(row.tell_each))
		for(var/treatment in row.mends)
			L.mend(treatment, row.mend_amount)
		if(length(row.poison))
			L.lingering_poison(row.poison[1], row.poison[2], subject)
		hits++
	if(GLOB.xform_trace)
		log_world("XFORM: wave from [subject] reached [hits] mob(s)")
	if(row.sfx)
		xform_play_sfx(subject, row.sfx, row.sfx_volume)

/// XFORM_FX_THERMAL: a heat wave or a cold snap. Each human in view on a simulated floor is pushed toward the extreme by what its protection lets
/// through, a slime takes the cold, and the subject's air takes `joules`.
/proc/xform_effect_thermal(atom/subject, datum/xform_effect/row)
	var/turf/simulated/T = get_turf(subject)
	if(!istype(T))
		return
	xform_effect_audit(subject, row)
	var/cold = row.direction == THERMAL_COLD
	for(var/mob/living/L in view(T))
		if(!istype(get_turf(L), /turf/simulated))
			continue
		if(cold && length(row.slime_damage) && istype(L, /mob/living/simple_mob/slime))
			var/mob/living/simple_mob/slime/S = L
			if(S.cold_resist >= 1)
				to_chat(S, span_warning("A chill is felt around you, however it cannot harm you."))
				continue
			if(S.client)
				to_chat(S, span_danger("You feel your body crystalize as an intense chill overwhelms you!"))
				S.inflict_cold_damage(row.slime_damage[1])
			else
				S.inflict_cold_damage(row.slime_damage[2])
			continue
		if(!ishuman(L))
			continue
		var/mob/living/carbon/human/H = L
		var/protection = cold ? H.get_cold_protection() : H.get_heat_protection()
		if(protection < 1)
			var/exposure = 1 - protection
			var/now = H.body_temperature()
			if(cold)
				H.set_bodytemperature(between(50, now - ((now - 50) * exposure), now))
			else if(row.temperature > now)
				H.set_bodytemperature(now + (row.temperature - now) * exposure)
		if(protection < 0.7)
			to_chat(H, span_danger(cold ? "A chilling wave of cold overwhelms you!" : "A scalding wave of heat overwhelms you!"))
		else
			to_chat(H, span_warning(cold ? "A chilling wave of cold passes by you, as your armor protects you from it." : "A scalding wave of heat passes by you, as your armor protects you from it."))
	var/datum/gas_mixture/env = T.return_air()
	if(env)
		heat_add(env, row.joules, HEAT_SOURCE_REACTION)
	if(row.sfx)
		xform_play_sfx(T, row.sfx, row.sfx_volume)

/// XFORM_FX_SCATTER: every mob in range of the subject is unbuckled and thrown to a random turf within `distance`, with sparks where it was and where it lands.
/proc/xform_effect_scatter(atom/subject, datum/xform_effect/row)
	var/turf/location = get_turf(subject)
	if(!location)
		return
	xform_effect_audit(subject, row)
	for(var/mob/living/M in range(row.range, location))
		var/atom/movable/seat = M.buckled_to()
		if(seat)
			seat.unbuckle_mob()
		fx_sparks(get_turf(M), 3, FALSE)
		M.forceMove(pick(trange(row.distance, location)))
		fx_sparks(M.loc, 3, FALSE)

/// XFORM_FX_SLICK: every simulated turf in range of the subject is made wet (and frozen with `freeze`).
/proc/xform_effect_slick(atom/subject, datum/xform_effect/row)
	var/turf/location = get_turf(subject)
	if(!location)
		return
	xform_effect_audit(subject, row)
	for(var/turf/simulated/T in trange(row.range, location))
		T.set_wet(TURFSLIP_WET)
		if(row.freeze)
			T.freeze_floor()
