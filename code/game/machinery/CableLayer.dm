/obj/machinery/cablelayer
	name = "automatic cable layer"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "pipe_d"
	density = TRUE
	var/obj/structure/cable/last_piece
	var/obj/item/stack/cable_coil/cable
	var/max_cable = 100
	on = 0

/obj/machinery/cablelayer/Initialize(mapload)
	rel_set(src, nameof(cable), new /obj/item/stack/cable_coil(src, max_cable))
	. = ..()

/obj/machinery/cablelayer/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	layCable(loc,direction)

/obj/machinery/cablelayer/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/cablelayer_load,
		/datum/interaction/machine_item/cablelayer_swallow,
		/datum/interaction/machine_hand/ungated/cablelayer_toggle,
	)
	..()

/// Load a coil into the reel.
/datum/interaction/machine_item/cablelayer_load
	id = "cablelayer_load"
	name = "Load cable"
	held_type = /obj/item/stack/cable_coil
	effect = /obj/machinery/cablelayer/proc/interaction_load

/obj/machinery/cablelayer/proc/interaction_load(mob/user, obj/item/stack/cable_coil/O, datum/interaction/interaction)
	var/result = load_cable(O)
	if(!result)
		to_chat(user, span_warning("\The [src]'s cable reel is full."))
	else
		to_chat(user, "You load [result] lengths of cable into [src].")
	return TRUE

/// Old attackby: any other item did nothing and the base attackby was never reached.
/datum/interaction/machine_item/cablelayer_swallow
	id = "cablelayer_swallow"
	name = "Use"
	held_type = /obj/item
	effect = /atom/proc/interaction_swallow

/// Old attack_hand (never called ..()): toggle the layer on/off.
/datum/interaction/machine_hand/ungated/cablelayer_toggle
	id = "cablelayer_toggle"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	requires = list(REQ_REACH_ADJACENT, REQ_ON(PRED_TARGET, /obj/machinery/cablelayer/proc/has_cable_or_on, "doesn't have any cable loaded"))
	effect = /obj/machinery/cablelayer/proc/interaction_toggle

/obj/machinery/cablelayer/proc/has_cable_or_on(mob/actor, atom/target, obj/item/held)
	return cable || on

/obj/machinery/cablelayer/proc/interaction_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	set_on(!on)
	act_message(user, src, MSG_SELF("You switch %T% [on? "on" : "off"]"), MSG_OTHERS("%U% [!on?"dea":"a"]ctivates %T%."))
	return TRUE

/obj/machinery/cablelayer/wirecutter_act(mob/user, obj/item/tool)
	if(!cable || !cable.get_amount())
		to_chat(user, span_warning("There's no more cable on the reel."))
		return ITEM_INTERACT_BLOCKING
	open_request(src, /datum/prompt/number/cablelayer_cut, PROC_REF(cable_length_entered), answerer = user, default = min(cable.get_amount(), 30), tool = tool)
	return ITEM_INTERACT_SUCCESS

/// How much cable to cut off the layer's reel. Re-checked: next to the layer and able.
/datum/prompt/number/cablelayer_cut
	title = "Cut cable"
	question = "Please specify the length of cable to cut"
	ask_flags = ASK_ADJACENT | ASK_CAPABLE
	timeout = 0
	step = 1
	var/obj/item/tool

CAPABILITIES(/datum/prompt/number/cablelayer_cut)
	ref_one(nameof(tool), /obj/item)

/datum/prompt/number/cablelayer_cut/prepare(datum/act/A)
	..()
	var/obj/item/captured_tool = tool
	rel_clear(src, nameof(tool))
	rel_set(src, nameof(tool), captured_tool)

/datum/prompt/number/cablelayer_cut/recheck_extra()
	return QDELETED(tool) ? "gone" : null

/obj/machinery/cablelayer/proc/cable_length_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/number/cablelayer_cut/ask = A.answer
	var/obj/item/tool = ask.tool
	if(!cable)
		return
	var/amount = min(ask.value, cable.get_amount(), 30)
	if(amount)
		playsound(src, tool.usesound, 50, TRUE)
		use_cable(amount)
		var/obj/item/stack/cable_coil/cut_cable = new(get_turf(src))
		cut_cable.set_amount(amount)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/cablelayer/examine(mob/user)
	. = ..()
	. += "[src]'s cable reel has [cable ? cable.get_amount() : 0] length\s left."

/obj/machinery/cablelayer/proc/load_cable(obj/item/stack/cable_coil/CC)
	if(istype(CC) && CC.get_amount())
		var/cur_amount = cable ? cable.get_amount() : 0
		var/to_load = max(max_cable - cur_amount,0)
		if(to_load)
			to_load = min(CC.get_amount(), to_load)
			if(!cable)
				rel_set(src, nameof(cable), new /obj/item/stack/cable_coil(src, to_load))
			else
				cable.add(to_load)
			CC.use(to_load)
			return to_load
		else
			return 0
	return

/obj/machinery/cablelayer/proc/use_cable(amount)
	if(!cable || cable.get_amount() < 1)
		visible_message("A red light flashes on \the [src].")
		return
	cable.use(amount)
	if(QDELETED(cable))
		own_take(src, nameof(cable))
	return 1

/obj/machinery/cablelayer/proc/reset()
	rel_clear(src, nameof(last_piece))

/obj/machinery/cablelayer/proc/dismantleFloor(turf/new_turf)
	if(istype(new_turf, /turf/simulated/floor))
		var/turf/simulated/floor/T = new_turf
		if(!T.is_plating())
			T.make_plating(!(T.broken || T.burnt))
	return new_turf.is_plating()

/obj/machinery/cablelayer/proc/layCable(turf/new_turf,M_Dir)
	if(!on)
		return reset()
	else
		dismantleFloor(new_turf)
	if(!istype(new_turf) || !dismantleFloor(new_turf))
		return reset()
	var/fdirn = turn(M_Dir,180)
	for(var/obj/structure/cable/LC in turf_contents_of_type(new_turf, /obj/structure/cable))		// check to make sure there's not a cable there already
		if(LC.d1 == fdirn || LC.d2 == fdirn)
			return reset()
	if(!use_cable(1))
		return reset()
	var/obj/structure/cable/NC = new(new_turf)
	NC.cableColor("red")
	NC.set_d1(0)
	NC.set_d2(fdirn)
	changed(NC)

	if(last_piece() && last_piece().d2 != M_Dir)
		last_piece().set_d1(min(last_piece().d2, M_Dir))
		last_piece().set_d2(max(last_piece().d2, M_Dir))
		changed(last_piece())
		last_piece().power_register()
	NC.power_register()
	rel_set(src, nameof(last_piece), NC)
	return 1

/obj/machinery/cablelayer/ownership()
	. = ..()
	. += owns(nameof(cable), policy = OWN_CONTAINED)

/// last piece (a relation view: it reads null once the target is deleted).
/obj/machinery/cablelayer/proc/last_piece() as /obj/structure/cable
	return last_piece
