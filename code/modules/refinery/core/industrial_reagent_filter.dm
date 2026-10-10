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

TRACKED(/obj/machinery/reagent_refinery/filter, filter_side)

CAPABILITIES(/obj/machinery/reagent_refinery/filter)
	after_init(0, then(PROC_REF(apply_default_parts)))
	climb()
	op("reagent_filter_use", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_reagent_filter_use)))
	op("reagent_filter_set_filter", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Set Filter Chemical"), needs(req_adjacent(), req_capable(), req(PROC_REF(dq_actor_can_act_holds), because = PROC_REF(dq_actor_can_act_refusal))), then(PROC_REF(interaction_reagent_filter_set_filter)))
	op("reagent_filter_flip", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Flip Filter Direction"), needs(req_adjacent(), req_capable(), req(PROC_REF(dq_actor_can_act_holds), because = PROC_REF(dq_actor_can_act_refusal))), then(PROC_REF(interaction_reagent_filter_flip)))

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

/obj/machinery/reagent_refinery/filter/draw(datum/look/look)
	..()
	var/datum/reagents/R = reagents
	look.watch(R) // its level and colour are tracked on the holder
	var/drawn_state = look.state("filter_[filter_side == 1 ? "r" : "l"]")
	if(R?.total_volume > 0)
		look.overlay(look_overlay_image(icon, "[drawn_state]_r", color = R.tint, dir = dir))

/obj/machinery/reagent_refinery/filter/proc/interaction_reagent_filter_use(datum/act/op/A)
	var/mob/user = A.actor
	set_filter(user)
	return TRUE

/obj/machinery/reagent_refinery/filter/proc/get_filter_side()
	return filter_side

/// A filter feeds a hub from its main line and from its filtered side.
/obj/machinery/reagent_refinery/filter/hub_intake(back)
	var/side_dir = turn(dir, filter_side == 1 ? 270 : 90)
	return side_dir == back || dir == back

/// Requirement (was REQ_* dq_actor_can_act): the legacy check answers TRUE to pass.
/obj/machinery/reagent_refinery/filter/proc/dq_actor_can_act_holds(datum/act/op/A)
	var/answer = dq_actor_can_act(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why dq_actor_can_act_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/reagent_refinery/filter/proc/dq_actor_can_act_refusal(datum/act/op/A)
	var/answer = dq_actor_can_act(A.actor, src, A.held)
	return istext(answer) ? answer : "you can't do that right now"

/obj/machinery/reagent_refinery/filter/proc/interaction_reagent_filter_set_filter(datum/act/op/A)
	var/mob/user = A.actor
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

/obj/machinery/reagent_refinery/filter/proc/interaction_reagent_filter_flip(datum/act/op/A)
	var/mob/user = A.actor
	flip_filter(user)
	return TRUE

/obj/machinery/reagent_refinery/filter/proc/flip_filter(mob/user)
	if (user.stat || user.restrained() || anchored)
		return

	set_filter_side(filter_side * -1)

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
