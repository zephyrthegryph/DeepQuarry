///The 'ID' for deconstructing items for Research points instead of nodes.
#define DESTRUCTIVE_ANALYZER_DESTROY_POINTS "research_points"

/*
Destructive Analyzer

It is used to destroy hand-held objects and advance technological research. Used to perform /datum/experiment/physical/destructive_analysis experiments.
*/

MSG_DEF_SELF(analyzer/busy, "It's busy right now.")

/obj/machinery/rnd/destructive_analyzer
	name = "destructive analyzer"
	icon_state = "d_analyzer"
	var/decon_mod = 0
	circuit = /obj/item/circuitboard/destructive_analyzer
	use_power = USE_POWER_IDLE
	idle_power_usage = 30
	active_power_usage = 2500
	var/rped_recycler_ready = TRUE
	var/datum/remote_materials/rmat

/// Busy analysing an item (or recycling parts).
OM_FIELD(/obj/machinery/rnd/destructive_analyzer, busy, FALSE, CHANGE_MACHINE_SETTINGS)

///Reset the state of this machine
/obj/machinery/rnd/destructive_analyzer/proc/reset_busy()
	set_busy(FALSE)

CAPABILITIES(/obj/machinery/rnd/destructive_analyzer)
	owns_one(nameof(rmat), /datum/remote_materials)
	interface("DestructiveAnalyzer")
	extend("ui_open", needs(req_is(STAT_DISABLED, FALSE, because = MSG(rnd/disabled))))
	extend("part_replacement.replace", needs(req(PROC_REF(idle), because = MSG(analyzer/busy))))
	op("eject_item", ui_act("eject_item"), then(PROC_REF(ui_act_eject_item)))
	// An item goes in through the closed hatch while it is idle (not a cyborg's module item); a part replacer dragged onto it recycles its lowest parts.
	op("load", item(/obj/item), label("Load"), priority(OP_PRIORITY_DEFAULT), when(req(PROC_REF(hatch_shut))), when(cond_not(req(/mob/living/silicon/robot, of = ON_ACTOR))),
		needs(req(PROC_REF(idle), because = MSG(analyzer/busy))), then(PROC_REF(interaction_load)))
	op("recycle", item(/obj/item/storage/part_replacer), gesture(GESTURE_DRAG), label("Recycle parts"), then(PROC_REF(interaction_recycle)))
	op("deconstruct", ui_act("deconstruct", arg("deconstruct_id", schema_text(4096))), then(PROC_REF(ui_act_deconstruct)))

/obj/machinery/rnd/destructive_analyzer/Initialize(mapload)
	rel_set(src, nameof(rmat), new /datum/remote_materials( \
		src, \
		mapload, \
		mat_container_flags = MATCONTAINER_NO_INSERT \
	))

	//Destructive analysis
	var/static/list/destructive_events = list(
		/datum/notice/machinery_destructive_scan = TYPE_PROC_REF(/datum/experiment_handler, try_run_destructive_experiment),
	)

	new /datum/experiment_handler(src, \
		config_mode = EXPERIMENT_CONFIG_ALTCLICK, \
		allowed_experiments = list(/datum/experiment/scanning),\
		config_flags = EXPERIMENT_CONFIG_ALWAYS_ACTIVE|EXPERIMENT_CONFIG_SILENT_FAIL,\
		experiment_events = destructive_events, \
	)
	. = ..()
	default_apply_parts()
	add_trait(src, TRAIT_ALT_CLICK_BLOCKER, ROUNDSTART_TRAIT)

/obj/machinery/rnd/destructive_analyzer/RefreshParts()
	var/T = total_component_rating_of_type(/obj/item/stock_parts)
	T *= 0.1
	decon_mod = clamp(T, 0, 1)

/// Its open panel and the item it holds have their own states.
/obj/machinery/rnd/destructive_analyzer/draw(datum/look/look)
	..()
	look.hide(LOOK_PANEL_OPEN)
	if(panel_open(src))
		look.state("d_analyzer_t")
	else if(loaded_item)
		look.state("d_analyzer_l")
	else
		look.state("d_analyzer")

/// Not busy analysing (a requirement of the part replacer).
/obj/machinery/rnd/destructive_analyzer/proc/idle(datum/act/A)
	return !busy

/// Its maintenance hatch is shut (an item goes in only then).
/obj/machinery/rnd/destructive_analyzer/proc/hatch_shut(datum/act/op/A)
	return !panel_open(src)

/obj/machinery/rnd/destructive_analyzer/proc/interaction_load(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	var/current_item = loaded_item
	if(current_item)
		to_chat(user, span_notice("There is something already loaded into \the [src]."))
	else
		if(is_type_in_list(O, GLOB.item_deconstruction_blacklist))
			to_chat(user, span_notice("The machine rejects \the [O]!"))
			return
		if((O.item_flags & DROPDEL) || (O.item_flags & NOSTRIP))
			to_chat(user, span_notice("The machine rejects \the [O]!"))
			return
		if(O?.tether_host())
			to_chat(user, span_notice("The machine rejects \the [O]!"))
			return
		if(LAZYLEN(O.contents))
			var/bad_item = FALSE
			for(var/obj/item/thing in contents_of(O))
				if(thing.item_flags & ABSTRACT)
					continue
				bad_item = TRUE
				break
			if(bad_item)
				to_chat(user, span_notice("The machine rejects \the [O]! You need to clear it of all items first!"))
				return
		set_busy(TRUE)
		if(!move_into(src, nameof(src.loaded_item), O, user))
			return
		SStgui.update_uis(src)
		to_chat(user, span_notice("You add \the [O] to \the [src]."))
		flick("d_analyzer_la", src)
		after(src, 1 SECONDS, PROC_REF(analyze_finish))

/obj/machinery/rnd/destructive_analyzer/proc/analyze_finish()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	reset_busy()

///////////////////////////////////////////////////////////////////////////////////////////////////////
// RPED recycling
///////////////////////////////////////////////////////////////////////////////////////////////////////
/obj/machinery/rnd/destructive_analyzer/proc/interaction_recycle(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/storage/part_replacer/replacer = A.held
	replacer.hide_from(user)
	if(!rped_recycler_ready)
		to_chat(user, span_notice("\The [src]'s stock parts recycler isn't ready yet."))
		return

	// We want the lowest-part tier rating in the RPED so we only recycle the lowest-tier parts.
	var/lowest_rating = INFINITY
	replacer.latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/B in contents_of(replacer)) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		if(B.rped_rating() < lowest_rating)
			lowest_rating = B.rped_rating()
	if(lowest_rating == INFINITY)
		atom_say("Mass part deconstruction attempt canceled - no valid parts for recycling detected.")
		return
	// Sending salvaged materials to the silo
	var/datum/material_container/materials = get_silo_material_container_datum(TRUE)
	if(!materials)
		return
	replacer.latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/B in contents_of(replacer)) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		if(B.rped_rating() > lowest_rating)
			continue
		materials.insert_item(B, decon_mod, src)
	// Feedback
	play_sfx(get_turf(src), SFX_MACHINES_CLICK)
	rped_recycler_ready = FALSE
	after(src, 5 SECONDS, PROC_REF(rped_ready))
	to_chat(user, span_notice("You deconstruct all the parts of rating [lowest_rating] in [replacer] with [src]."))

/obj/machinery/rnd/destructive_analyzer/proc/rped_ready()
	PRIVATE_PROC(TRUE)
	SHOULD_NOT_OVERRIDE(TRUE)

	rped_recycler_ready = TRUE
	play_sfx(get_turf(src), SFX_MACHINES_CHIME)

/obj/machinery/rnd/destructive_analyzer/proc/get_silo_material_container_datum(verbose)
	var/datum/material_container/materials = rmat.mat_container()
	if(!materials)
		if(verbose)
			atom_say("No access to material storage, please contact the quartermaster.")
		return null
	if(rmat.on_hold())
		if(verbose)
			atom_say("Mineral access is on hold, please contact the quartermaster.")
		return null
	return materials

///////////////////////////////////////////////////////////////////////////////////////////////////////
// Handling deconstruction
///////////////////////////////////////////////////////////////////////////////////////////////////////

/// /obj/machinery/rnd/destructive_analyzer's window data.
/obj/machinery/rnd/destructive_analyzer/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["server_connected"] = !!stored_research
	data["node_data"] = null
	var/obj/item/current_item = loaded_item
	if(current_item)
		data["item_icon"] = icon2base64(getFlatIcon(image(icon = current_item.icon, icon_state = current_item.icon_state), no_anim = TRUE))
		data["indestructible"] = is_type_in_list(current_item, GLOB.item_deconstruction_blacklist)
		data["loaded_item"] = current_item
		data["already_deconstructed"] = !!LAZYACCESS(stored_research.deconstructed_items, current_item.type)
		var/list/points = techweb_item_point_check(current_item)
		data["recoverable_points"] = techweb_point_display_generic(points)

		var/list/boostable_nodes = techweb_item_unlock_check(current_item)
		for(var/id in boostable_nodes)
			var/datum/techweb_node/unlockable_node = SSresearch.techweb_node_by_id(id)
			var/list/node_data = list()
			node_data["node_name"] = unlockable_node.display_name
			node_data["node_id"] = unlockable_node.id
			node_data["node_hidden"] = !!LAZYACCESS(stored_research.hidden_nodes, unlockable_node.id)
			data["node_data"] += list(node_data)
	else
		data["loaded_item"] = null
	return data

/obj/machinery/rnd/destructive_analyzer/tgui_static_data(mob/user)
	var/list/data = list()
	data["research_point_id"] = DESTRUCTIVE_ANALYZER_DESTROY_POINTS
	return data

/obj/machinery/rnd/destructive_analyzer/proc/ui_act_eject_item(datum/act/op/A)
	var/mob/user = A.actor
	var/current_item = loaded_item
	if(busy)
		balloon_alert(user, "already busy!")
		return TRUE
	if(current_item)
		unload_item()
		return TRUE

/obj/machinery/rnd/destructive_analyzer/proc/ui_act_deconstruct(datum/act/op/A, deconstruct_id)
	var/mob/user = A.actor
	if(!user_try_decon_id(deconstruct_id))
		balloon_alert(user, "analysis failed!")
	return TRUE

///Drops the loaded item where it can and nulls it.
/obj/machinery/rnd/destructive_analyzer/proc/unload_item()
	var/obj/item/current_item = own_take(src, nameof(loaded_item))
	if(!current_item)
		return FALSE
	current_item.forceMove(drop_location())
	return TRUE

/**
 * Destroys an item by going through all its contents (including itself) and calling destroy_item_individual
 * Args:
 * gain_research_points - Whether deconstructing each individual item should check for research points to boost.
 */
/obj/machinery/rnd/destructive_analyzer/proc/destroy_item(gain_research_points = FALSE)
	var/obj/item/current_item = loaded_item
	if(!current_item || QDELETED(src))
		return FALSE
	set_busy(TRUE)
	after(src, 2.4 SECONDS, PROC_REF(reset_busy))
	use_power(active_power_usage)
	// Destroy items inside
	own_take(src, nameof(loaded_item)) // destroyed below
	var/list/destructing = list()
	destructing += current_item
	for(var/atom/movable/AM in contents_of(current_item))
		AM.forceMove(get_turf(src))
		destructing += AM
	for(var/atom/thing_destroying in destructing) // For all contents and itself
		destroy_item_individual(thing_destroying, gain_research_points)
	// feedback
	play_sfx(src, SFX_MACHINES_DESTRUCTIVE_ANALYZER)
	return TRUE

/**
 * Destroys the individual provided item
 * Args:
 * thing - The thing being destroyed. Generally an object, but it can be a mob too, such as intellicards and pAIs.
 * gain_research_points - Whether deconstructing this should give research points to the stored techweb, if applicable.
 */
/obj/machinery/rnd/destructive_analyzer/proc/destroy_item_individual(obj/item/thing, gain_research_points = FALSE)
	if(isliving(thing))
		var/mob/living/mob_thing = thing
		var/turf/turf_to_dump_to = get_turf(src)
		log_and_message_admins("made an attempt to kill [mob_thing] in a destructive analyzer was made at [ADMIN_VERBOSEJMP(turf_to_dump_to)]")
		visible_message(span_warning("A loud buzz sounds out from \the [src] as it rejects and spits out \the [mob_thing]!"))
		mob_thing.forceMove(turf_to_dump_to)
		return
	//Safety.
	if(is_type_in_list(thing, GLOB.item_deconstruction_blacklist))
		var/turf/turf_to_dump_to = get_turf(src)
		log_and_message_admins("made an attempt to destroy [thing] in a destructive analyzer was made at [ADMIN_VERBOSEJMP(turf_to_dump_to)]")
		visible_message(span_warning("A loud buzz sounds out from \the [src] as it rejects and spits out \the [thing]!"))
		thing.forceMove(turf_to_dump_to)
		return

	//Perform experiment
	techweb_item_generate_points(thing, stored_research)
	PUBLISH_LEGACY(src, /datum/notice/machinery_destructive_scan, thing)

	//Finally, let's add it to the material silo, if applicable.
	var/datum/material_container/materials = get_silo_material_container_datum(FALSE)
	if(materials)
		materials.insert_item(thing, decon_mod, src, FALSE)
	consumed(thing, src)

/**
 * Attempts to destroy the loaded item using a provided research id.
 * Args:
 * id - The techweb ID node that we're meant to unlock if applicable.
 */
/obj/machinery/rnd/destructive_analyzer/proc/user_try_decon_id(id)
	var/obj/item/current_item = loaded_item
	if(!istype(current_item))
		return FALSE
	if(LAZYLEN(current_item.contents))
		visible_message(span_notice("A warning blares from \the [src]: The [current_item] still has items inside it!"))
		return FALSE
	if(isnull(id))
		return FALSE

	if(id == DESTRUCTIVE_ANALYZER_DESTROY_POINTS)
		if(!destroy_item(gain_research_points = TRUE))
			return FALSE
		return TRUE

	var/datum/techweb_node/node_to_discover = SSresearch.techweb_node_by_id(id)
	if(!istype(node_to_discover))
		return FALSE
	if(!destroy_item())
		return FALSE
	stored_research.unhide_node(node_to_discover)
	return TRUE

#undef DESTRUCTIVE_ANALYZER_DESTROY_POINTS

