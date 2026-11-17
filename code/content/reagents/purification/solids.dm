// Solids in a glass container (the vars: code/content/reagents/purification/funnel_and_catalyst.dm; the tables: code/defines/content/chem_solids.dm).
//
// Any small item (ITEMSIZE_SMALL or less, or one sheet of a material) can be dropped into a glass container, up to CHEM_SOLIDS_MAX of them, and all of them come out again
// together, whole. What a solid does there depends on the liquid:
//
//  * It dissolves when the liquid can dissolve it. The item's feedstock (the grinder's: item_feedstock(), a sheet's by its grinding row, an ore's with the traces of its vein)
//    says what it is: the class of the reagent that makes most of it (chem_solid_classes) names the solvents that dissolve it (chem_solid_solvents: metals in an acid, soap,
//    sugar and salts in water, wax and oils in ethanol). While a solvent is in the glass (CHEM_SOLID_MIN_SOLVENT units) the solid dissolves over the seconds its class takes,
//    twice as fast for every CHEM_SOLID_HEAT_DOUBLING K the glass is above room temperature. It spends some of the solvent on the way (an acid is eaten by a metal), and when it
//    is gone the glass holds its feedstock and the traces it carried: no more than it cost to make. An item with no solvent here (glass, tungsten, a plastic) never dissolves.
//  * One that is not dissolving and is made of a catalytic material is the solid catalyst: its kind and its activity (weighted by the share of the item that material is) come
//    from the material that is most catalytic in it, by the rules of a sheet. With several, the strongest works.
//
// The dissolving counts real time between steps, so it does not matter who asks: the glass's own timer, a hot plate it stands on, or the temperature crossing the edge of a
// recipe's band (code/content/reagents/reagent_containers/reaction_watch.dm). Every insertion, dissolving step and pick is written to the world log under GLOB.chem_trace.

/// How far one solid in a glass has dissolved: a record the glass owns, naming the solid.
/datum/solid_progress
	/// 0 (whole) to 1 (gone).
	var/progress = 0

CAPABILITIES(/datum/solid_progress)
	ref_one(nameof(item), /obj/item)

/datum/solid_progress/var/obj/item/item

// ---- what fits ----

/// A small item that nothing else of the glass takes can go in: it is open, there is room, and the item is no container (those are poured), no funnel, filter or electrode
/// (those are fitted), no bag of things, and small or a sheet (one is dropped).
/obj/item/reagent_containers/glass/proc/solid_fits(datum/act/op/A)
	var/obj/item/held = A.held
	if(isnull(held) || !is_open_container() || length(solids) >= CHEM_SOLIDS_MAX)
		return FALSE
	if(istype(held, /obj/item/reagent_containers) || istype(held, /obj/item/chem_funnel) || istype(held, /obj/item/chem_filter) || istype(held, /obj/item/chem_electrode) || istype(held, /obj/item/storage))
		return FALSE
	return istype(held, /obj/item/stack/material) || held.w_class <= ITEMSIZE_SMALL

/// There is something to take out.
/obj/item/reagent_containers/glass/proc/solids_lying(datum/act/op/A)
	return length(solids) ? null : /datum/msg/req_failed

/// The timer's gate: there is something lying in it.
/obj/item/reagent_containers/glass/proc/solids_lying_now(datum/act/A)
	return length(solids) > 0

/obj/item/reagent_containers/glass/proc/solid_added(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	var/obj/item/part = held
	var/obj/item/stack/material/sheet = held
	if(istype(sheet))
		part = sheet.split(1, TRUE)
		if(!part)
			return OP_OK
	if(!move_into(src, nameof(src.solids), part, user))
		if(part != held)
			part.forceMove(get_turf(src))
		return OP_OK
	if(length(solids) == 1)
		STAMP(src, dissolve_at, CLOCK_WORLD)
	to_chat(user, span_notice("You drop \the [part] into \the [src]."))
	if(GLOB.chem_trace)
		log_world("CHEM: [user] put [part] ([part.type]) in [src] ([length(solids)] solid\s: [solids_text()]); [solid_status(part)]")
	reagents?.handle_reactions() // a route that runs on it may go now
	log_catalyst_pick("[part] went in")
	return OP_OK

/// All of the solids come out whole, into the hands that asked.
/obj/item/reagent_containers/glass/proc/solids_removed(datum/act/op/A)
	var/mob/user = A.actor
	var/list/taken = rel_take_all(src, nameof(solids))
	rel_clear(src, nameof(dissolutions))
	if(!length(taken))
		return OP_OK
	for(var/obj/item/O as anything in taken)
		O.forceMove(get_turf(src))
		user.put_in_hands(O)
	to_chat(user, span_notice("You fish [english_list(taken)] out of \the [src]."))
	if(GLOB.chem_trace)
		log_world("CHEM: [user] took [length(taken)] solid\s out of [src]: [english_list(taken)]")
	return OP_OK

/// "a, b, c" of the solids, for the log.
/obj/item/reagent_containers/glass/proc/solids_text()
	var/list/names = list()
	for(var/obj/item/O as anything in solids)
		names += "[O]"
	return jointext(names, ", ")

// ---- examine ----

/obj/item/reagent_containers/glass/examine(mob/user)
	. = ..()
	if(!length(solids) || get_dist(user, src) > 2)
		return
	for(var/obj/item/O as anything in solids)
		var/progress = solid_progress(O)
		if(solid_dissolving(O))
			. += span_notice("\A [O] lies in it, fizzing as it dissolves ([round((progress || 0) * 100)]%).")
		else
			. += span_notice("\A [O] lies in it[progress ? ", partly dissolved" : ""].")

// ---- what a solid is made of ----

/// What a solid dissolves into, as reagent id => units: its feedstock (a sheet by its grinding row, an ore with the traces of its vein, any other item as the grinder
/// makes it) with the traces and contaminants it carries. The grinder's numbers, so a solid never dissolves into more than it cost to make.
/proc/solid_feedstock(obj/item/O)
	RETURN_TYPE(/list)
	var/list/result = list()
	var/obj/item/stack/material/sheet = O
	if(istype(sheet))
		var/datum/xform/rule = grinding_sheet_rule_for(sheet.type)
		if(!rule)
			return result
		var/units_per_sheet = sheet.reagents_per_sheet()
		var/list/ids = rule.grind_ids()
		for(var/id in ids)
			result[id] = (result[id] || 0) + sheet.get_amount() * units_per_sheet / length(ids)
		var/list/carried = stack_trace_contaminants(sheet, sheet.get_amount(), units_per_sheet)
		for(var/contaminant_id in carried)
			result[contaminant_id] = (result[contaminant_id] || 0) + carried[contaminant_id]
		return result
	var/obj/item/ore/ore = O
	if(istype(ore))
		var/datum/xform/ore_rule = grinding_ore_rule_for(ore.type)
		if(!ore_rule)
			return result
		var/list/ore_ids = ore_rule.grind_ids()
		for(var/id in ore_ids)
			result[id] = (result[id] || 0) + REAGENTS_PER_ORE / length(ore_ids)
		var/list/ore_carried = ore_trace_contaminants(ore)
		for(var/contaminant_id in ore_carried)
			result[contaminant_id] = (result[contaminant_id] || 0) + ore_carried[contaminant_id]
		return result
	return item_feedstock(O)

/// The class of a feedstock (CHEM_SOLID_*): the class of the reagent there is most of, or null when the reagents a beaker does not dissolve (glass, tungsten) are
/// more of it. Contaminants do not count.
/proc/solid_class_of(list/feedstock)
	var/list/per_class = list()
	var/inert = 0
	var/best_class
	var/best = 0
	for(var/id in feedstock)
		if(contaminant_def(id))
			continue
		var/class = GLOB.chem_solid_classes[id]
		if(!class)
			inert += feedstock[id]
			continue
		per_class[class] = (per_class[class] || 0) + feedstock[id]
	for(var/class in per_class)
		if(per_class[class] > best)
			best = per_class[class]
			best_class = class
	return best >= inert ? best_class : null

// ---- dissolving ----

/// The solvent rule that applies to this solid (list: CHEM_SOLVENT_* columns), or null when nothing a beaker holds dissolves it.
/obj/item/reagent_containers/glass/proc/solid_rule(obj/item/O)
	var/class = solid_class_of(solid_feedstock(O))
	return class ? GLOB.chem_solid_solvents[class] : null

/// The reagent in the glass that dissolves this solid (the most there is of the ones its rule names, at least CHEM_SOLID_MIN_SOLVENT units), or null.
/obj/item/reagent_containers/glass/proc/solid_solvent(list/rule)
	if(!rule || !reagents)
		return null
	var/best_id
	var/best = CHEM_SOLID_MIN_SOLVENT - 0.0001
	for(var/id in rule[CHEM_SOLVENT_IDS])
		var/amount = reagents.get_reagent_amount(id)
		if(amount > best)
			best = amount
			best_id = id
	return best_id

/// Is the liquid dissolving this solid now.
/obj/item/reagent_containers/glass/proc/solid_dissolving(obj/item/O)
	return !isnull(solid_solvent(solid_rule(O)))

/// How the solid stands, for the log.
/obj/item/reagent_containers/glass/proc/solid_status(obj/item/O)
	var/list/rule = solid_rule(O)
	if(!rule)
		return "it dissolves in nothing"
	var/solvent = solid_solvent(rule)
	return solvent ? "[solvent] dissolves it" : "it waits for [english_list(rule[CHEM_SOLVENT_IDS], and_text = " or ")]"

/// How much faster than at room temperature the liquid dissolves things: doubling for every CHEM_SOLID_HEAT_DOUBLING K above it.
/obj/item/reagent_containers/glass/proc/solid_speed()
	return clamp(2 ** ((get_temperature() - T20C) / CHEM_SOLID_HEAT_DOUBLING), CHEM_SOLID_SPEED_MIN, CHEM_SOLID_SPEED_MAX)

/// The glass's own timer.
/obj/item/reagent_containers/glass/proc/dissolve_ticked(datum/act/timer/A)
	solids_step()

/// Dissolves the solids for `seconds` (the time since the last step when none is given) at the speed of the glass's temperature.
/obj/item/reagent_containers/glass/solids_step(seconds)
	if(!length(solids) || QDELETED(src))
		return
	if(isnull(seconds))
		seconds = ELAPSED(src, dissolve_at, CLOCK_WORLD) / (1 SECONDS)
	STAMP(src, dissolve_at, CLOCK_WORLD)
	seconds = clamp(seconds, 0, CHEM_SOLID_STEP_MAX)
	if(seconds <= 0 || !reagents?.total_volume)
		return
	var/speed = solid_speed()
	for(var/obj/item/O as anything in solids.Copy())
		dissolve_one(O, seconds * speed)

/// The record of how far this solid has dissolved, or null when it has not begun.
/obj/item/reagent_containers/glass/proc/dissolution_of(obj/item/O)
	RETURN_TYPE(/datum/solid_progress)
	for(var/datum/solid_progress/record as anything in dissolutions)
		if(record.item == O)
			return record
	return null

/// How far this solid has dissolved: 0 to 1.
/obj/item/reagent_containers/glass/proc/solid_progress(obj/item/O)
	return dissolution_of(O)?.progress || 0

/// `effective` seconds (at room temperature) of dissolving for one solid.
/obj/item/reagent_containers/glass/proc/dissolve_one(obj/item/O, effective)
	var/list/feed = solid_feedstock(O)
	var/class = solid_class_of(feed)
	var/list/rule = class ? GLOB.chem_solid_solvents[class] : null
	var/solvent = solid_solvent(rule)
	if(!solvent)
		return
	var/total = 0
	for(var/id in feed)
		total += feed[id]
	if(total <= 0)
		return
	var/datum/solid_progress/record = dissolution_of(O)
	var/before = record?.progress || 0
	var/after = min(1, before + effective / rule[CHEM_SOLVENT_SECONDS])
	if(after > before)
		if(!record)
			record = new /datum/solid_progress
			rel_add(src, nameof(dissolutions), record)
			rel_set(record, nameof(record.item), O)
			visible_message(span_notice("\The [O] begins to fizz in \the [src]."))
		record.progress = after
		var/spend = min(total * (after - before) * rule[CHEM_SOLVENT_SPEND], reagents.get_reagent_amount(solvent))
		if(spend > 0)
			reagents.remove_reagent(solvent, spend, safety = 1)
		if(GLOB.chem_trace)
			log_world("CHEM: [O] in [src] dissolves in [solvent] ([class]): [round(before * 100)]% -> [round(after * 100)]% at x[round(solid_speed(), 0.01)], spent [round(spend, 0.001)] of the solvent")
	if(after < 1)
		return
	if(reagents.get_free_space() < total)
		if(GLOB.chem_trace)
			log_world("CHEM: [O] in [src] is dissolved but there is no room for [round(total, 0.01)] units of it: it waits")
		return
	for(var/id in feed)
		reagents.add_reagent(id, feed[id], safety = 1)
	rel_remove(src, nameof(dissolutions), record)
	visible_message(span_notice("\The [O] dissolves in \the [src]."))
	if(GLOB.chem_trace)
		log_world("CHEM: [O] dissolved in [src] into [contaminants_text(feed)]")
	rel_remove(src, nameof(solids), O) // owned: gone with it
	reagents.handle_reactions()
	log_catalyst_pick("[O] dissolved")

// ---- the solid catalyst ----

/// What one solid does as a catalyst, as list(kind, activity), or null when it is made of nothing catalytic. Its dominant catalytic material (the one that most of its
/// catalytic strength comes from) gives the kind and the activity, the activity weighted by the share of the item that material is (a sheet is all of it).
/obj/item/reagent_containers/glass/proc/solid_catalysis(obj/item/O)
	var/datum/material/best_material
	var/best_share = 0
	var/obj/item/stack/material/sheet = O
	if(istype(sheet))
		if(sheet.material?.trait(MT_CATALYTIC) > 0)
			best_material = sheet.material
			best_share = 1
	else
		var/list/composition = O.get_material_composition()
		var/total = 0
		for(var/datum/material/M as anything in composition)
			total += composition[M]
		var/best_score = 0
		for(var/datum/material/M as anything in composition)
			var/strength = M.trait(MT_CATALYTIC)
			if(strength <= 0 || total <= 0)
				continue
			var/share = composition[M] / total
			if(strength * share > best_score)
				best_score = strength * share
				best_material = M
				best_share = share
	if(!best_material)
		return null
	var/kind = CHEM_CATALYST_SOLID_METAL
	if(best_material.sorbed_volume() >= CHEM_SOLID_ACID_POROSITY)
		kind = CHEM_CATALYST_SOLID_ACID
	else if(best_material.heat_resistance >= CHEM_REFRACTORY_HEAT)
		kind = CHEM_CATALYST_SOLID_REFRACTORY
	return list(kind, clamp(best_material.trait(MT_CATALYTIC), 0, 100) * best_share)

/// The solid that works as the catalyst: list(item, kind, activity) for the strongest of those not being dissolved, or null with none.
/obj/item/reagent_containers/glass/proc/strongest_catalyst()
	var/list/best
	for(var/obj/item/O as anything in solids)
		var/list/catalysis = solid_catalysis(O)
		if(!catalysis || (best && catalysis[2] <= best[3]))
			continue
		if(solid_dissolving(O))
			continue
		best = list(O, catalysis[1], catalysis[2])
	return best

/// The activity (0..100) of the solid catalyst in the glass: 0 with none.
/obj/item/reagent_containers/glass/proc/catalyst_activity()
	var/list/best = strongest_catalyst()
	return best ? best[3] : 0

/// The kind of the solid catalyst in the glass (CHEM_CATALYST_SOLID_ACID for a porous material, CHEM_CATALYST_SOLID_REFRACTORY for a heat-resistant metal, else
/// CHEM_CATALYST_SOLID_METAL), or null with none.
/obj/item/reagent_containers/glass/proc/catalyst_kind()
	var/list/best = strongest_catalyst()
	return best ? best[2] : null

/// Writes which solid works as the catalyst now (and why it is asked: what just changed) to the world log.
/obj/item/reagent_containers/glass/proc/log_catalyst_pick(why)
	if(!GLOB.chem_trace)
		return
	var/list/best = strongest_catalyst()
	if(!best)
		log_world("CHEM: [src]: no solid catalyst ([why]; [length(solids)] solid\s)")
		return
	log_world("CHEM: [src]: [best[1]] is the [best[2]] catalyst of activity [round(best[3], 0.1)] ([why]; [length(solids)] solid\s)")
