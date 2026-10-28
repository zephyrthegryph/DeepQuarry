// spawns(): the atoms a transformation step makes (doc/rewrite/proposals/transformations.md section 6).
//
//   spawns(what, n = 1, at = SUBJECT_TURF, per = SPAWN_PER_STEP, amount = null, scatter = 0, inherit = TRUE, tell = null, audit = null)
//
//   what     a type; or an assoc list type => weight, one drawn with pickweight() for every copy; or the name (text) of a GLOB list of weights
//            ("xenobio_metal_materials_normal" is GLOB.xenobio_metal_materials_normal), read when the step goes, never at compile.
//   n        copies; list(lo, hi) rolls rand(lo, hi) once per step. How it scales is `per`:
//              SPAWN_PER_STEP    n copies each step the rule goes, whatever its extent (what every legacy tail did).
//              SPAWN_PER_MADE    n * FLOOR(made) copies, `made` being what the step made (reaction progress times the rule's `made` or product amount).
//              SPAWN_STACK_MADE  one stack of n * FLOOR(made) units; nothing when that is 0.
//   at       SUBJECT_TURF: the turf of the thing the reagents are in (the only place built).
//   amount   the second constructor argument of every copy (a stack's size).
//   scatter  each copy then takes random cardinal steps while its count <= rand(1, scatter): the roll is repeated for every step, as the legacy loops did, so the
//            seeded rng sequence of a converted tail is unchanged (and how far a copy goes is a tail, not a cap).
//   inherit  a real transformation hands its heat on: each copy starts at the temperature the subject had when the step went (inherit_heat()).
//            Deleting the subject drops its heat, it never dumps it (code/modules/heat/heat.dm).
//   tell     a message the subject shows (visible_message) before the copies are made.
//   audit    an admin log line "<audit> has been activated in <area>.  Last fingerprints: <last print>", logged before the copies are made.
//
// The op part spawns(T, n) of code/engine/parts/part.dm carries these arguments; an op ignores the ones it does not know.
//
// Rows run in declaration order, copies in order: the rng is rolled in that order (pick, then the constructor, then the scatter), so a seeded
// settle is reproducible. Nothing here sleeps. A subject that is gone or has no turf spawns nothing and says so in the world log; a copy that
// deletes itself in its constructor is skipped (no heat, no scatter).

/// A compiled spawns() row.
/datum/xform_spawn
	var/what
	var/n = 1
	var/per = SPAWN_PER_STEP
	var/amount
	var/scatter = 0
	var/inherit = TRUE
	var/tell
	var/audit

/// The rows of a rule's `spawns` argument (one spawns() or a list of them), or null (reported) when one is wrong.
/proc/xform_spawn_rows(type, origin, spawns_argument)
	var/list/rows = list()
	for(var/datum/entry/part/effect/spawns/E as anything in entry_flatten(islist(spawns_argument) ? spawns_argument : list(spawns_argument)))
		if(!istype(E))
			declare_report("[origin]: [type]: spawns = takes spawns(...) rows")
			return null
		var/list/arguments = E.args
		var/what = arguments["type"]
		if(!ispath(what) && !islist(what) && !(istext(what) && length(what)))
			declare_report("[origin]: [type]: spawns() names a type, a weighted list or the name of a global list, not [what]")
			return null
		var/at = arguments["at"] || SUBJECT_TURF
		if(at != SUBJECT_TURF)
			declare_report("[origin]: [type]: spawns(at = [at]) is not built -- only SUBJECT_TURF is")
			return null
		var/per = arguments["per"] || SPAWN_PER_STEP
		if(per != SPAWN_PER_STEP && per != SPAWN_PER_MADE && per != SPAWN_STACK_MADE)
			declare_report("[origin]: [type]: spawns(per = [per]) is not SPAWN_PER_STEP, SPAWN_PER_MADE or SPAWN_STACK_MADE")
			return null
		var/n = arguments["n"]
		if(!isnum(n) && !(islist(n) && length(n) == 2))
			declare_report("[origin]: [type]: spawns(n = [n]) is a number or list(lo, hi)")
			return null
		if(per == SPAWN_STACK_MADE && !ispath(what, /obj/item/stack))
			declare_report("[origin]: [type]: spawns(per = SPAWN_STACK_MADE) makes a stack type")
			return null
		var/datum/xform_spawn/row = new
		row.what = what
		row.n = n
		row.per = per
		row.amount = arguments["amount"]
		row.scatter = arguments["scatter"] || 0
		row.inherit = isnull(arguments["inherit"]) ? TRUE : !!arguments["inherit"]
		row.tell = arguments["tell"]
		row.audit = arguments["audit"]
		rows += row
	if(!length(rows))
		declare_report("[origin]: [type]: spawns = names no spawns() row")
		return null
	return rows

/// The weighted list or type a row's `what` names now. Null (logged) when the global list is not there.
/proc/xform_spawn_source(datum/xform/X, datum/xform_spawn/row)
	if(!istext(row.what))
		return row.what
	var/list/table = GLOB.vars[row.what]
	if(!islist(table) || !length(table))
		log_world("XFORM: [X.rule_type] spawns from GLOB.[row.what], which is not a list with entries")
		return null
	return table

/// How many copies a row makes in a step that made `made`.
/proc/xform_spawn_count(datum/xform_spawn/row, made)
	var/n = row.n
	if(islist(n))
		n = rand(n[1], n[2])
	switch(row.per)
		if(SPAWN_PER_MADE)
			return n * FLOOR(made, 1)
		if(SPAWN_STACK_MADE)
			return n * FLOOR(made, 1)
		else
			return n

/// Runs every spawns() row of `X` for a step of `holder` that made `made`. Called by xform_effects().
/proc/xform_run_spawns(datum/xform/X, datum/reagents/holder, made)
	var/atom/subject = holder.my_atom
	if(!subject || QDELETED(subject))
		log_world("XFORM: [X.rule_type] spawns nothing: its subject is gone")
		return
	// Read before anything is made: the turf and the heat the products inherit are the subject's now.
	var/turf/place = get_turf(subject)
	if(!place)
		log_world("XFORM: [X.rule_type] spawns nothing: [subject] ([subject.type]) is not on a turf")
		return
	var/subject_k = subject.get_temperature()
	for(var/datum/xform_spawn/row as anything in X.spawn_rows)
		if(row.audit)
			log_and_message_admins("[row.audit] has been activated in [get_area(subject)].  Last fingerprints: [subject.forensic_data?.get_lastprint()]", null)
		if(row.tell)
			subject.visible_message(row.tell)
		var/count = xform_spawn_count(row, made)
		var/stack_size = row.amount
		if(row.per == SPAWN_STACK_MADE)
			stack_size = count
			count = count > 0 ? 1 : 0
		if(GLOB.xform_trace)
			log_world("XFORM: [X.rule_type] spawns [count] x [istext(row.what) ? "GLOB.[row.what]" : (islist(row.what) ? "a weighted pick" : "[row.what]")] at [place] ([place.x],[place.y],[place.z])")
		for(var/i in 1 to count)
			var/what = row.what
			if(!ispath(what))
				what = pickweight(xform_spawn_source(X, row))
			if(!ispath(what))
				continue
			var/atom/movable/made_thing = isnull(stack_size) ? new what(place) : new what(place, stack_size)
			if(QDELETED(made_thing))
				continue
			if(row.inherit)
				made_thing.inherit_heat(subject_k)
			if(row.scatter)
				for(var/step_count = 1, step_count <= rand(1, row.scatter), step_count++)
					step(made_thing, pick(NORTH, SOUTH, EAST, WEST))
