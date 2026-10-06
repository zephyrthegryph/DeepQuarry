/obj/machinery/reagent_refinery/filter
	name = "Industrial Chemical Filter"
	desc = "Identifies and extracts specific chemicals."
	icon_state = "filter_l"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 5
	active_power_usage = 50
	circuit = /obj/item/circuitboard/industrial_reagent_filter
	VAR_PROTECTED/filter_side = -1 // L
	VAR_PRIVATE/filter_reagent_id = ""

	possible_transfer_amounts = list(0,1,2,5,10,15,20,25,30,40,60)
	default_max_vol = 60 // smoll to match pipes

/obj/machinery/reagent_refinery/filter/alt
	filter_side = 1 // R
	icon_state = "filter_r"

CAPABILITIES(/obj/machinery/reagent_refinery/filter)
	climb()

/obj/machinery/reagent_refinery/filter/Initialize(mapload)
	. = ..()
	default_apply_parts()
	// Update neighbours and self for state
	update_neighbours()
	update_icon()

/obj/machinery/reagent_refinery/filter/refinery_step()
	if(!anchored)
		return

	power_change()
	if(!operable())
		return

	// extract and filter side products
	if(filter_reagent_id == "")
		return // MUST BE SET
	if(amount_per_transfer_from_this <= 0)
		return
	if(filter_reagent_id != "-1" || filter_reagent_id == "-2") // disabled check, and "all" check
		var/check_dir = 0
		if(filter_side == 1)
			check_dir = turn(src.dir, 270)
		else
			check_dir = turn(src.dir, 90)
		var/obj/machinery/reagent_refinery/filter_target = locate_within(get_step(get_turf(src),check_dir), /obj/machinery/reagent_refinery)
		if(filter_target && reagents.total_volume > 0)
			transfer_tank( reagents, filter_target, check_dir, filter_reagent_id == "-2" ? "" : filter_reagent_id)
	// dump reagents to next refinery machine if all of the target reagent has been filtered out
	if(filter_reagent_id != "-2") // "all" filter option pushes it all out the side path
		var/obj/machinery/reagent_refinery/target = locate_within(get_step(get_turf(src),dir), /obj/machinery/reagent_refinery)
		if(target && reagents.total_volume > 0)
			transfer_tank( reagents, target, dir)

DECLARE_APPEARANCE_PROC(/obj/machinery/reagent_refinery/filter, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/reagent_refinery/filter/appearance_overlays()
	. = list()
	icon_state = "filter_[filter_side == 1 ? "r" : "l"]"

	if(reagents && reagents.total_volume > 0)
		var/image/filling = image(icon, loc, "[icon_state]_r",dir = dir)
		filling.color = reagents.get_color()
		. += filling

/obj/machinery/reagent_refinery/filter/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/reagent_filter_use,
		/datum/interaction/machine_verb/reagent_filter_set_filter,
		/datum/interaction/machine_verb/reagent_filter_flip,
	)
	..()

/datum/interaction/machine_hand/ungated/reagent_filter_use
	id = "reagent_filter_use"
	name = "Use"
	effect = /obj/machinery/reagent_refinery/filter/proc/interaction_reagent_filter_use

/obj/machinery/reagent_refinery/filter/proc/interaction_reagent_filter_use(mob/user, obj/item/held, datum/interaction/interaction)
	set_filter(user)
	return TRUE

/obj/machinery/reagent_refinery/filter/proc/get_filter_side()
	return filter_side

/datum/interaction/machine_verb/reagent_filter_set_filter
	id = "reagent_filter_set_filter"
	name = "Set Filter Chemical"
	effect = /obj/machinery/reagent_refinery/filter/proc/interaction_reagent_filter_set_filter

/obj/machinery/reagent_refinery/filter/proc/interaction_reagent_filter_set_filter(mob/user, obj/item/held, datum/interaction/interaction)
	set_filter(user)
	return TRUE

/obj/machinery/reagent_refinery/filter/proc/set_filter(mob/user)
	if (user.stat || user.restrained())
		return
	var/list/selection_data = filter_selection_data()
	open_request(src, /datum/prompt/choice/refinery_filter, PROC_REF(filter_selected), answerer = user, question = "Select chemical to filter. It is currently [selection_data["filter"]].", title = "Chemical Select", choices = selection_data["choices"])

/obj/machinery/reagent_refinery/filter/proc/filter_selection_data()
	// Get a list of reagents currently inside!
	var/list/tgui_list = list("Disabled" = "","Bypass" = "-1","All" = "-2")
	for(var/datum/reagent/R in reagents.reagent_list)
		if(R)
			tgui_list[R.name] = R.id

	var/filter = "disabled"
	if(filter_reagent_id == "-1")
		filter = "filtering out nothing"
	else if(filter_reagent_id == "-2")
		filter = "filtering out everything"
	else if(filter_reagent_id != "")
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[filter_reagent_id]
		filter = "filtering [R.name]"
	return list("choices" = tgui_list, "filter" = filter)

/datum/prompt/choice/refinery_filter
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/refinery_filter/recheck_extra()
	if(QDELETED(owner) || QDELETED(answerer))
		return "gone"
	if(answerer.stat || answerer.restrained())
		return "cannot use"

/obj/machinery/reagent_refinery/filter/proc/filter_selected(datum/act/request/context)
	if(isnull(context.request.value) || context.request.last_error == "gone")
		return
	SStgui.update_uis(src)
	if(context.answer)
		apply_filter_selection(context.answer.value)

/obj/machinery/reagent_refinery/filter/proc/apply_filter_selection(select)
	var/list/selection_data = filter_selection_data()
	var/list/tgui_list = selection_data["choices"]
	// Select if possible
	if(select && select != "")
		filter_reagent_id = tgui_list[select]

/datum/interaction/machine_verb/reagent_filter_flip
	id = "reagent_filter_flip"
	name = "Flip Filter Direction"
	effect = /obj/machinery/reagent_refinery/filter/proc/interaction_reagent_filter_flip

/obj/machinery/reagent_refinery/filter/proc/interaction_reagent_filter_flip(mob/user, obj/item/held, datum/interaction/interaction)
	flip_filter(user)
	return TRUE

/obj/machinery/reagent_refinery/filter/proc/flip_filter(mob/user)
	if (user.stat || user.restrained() || anchored)
		return

	filter_side *= -1
	update_icon()

/obj/machinery/reagent_refinery/filter/handle_transfer(atom/origin_machine, datum/reagents/RT, source_forward_dir, transfer_rate, filter_id = "")
	// pumps, furnaces, splitters and filters can only be FED in a straight line
	if(source_forward_dir != dir)
		return 0
	. = ..(origin_machine, RT, source_forward_dir, transfer_rate, filter_id)

/obj/machinery/reagent_refinery/filter/examine(mob/user, infix, suffix)
	. = ..()
	var/filter = "disabled"
	if(filter_reagent_id == "-1")
		filter = "filtering out nothing"
	else if(filter_reagent_id == "-2")
		filter = "filtering out everything"
	else if(filter_reagent_id != "")
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[filter_reagent_id]
		filter = "filtering [R.name]"
	. += "The meter shows [reagents.total_volume]u / [reagents.maximum_volume]u. It is currently [filter]. At a rate of [amount_per_transfer_from_this]u."
	tutorial(REFINERY_TUTORIAL_INPUT|REFINERY_TUTORIAL_FILTER, .)
