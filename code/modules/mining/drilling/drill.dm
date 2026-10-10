/obj/machinery/mining
	icon = 'icons/obj/mining_drill.dmi'
	anchored = FALSE
	use_power = USE_POWER_OFF //The drill takes power directly from a cell.
	density = TRUE
	layer = MOB_LAYER+0.1 //So it draws over mobs in the tile north of it.

/obj/machinery/mining/drill
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "mining drill head"
	desc = "An enormous drill."
	icon_state = "mining_drill"
	circuit = /obj/item/circuitboard/miningdrill
	var/braces_needed = 2
	var/total_brace_tier = 0
	/// Connected braces: pairs with each brace's connected (REL_PAIR_LIST).
	var/list/obj/machinery/mining/brace/supports
	var/supported = 0
	active = 0
	var/list/resource_field
	var/list/gas_field
	var/obj/item/radio/intercom/faultreporter
	var/drill_range = 5
	var/offset = 2
	var/current_capacity = 0
	var/drill_moles_per_tick = 0

	var/list/stored_ore = list( // ALLOW(instance_list): d: edited in place per instance (13 writers)
		ORE_SAND = 0,
		ORE_HEMATITE = 0,
		ORE_CARBON = 0,
		ORE_COPPER = 0,
		ORE_TIN = 0,
		ORE_VOPAL = 0,
		ORE_PAINITE = 0,
		ORE_QUARTZ = 0,
		ORE_BAUXITE = 0,
		ORE_PHORON = 0,
		ORE_SILVER = 0,
		ORE_GOLD = 0,
		ORE_MARBLE = 0,
		ORE_URANIUM = 0,
		ORE_DIAMOND = 0,
		ORE_PLATINUM = 0,
		ORE_LEAD = 0,
		ORE_MHYDROGEN = 0,
		ORE_VERDANTIUM = 0,
		ORE_RUTILE = 0)

	var/list/ore_types = list( // ALLOW(instance_list): d: edited in place per instance (4 writers)
		ORE_HEMATITE = /obj/item/ore/iron,
		ORE_URANIUM = /obj/item/ore/uranium,
		ORE_GOLD = /obj/item/ore/gold,
		ORE_SILVER = /obj/item/ore/silver,
		ORE_DIAMOND = /obj/item/ore/diamond,
		ORE_PHORON = /obj/item/ore/phoron,
		ORE_PLATINUM = /obj/item/ore/osmium,
		ORE_MHYDROGEN = /obj/item/ore/hydrogen,
		ORE_SAND = /obj/item/ore/glass,
		ORE_CARBON = /obj/item/ore/coal,
		ORE_COPPER = /obj/item/ore/copper,
		ORE_TIN = /obj/item/ore/tin,
		ORE_BAUXITE = /obj/item/ore/bauxite,
		ORE_RUTILE = /obj/item/ore/rutile
		)

	//Upgrades
	var/harvest_speed
	var/capacity
	var/charge_use
	var/exotic_drilling
	var/obj/item/cell/cell = null

	// Found with an advanced laser. exotic_drilling >= 1
	var/static/list/ore_types_uncommon = list(
		ORE_MARBLE = /obj/item/ore/marble,
		ORE_PAINITE = /obj/item/ore/painite,
		ORE_QUARTZ = /obj/item/ore/quartz,
		ORE_LEAD = /obj/item/ore/lead,
		ORE_PENTLANDITE = /obj/item/ore/pentlandite,
		ORE_CHROMITE = /obj/item/ore/chromite,
		ORE_KAOLIN = /obj/item/ore/kaolin
		)

	// Found with an ultra laser. exotic_drilling >= 2
	var/static/list/ore_types_rare = list(
		ORE_VOPAL = /obj/item/ore/void_opal,
		ORE_VERDANTIUM = /obj/item/ore/verdantium,
		ORE_WOLFRAMITE = /obj/item/ore/wolframite
		)

	//Flags
	var/need_update_field = 0
	var/need_player_check = 0
TRACKED(/obj/machinery/mining/drill, need_player_check)
TRACKED(/obj/machinery/mining/drill, supported)

CAPABILITIES(/obj/machinery/mining/drill)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(active), wakes_on = list(nameof(active)))
	owns_one(nameof(faultreporter), /obj/item/radio/intercom)
	climb()
	op("label", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), label("Assign ID number"), needs(req(PROC_REF(label_available), silent = TRUE)),
		asks(/datum/prompt/text/drill_label), then(PROC_REF(label_entered)))
	owns_one(nameof(cell), /obj/item/cell, starts = nameof(cell))
	op("use_crowbar", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(crowbar_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("attackby", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_attackby)))
	op("use", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_use)))
	op("unload", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Unload Drill"), needs(req_adjacent(), req_capable(), req(PROC_REF(dq_actor_can_act_holds))), then(PROC_REF(interaction_unload)))

/obj/machinery/mining/drill/examine(mob/user) //Let's inform people about stuff. Let people KNOW how it works.
	. = ..()
	if(Adjacent(user))
		if(cell)
			. += "The drill's cell is [round(cell.percent() )]% charged."
			if(charge_use) //Prevention of dividing by 0 errors.
				. += "The drill reads that it can mine for [round((cell.charge/charge_use)/60)] more minutes before the cell depletes."
		else
			. += "The drill has no cell installed."
		if(drill_range)
			. += "The drill will mine in a range of [drill_range] tiles."
		if(harvest_speed)
			. += "The drill can mine [harvest_speed] [(harvest_speed == 1)? "ore" : "ores"] a second!"
		if(exotic_drilling)
			. += "The drill is upgraded and is capable of mining [(exotic_drilling == 1)? "moderately further" : "as deep as possible"]!"
		if(capacity && current_capacity)
			. += "The drill currently has [current_capacity] capacity taken up and can fit [capacity - current_capacity] more ore."

/obj/machinery/mining/drill/Initialize(mapload)
	. = ..()
	default_apply_parts()
	rel_set(src, nameof(faultreporter), new /obj/item/radio/intercom{channels=list("Supply")}(null))


/obj/machinery/mining/drill/dismantle()
	if(cell)
		cell.forceMove(loc)
		rel_take(src, nameof(cell))
	return ..()

/obj/machinery/mining/drill/get_cell()
	return cell

/obj/machinery/mining/drill/loaded
	cell = /obj/item/cell/high

/// Drills every machine frame while active (declared; a fault clears active, and need_player_check
/// is only ever set together with that, so the drill sleeps until a player switches it back on).
/obj/machinery/mining/drill/proc/work_step(datum/act/timer/A)

	check_supports()
	if(!active) // check_supports() just lost the bracing and stopped the drill
		return

	if(!anchored || !use_cell_power())
		system_error("System configuration or charge error.")
		return

	if(need_update_field)
		get_resource_field()


	if(!active)
		return

	//Drill through the flooring, if any.
	if(ismineralturf(get_turf(src)))
		var/turf/simulated/mineral/M = get_turf(src)
		M.GetDrilled()
	// Extract gasses!
	else if(istype(get_turf(src), /turf/simulated/floor/gas_crack))
		if(length(gas_field))
			//Create gas mixture to hold data for passing
			var/datum/gas_mixture/GM = new
			for(var/gas in gas_field)
				GM.adjust_multi(gas, drill_moles_per_tick)
			heat_set(GM, 423)  // ~150C; must go through the arena, not the DM mirror
			var/atom/location = src.loc
			location.assume_air(GM)
	else if(istype(get_turf(src), /turf/simulated))
		var/turf/simulated/T = get_turf(src)
		T.ex_act(2.0)

	//Dig out the tasty ores.
	if(length(resource_field))
		var/turf/simulated/harvesting = DEFAULTPICK(resource_field, null)

		while(length(resource_field) && !harvesting.resources)
			harvesting.turf_resource_types &= ~(TURF_HAS_MINERALS)
			harvesting.resources = null
			rel_remove(src, nameof(resource_field), harvesting)
			if(length(resource_field)) // runtime protection
				harvesting = DEFAULTPICK(resource_field, null)
			else
				harvesting = null

		if(!harvesting) return

		var/total_harvest = harvest_speed //Ore harvest-per-tick.
		var/found_resource = 0 //If this doesn't get set, the area is depleted and the drill errors out.

		for(var/metal in ore_types)

			if(current_capacity >= capacity)
				system_error("Insufficient storage space.")
				set_active(0)
				set_need_player_check(1)
				return

			if(current_capacity + total_harvest >= capacity)
				total_harvest = capacity - current_capacity

			if(total_harvest <= 0) break
			if(harvesting.resources[metal])

				found_resource  = 1

				var/create_ore = 0
				if(harvesting.resources[metal] >= total_harvest)
					harvesting.resources[metal] -= total_harvest
					create_ore = total_harvest
					total_harvest = 0
				else
					total_harvest -= harvesting.resources[metal]
					create_ore = harvesting.resources[metal]
					harvesting.resources[metal] = 0

				for(var/i=1, i <= create_ore, i++)
					stored_ore[metal]++	// Adds the ore to the drill.
					current_capacity++	// Adds the ore to the drill's capacity.

		if(!found_resource)	// If a drill can't see an advanced material, it will destroy it while going through.
			harvesting.turf_resource_types &= ~(TURF_HAS_MINERALS)
			harvesting.resources = null
			rel_remove(src, nameof(resource_field), harvesting)

	else if(!length(gas_field)) // Won't stop digging if gas pressure is detected
		set_active(0)
		set_need_player_check(1)
		system_error("Resources depleted.")

/obj/machinery/mining/drill/proc/interaction_attackby(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	if(!active)
		if(default_part_replacement(user, O))
			return TRUE
	if(!panel_open || active)
		return OP_DECLINE

	if(istype(O, /obj/item/cell))
		if(cell)
			balloon_alert(user, "the drill already has a cell installed.")
		else
			if(!move_into(src, nameof(src.cell), O, user))
				return TRUE
			materialize_parts()
			// The cell var owns it; it is not also a component part (one owner per entity).
			balloon_alert(user, "you install \the [O]")
		return TRUE
	return OP_DECLINE

/obj/machinery/mining/drill/proc/label_available(datum/act/op/A)
	return (!active) ? null : MSG(op/not_available)

/// The multitool's answer: the drill's new id number, or no number at all (an active drill keeps its name).
/obj/machinery/mining/drill/proc/label_entered(datum/act/op/A)
	if(active || isnull(A.answer))
		SStgui.update_uis(src)
		return OP_OK
	var/newtag = text2num(sanitizeSafe(A.answer.value, 4))
	if(newtag)
		name = "[initial(name)] #[newtag]"
		to_chat(A.actor, span_notice("You changed the drill ID to: [newtag]"))
	else
		name = initial(name)
		to_chat(A.actor, span_notice("You removed the drill's ID and any extraneous labels."))
	SStgui.update_uis(src)
	return OP_OK

/datum/prompt/text/drill_label
	question = "Enter new ID number or leave empty to cancel."
	title = "Assign ID number"
	timeout = 0
	max_len = 4
	name_text = TRUE
	encode = FALSE
	multiline = FALSE

/datum/prompt/text/drill_label/recheck_extra()
	. = ..()
	if(.)
		return
	var/obj/machinery/mining/drill/drill = owner
	if(istype(drill) && drill.active)
		return "the drill is active"
	return null

/obj/machinery/mining/drill/proc/screwdriver_used(datum/act/op/A)
	if(active)
		return OP_OK
	return OP_DECLINE

/obj/machinery/mining/drill/proc/crowbar_used(datum/act/op/A)
	if(active)
		return OP_OK
	return OP_DECLINE

/obj/machinery/mining/drill/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	check_supports()
	RefreshParts()

	if (panel_open && cell && user.Adjacent(src))
		balloon_alert(user, "you take out \the [cell]")
		var/obj/item/cell/removed = rel_take(src, nameof(cell))
		user.put_in_hands(removed)
		return TRUE
	else if(need_player_check)
		balloon_alert(user, "manual override hit, the drill's error checking resets.")
		set_need_player_check(0)
		if(anchored)
			get_resource_field()
		return TRUE
	else if(supported && !panel_open)
		if(use_cell_power())
			set_active(!active)
			if(active)
				visible_message(span_infoplain(span_bold("\The [src]") + " lurches downwards, grinding noisily."))
				need_update_field = 1
				harvest_speed *= total_brace_tier
				charge_use *= total_brace_tier
			else
				visible_message(span_infoplain(span_bold("\The [src]") + " shudders to a grinding halt."))
		else
			to_chat(user, span_notice("The drill is unpowered."))
	else
		to_chat(user, span_notice("Turning on a piece of industrial machinery without sufficient bracing or wires exposed is a bad idea."))

	return TRUE

/obj/machinery/mining/drill/proc/appearance_state()
	if(need_player_check)
		return "mining_drill_error"
	if(active)
		return "mining_drill_active"
	if(supported)
		return "mining_drill_braced"
	return "mining_drill"

/// The look (the draw sweep: from its template).
/obj/machinery/mining/drill/draw(datum/look/look)
	..()
	look.state("[appearance_state()]")

/obj/machinery/mining/drill/RefreshParts()
	..()
	harvest_speed = 0
	capacity = 0
	charge_use = 50
	drill_range = 5
	offset = 2

	var/laser_rating = get_part_rating(/obj/item/stock_parts/micro_laser)
	if(laser_rating)
		harvest_speed = laser_rating ** 2 // 1, 4, 9, 16, 25
		exotic_drilling = laser_rating - 1
		if(exotic_drilling >= 1)
			ore_types |= ore_types_uncommon
			if(exotic_drilling >= 2)
				ore_types |= ore_types_rare
		else
			ore_types -= ore_types_uncommon
			ore_types -= ore_types_rare
		if(laser_rating > 3) // are we t4+?
			// default drill range 5, offset 2
			if(laser_rating >= 5) // t5
				drill_range = 9
				offset = 4
			else if(laser_rating >= 4) // t4
				drill_range = 7
				offset = 3
	var/bin_rating = get_part_rating(/obj/item/stock_parts/matter_bin)
	if(bin_rating)
		capacity = 200 * bin_rating
	var/cap_rating = get_part_rating(/obj/item/stock_parts/capacitor)
	if(cap_rating)
		charge_use -= 10 * cap_rating
	// `cell` is set only by inserting one (it is not a board part, so not in component_parts);
	// re-adopting "whatever cell is inside" here could claim a cell another var already owns.

/obj/machinery/mining/drill/proc/check_supports()

	set_supported(0)
	total_brace_tier = 0

	var/list/braces = supports
	if(!length(braces) && initial(anchored) == 0)
		icon_state = "mining_drill"
		set_anchored(FALSE)
		set_active(0)
	else
		set_anchored(TRUE)

	if(length(braces))
		if(length(braces) >= braces_needed)
			set_supported(1)
		else for(var/obj/machinery/mining/brace/check in braces)
			if(check.brace_tier >= 3)
				set_supported(1)
		for(var/obj/machinery/mining/brace/check in braces)
			total_brace_tier += check.brace_tier


/obj/machinery/mining/drill/proc/system_error(error)

	if(error)
		src.visible_message(span_infoplain(span_bold("\The [src]") + " flashes a '[error]' warning."))
		faultreporter.autosay(error, src.name, "Supply", using_map.get_map_levels(z))
	set_need_player_check(1)
	set_active(0)

/obj/machinery/mining/drill/proc/get_resource_field()

	rel_clear(src, nameof(resource_field))
	gas_field = list()
	need_update_field = 0
	drill_moles_per_tick = 0

	var/turf/T = get_turf(src)
	if(!istype(T)) return

	var/tx = T.x - offset
	var/ty = T.y - offset
	var/turf/simulated/mine_turf
	for(var/iy = 0,iy < drill_range, iy++)
		for(var/ix = 0, ix < drill_range, ix++)
			mine_turf = locate(tx + ix, ty + iy, T.z)
			if(!istype(mine_turf, /turf/space/))
				if(mine_turf && mine_turf.turf_resource_types & TURF_HAS_MINERALS)
					rel_add(src, nameof(resource_field), mine_turf)
				// gas mining
				if(istype(mine_turf,/turf/simulated/floor/gas_crack))
					// Get gasses the cracks around us could give!
					var/turf/simulated/floor/gas_crack/G = mine_turf
					if(!G.gas_type)
						continue
					drill_moles_per_tick += 2
					LAZYADD(gas_field, G.gas_type)
	if(!length(resource_field) && !length(gas_field))
		system_error("Resources depleted.")

/obj/machinery/mining/drill/proc/use_cell_power()
	if(!cell) return 0
	return cell.checked_use(charge_use)

/// Requirement: dq_actor_can_act returns null to allow, or a refusal reason.
/obj/machinery/mining/drill/proc/dq_actor_can_act_holds(datum/act/op/A)
	READS_FROM(A.actor)
	return (isliving(A.actor) && !A.actor.incapacitated()) ? null : "you can't do that right now"

/obj/machinery/mining/drill/proc/interaction_unload(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/structure/ore_box/B = locate_in_list(orange(1), /obj/structure/ore_box)
	if(B)
		for(var/ore in stored_ore)
			if(stored_ore[ore] > 0)
				var/ore_amount = stored_ore[ore]	// How many ores does the satchel have?
				B.stored_ore[ore] += ore_amount 	// Add the ore to the machine.
				stored_ore[ore] = 0 				// Set the value of the ore in the satchel to 0.
				current_capacity = 0				// Set the amount of ore in the drill to 0.
		balloon_alert(user, "onloaded cache into the ore box.")
	else
		balloon_alert(user, "move an ore box to the drill before unloading it.")
	return TRUE

/obj/machinery/mining/brace
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "mining drill brace"
	desc = "A machinery brace for an industrial drill. It looks easily two feet thick."
	icon_state = "mining_brace"
	circuit = /obj/item/circuitboard/miningdrillbrace
	var/brace_tier = 1
	var/tmp/obj/machinery/mining/drill/connected

/obj/machinery/mining/brace/examine(mob/user)
	. = ..()
	if(brace_tier >= 3)
		. += span_notice("The internals of the brace look resilient enough to support a drill by itself.")

CAPABILITIES(/obj/machinery/mining/brace)
	links(/obj/machinery/mining/brace::connected, /obj/machinery/mining/drill::supports, b_many = TRUE)
	climb()
	op("use_crowbar", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(crowbar_used)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wrench_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("attackby", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req(PROC_REF(can_work_on_holds))), then(PROC_REF(interaction_attackby)))
	default_parts()
	rotatable()

/obj/machinery/mining/brace/RefreshParts()
	..()
	brace_tier = get_part_rating(/obj/item/stock_parts/manipulator)

/// Requirement: the brace of a running drill can't be worked on.
/obj/machinery/mining/brace/proc/can_work_on(mob/user, atom/target, obj/item/held)
	if(connected() && connected().active)
		return "you can't work with the brace of a running drill"
	return null

/// Requirement: can_work_on returns null to allow, or a refusal reason.
/obj/machinery/mining/brace/proc/can_work_on_holds(datum/act/op/A)
	return can_work_on(A.actor, src, A.held)

/obj/machinery/mining/brace/proc/interaction_attackby(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(default_part_replacement(user,W))
		return TRUE
	return OP_DECLINE

/obj/machinery/mining/brace/proc/screwdriver_used(datum/act/op/A)
	if(connected()?.active)
		return OP_OK
	return OP_DECLINE

/obj/machinery/mining/brace/proc/crowbar_used(datum/act/op/A)
	if(connected()?.active)
		return OP_OK
	return OP_DECLINE

/obj/machinery/mining/brace/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(connected()?.active)
		balloon_alert(user, "you can't work with the brace of a running drill.")
		return OP_OK
	if(istype(get_turf(src), /turf/space))
		balloon_alert(user, "you can't anchor something to empty space. Idiot.")
		return OP_OK
	playsound(src, tool.usesound, 100, TRUE)
	balloon_alert(user, "[anchored ? "una" : "a"]nchored the brace")
	set_anchored(!anchored)
	if(anchored)
		connect()
	else
		disconnect()
	return OP_OK

/obj/machinery/mining/brace/proc/connect()

	var/turf/T = get_step(get_turf(src), src.dir)

	for(var/thing in contents_of(T))
		if(istype(thing, /obj/machinery/mining/drill))
			rel_set(src, nameof(connected), thing)
			break

	if(!connected())
		return

	icon_state = "mining_brace_active"

	// rel_set() above already listed us in the drill's supports (the pair).
	connected().check_supports()

/obj/machinery/mining/brace/proc/disconnect()

	if(!connected()) return

	icon_state = "mining_brace"

	var/obj/machinery/mining/drill/drill = connected()
	rel_clear(src, nameof(connected)) // leaves the drill's supports too (the pair)
	drill.check_supports()

/// Accessor for the connected var.
/obj/machinery/mining/brace/proc/connected() as /obj/machinery/mining/drill
	return connected
