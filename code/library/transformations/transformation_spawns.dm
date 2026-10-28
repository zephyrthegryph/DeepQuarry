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
	var/sfx
	/// Percent chance a copy is scattered at all (null: always, when `scatter` is set).
	var/scatter_chance

/// The rows of a rule's `spawns` argument (one spawns() or a list of them), or null (reported) when one is wrong.
/proc/xform_spawn_rows(type, origin, spawns_argument)
	var/list/rows = list()
	for(var/datum/entry/part/effect/spawns/E as anything in entry_flatten(islist(spawns_argument) ? spawns_argument : list(spawns_argument)))
		if(!istype(E))
			declare_report("[origin]: [type]: spawns = takes spawns(...) rows")
			return null
		var/list/arguments = E.args
		var/what = arguments["type"]
		if(!ispath(what) && !islist(what) && !istype(what, /datum/entry/part/pick_from) && !(istext(what) && length(what)))
			declare_report("[origin]: [type]: spawns() names a type, a weighted list or the name of a global list, not [what]")
			return null
		if(!xform_names_ok(type, origin, what))
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
		row.sfx = arguments["sfx"]
		row.scatter_chance = arguments["scatter_chance"]
		rows += row
	if(!length(rows))
		declare_report("[origin]: [type]: spawns = names no spawns() row")
		return null
	return rows

/// The weighted list or type a row's `what` names now. Null (logged) when the global list is not there.
/proc/xform_spawn_source(datum/xform/X, datum/xform_spawn/row)
	if(istype(row.what, /datum/entry/part/pick_from))
		var/datum/entry/part/pick_from/pick = row.what
		return xform_pick_table(X, pick.args["choices"])
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
		if(row.sfx)
			play_sfx(subject, row.sfx)
		var/count = xform_spawn_count(row, made)
		var/stack_size = row.amount
		if(row.per == SPAWN_STACK_MADE)
			stack_size = count
			count = count > 0 ? 1 : 0
		if(GLOB.xform_trace)
			log_world("XFORM: [X.rule_type] spawns [count] x [istext(row.what) ? "GLOB.[row.what]" : (islist(row.what) ? "a weighted pick" : "[row.what]")] at [place] ([place.x],[place.y],[place.z])")
		for(var/i in 1 to count)
			var/what = row.what
			var/copy_size = stack_size
			if(istype(what, /datum/entry/part/pick_from))
				var/datum/entry/part/pick_from/pick = what
				var/list/choice = xform_pick_choice(pick.args["choices"])
				if(!choice)
					continue
				what = pickweight(xform_pick_source(X, choice[2]))
				if(length(choice) >= 3 && !isnull(choice[3]))
					copy_size = choice[3]
			else if(!ispath(what))
				what = pickweight(xform_spawn_source(X, row))
			if(!ispath(what))
				continue
			var/atom/movable/made_thing = isnull(copy_size) ? new what(place) : new what(place, copy_size)
			if(QDELETED(made_thing))
				continue
			if(row.inherit)
				made_thing.inherit_heat(subject_k)
			if(row.scatter && (isnull(row.scatter_chance) || prob(row.scatter_chance)))
				for(var/step_count = 1, step_count <= rand(1, row.scatter), step_count++)
					step(made_thing, pick(NORTH, SOUTH, EAST, WEST))

/// The table a pick_from() settles on now: one of its choices by weight, then that choice's source as a list of types (weighted or not).
/proc/xform_pick_table(datum/xform/X, list/choices)
	var/list/weights = list()
	for(var/i in 1 to length(choices))
		var/weight = choices[i][1]
		if(islist(weight))
			weight = xform_pick_weight(weight)
		weights["[i]"] = weight
	var/chosen = text2num(pickweight(weights))
	if(!chosen)
		return null
	return xform_pick_source(X, choices[chosen][2])

/// The number a length_of() or weight_sum_of() weight stands for now.
/proc/xform_pick_weight(list/spec)
	if(spec[1] == "length_of")
		var/list/measured = GLOB.vars[spec[2]]
		return islist(measured) ? length(measured) : 0
	var/total = 0
	for(var/name in spec[2])
		var/list/summed = GLOB.vars[name]
		if(!islist(summed))
			continue
		for(var/entry in summed)
			var/entry_weight = summed[entry]
			total += isnum(entry_weight) ? entry_weight : 1
	return total

/// The choice (list(weight, source[, amount])) a pick_from() settles on now, or null.
/proc/xform_pick_choice(list/choices)
	var/list/weights = list()
	for(var/i in 1 to length(choices))
		var/weight = choices[i][1]
		if(islist(weight))
			weight = xform_pick_weight(weight)
		weights["[i]"] = weight
	var/chosen = text2num(pickweight(weights))
	return chosen ? choices[chosen] : null

/// A pick_from() source as a list of types: a GLOB list's name, a list of names (their union), or subtypes_of().
/proc/xform_pick_source(datum/xform/X, source)
	if(istext(source))
		var/list/table = GLOB.vars[source]
		if(!islist(table) || !length(table))
			log_world("XFORM: [X.rule_type] picks from GLOB.[source], which is not a list with entries")
			return null
		return table
	var/list/parts = source
	if(length(parts) && parts[1] == "types")
		var/list/matching = list()
		for(var/candidate in typesof(parts[2]))
			if(!parts[3] || call(parts[3])(candidate))
				matching += candidate
		return matching
	if(length(parts) && parts[1] == "subtypes")
		var/list/found = subtypesof(parts[2])
		for(var/excluded in parts[3])
			found -= subtypesof(excluded)
		return found
	var/list/union = list()
	for(var/name in parts)
		var/list/table = GLOB.vars[name]
		if(!islist(table))
			log_world("XFORM: [X.rule_type] picks from GLOB.[name], which is not a list")
			continue
		union += table
	return union

/// TRUE when every GLOB name a spawns() `what` mentions (a bare name, or inside a pick_from()) is a GLOB var; reports the first that is not (the boot gate).
/proc/xform_names_ok(type, origin, what)
	var/list/names = list()
	if(istext(what))
		names += what
	else if(istype(what, /datum/entry/part/pick_from))
		var/datum/entry/part/pick_from/pick = what
		var/list/choices = pick.args["choices"]
		if(!islist(choices) || !length(choices))
			declare_report("[origin]: [type]: pick_from(choices = ...) names no choice")
			return FALSE
		for(var/list/choice in choices)
			if(length(choice) < 2)
				declare_report("[origin]: [type]: a pick_from() choice is list(weight, source) or list(weight, source, amount)")
				return FALSE
			var/weight = choice[1]
			if(islist(weight))
				if(weight[1] == "length_of")
					names += weight[2]
				else if(weight[1] == "weight_sum_of")
					names += weight[2]
				else
					declare_report("[origin]: [type]: a pick_from() weight is a number, length_of() or weight_sum_of()")
					return FALSE
			else if(!isnum(weight))
				declare_report("[origin]: [type]: a pick_from() weight is a number, length_of() or weight_sum_of(), not [weight]")
				return FALSE
			var/source = choice[2]
			if(istext(source))
				names += source
			else if(islist(source) && length(source) && source[1] != "subtypes" && source[1] != "types")
				names += source
	for(var/name in names)
		if(islist(name))
			for(var/inner in name)
				if(!istext(inner) || !(inner in GLOB.vars))
					declare_report("[origin]: [type]: [inner] is not a GLOB var (write nameof(GLOB.x))")
					return FALSE
		else if(!istext(name) || !(name in GLOB.vars))
			declare_report("[origin]: [type]: [name] is not a GLOB var (write nameof(GLOB.x))")
			return FALSE
	return TRUE
