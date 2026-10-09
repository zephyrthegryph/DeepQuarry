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

CAPABILITIES(/obj/machinery/cablelayer)
	op("cablelayer_load", item(/obj/item/stack/cable_coil), priority(OP_PRIORITY_DEFAULT - 1), label("Load cable"), then(PROC_REF(interaction_load)))
	op("use_wirecutter", tool(TOOL_WIRECUTTER), priority(OP_PRIORITY_DEFAULT), wait(0), label("Cut cable"), needs(req_full(nameof(cable), because = MSG(cablelayer/no_cable))),
		asks(/datum/prompt/number/cablelayer_cut, fields = list("default" = computed(PROC_REF(cut_default)))),
		then(PROC_REF(cable_length_entered)))
	op("cablelayer_toggle", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Toggle"), needs(req(PROC_REF(toggle_ready))), then(PROC_REF(interaction_toggle)))

/obj/machinery/cablelayer/proc/interaction_load(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/stack/cable_coil/O = A.held
	var/result = load_cable(O)
	if(!result)
		to_chat(user, span_warning("\The [src]'s cable reel is full."))
	else
		to_chat(user, "You load [result] lengths of cable into [src].")
	return OP_OK

/// The reel is a declared owned item, so test its actual value just as the old adapter did.
/obj/machinery/cablelayer/proc/toggle_ready(datum/act/op/A)
	return cable || on ? null : MSG(cablelayer/toggle_no_cable)

/obj/machinery/cablelayer/proc/interaction_toggle(datum/act/op/A)
	var/mob/user = A.actor
	set_on(!on)
	act_message(user, src, MSG_SELF("You switch %T% [on? "on" : "off"]"), MSG_OTHERS("%U% [!on?"dea":"a"]ctivates %T%."))
	return OP_OK

/// How much cable to cut off the layer's reel. Asked by the wirecutter op (an asks() step: the hand and the place are kept while it is open).
/datum/prompt/number/cablelayer_cut
	title = "Cut cable"
	question = "Please specify the length of cable to cut"
	timeout = 0
	step = 1

MSG_DEF_SELF(cablelayer/no_cable, "There's no more cable on the reel.")

/// The question's starting value: up to 30 lengths.
/obj/machinery/cablelayer/proc/cut_default(datum/act/A)
	return min(cable?.get_amount(), 30)

/// The wirecutter's answer: that much cable comes off the reel.
/obj/machinery/cablelayer/proc/cable_length_entered(datum/act/op/A)
	var/obj/item/tool = A.held
	if(!cable || !isnum(A.answer?.value))
		return OP_OK
	var/amount = min(A.answer.value, cable.get_amount(), 30)
	if(amount > 0)
		playsound(src, tool.usesound, 50, TRUE)
		use_cable(amount)
		var/obj/item/stack/cable_coil/cut_cable = new(get_turf(src))
		cut_cable.set_amount(amount)
	return OP_OK

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
		rel_take(src, nameof(cable))
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

MSG_DEF_SELF(cablelayer/toggle_no_cable, "doesn't have any cable loaded")
