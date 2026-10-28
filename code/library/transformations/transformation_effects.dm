// sets_off(): the stock effects a reagent step sets off (doc/rewrite/proposals/transformations.md section 6, stock parts for the common tail).
//
//   sets_off(XFORM_FX_SMOKE, clears = TRUE, sfx = SFX_EFFECTS_SMOKE)
//   sets_off(XFORM_FX_FOAM, variant = 0|1|2, tell = "The solution spews out foam!", clears = TRUE)
//   sets_off(XFORM_FX_EXPLOSION, divisor = 10, skip_in_tests = TRUE)
//   sets_off(XFORM_FX_EMP, divisors = list(24, 20, 18, 14), clears = TRUE)
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
	var/list/body_effects
	var/lasts

/// The rows of a rule's `effects` argument (one sets_off() or a list of them), or null (reported) when one is wrong.
/proc/xform_effect_rows(type, origin, effects_argument)
	var/list/rows = list()
	for(var/datum/entry/part/effect/sets_off/E as anything in entry_flatten(islist(effects_argument) ? effects_argument : list(effects_argument)))
		if(!istype(E))
			declare_report("[origin]: [type]: effects = takes sets_off(...) rows")
			return null
		var/list/arguments = E.args
		var/kind = arguments["kind"]
		if(kind != XFORM_FX_SMOKE && kind != XFORM_FX_FOAM && kind != XFORM_FX_EXPLOSION && kind != XFORM_FX_EMP && kind != XFORM_FX_AREA && kind != XFORM_FX_BLAST && kind != XFORM_FX_FROST && kind != XFORM_FX_LATER)
			declare_report("[origin]: [type]: sets_off([kind]) is not XFORM_FX_SMOKE, XFORM_FX_FOAM, XFORM_FX_EXPLOSION, XFORM_FX_EMP, XFORM_FX_AREA, XFORM_FX_BLAST, XFORM_FX_FROST or XFORM_FX_LATER")
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
		var/body_effect = arguments["body_effect"]
		row.body_effects = islist(body_effect) ? body_effect : (body_effect ? list(body_effect) : null)
		row.lasts = arguments["lasts"]
		if(kind == XFORM_FX_EMP && (!islist(row.divisors) || length(row.divisors) != 4))
			declare_report("[origin]: [type]: sets_off(XFORM_FX_EMP) takes divisors = list(a, b, c, d)")
			return null
		if(kind == XFORM_FX_AREA && (!isnum(row.range) || !length(row.body_effects)))
			declare_report("[origin]: [type]: sets_off(XFORM_FX_AREA) takes range = n and body_effect = a path or a list of paths")
			return null
		if(kind == XFORM_FX_BLAST && (!islist(row.blast) || length(row.blast) != 4))
			declare_report("[origin]: [type]: sets_off(XFORM_FX_BLAST) takes blast = list(devastation, heavy, light, flash)")
			return null
		if(kind == XFORM_FX_LATER && (!isnum(row.delay) || !row.handler))
			declare_report("[origin]: [type]: sets_off(XFORM_FX_LATER) takes delay = n and handler = GLOBAL_PROC_REF(x)")
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
					if(istext(part)) // "lo:hi" is rolled with rand() in order
						var/list/span = splittext(part, ":")
						b += rand(text2num(span[1]), text2num(span[2]))
					else
						b += part
				explosion(location, b[1], b[2], b[3], b[4])
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
					play_sfx(subject, row.sfx, 0.75)
				after(subject, row.delay, row.handler, with = list(subject))
			if(XFORM_FX_AREA)
				for(var/mob/living/L in range(row.range, subject))
					for(var/effect_path in row.body_effects)
						L.apply_body_effect(effect_path, row.lasts, subject) // the extract is the origin: the old tails passed the rule, which a body effect refuses (an origin is an atom)
			if(XFORM_FX_EMP)
				var/list/d = row.divisors
				empulse(location, round(made / d[1]), round(made / d[2]), round(made / d[3]), round(made / d[4]), 1)
				if(row.clears && !isliving(subject))
					holder.clear_reagents()
