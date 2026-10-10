/obj/machinery/pipelayer
	maintenance_flags = MACHINE_MAINT_PANEL
	name = "automatic pipe layer"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "pipe_d"
	density = TRUE
	circuit = /obj/item/circuitboard/pipelayer
	var/turf/old_turf		// Last turf we were on.
	var/old_dir				// Last direction we were facing.
	on = 0				// Pipelaying online?
	var/a_dis = 0			// Auto-dismantling - If enabled it will remove floor tiles
	var/P_type = null		// Currently selected pipe type
	var/P_type_t = ""		// Name of currently selected pipe type
	var/max_metal = 50		// Max capacity for internal metal storage
	var/metal = 0			// Current amount in internal metal storage
	var/pipe_cost = 0.25	// Cost in steel for each pipe.
	var/obj/item/tool/wrench/W // Internal wrench used for wrenching down the pipes
	var/static/list/Pipes = list(
		"regular pipes" = /obj/machinery/atmospherics/pipe/simple,
		"scrubbers pipes" = /obj/machinery/atmospherics/pipe/simple/hidden/scrubbers,
		"supply pipes" = /obj/machinery/atmospherics/pipe/simple/hidden/supply,
		"heat exchange pipes" = /obj/machinery/atmospherics/pipe/simple/heat_exchanging
	)

TRACKED(/obj/machinery/pipelayer, a_dis)

MSG_DEF_SELF(pipelayer/no_metal, "It doesn't work without metal.")
MSG_DEF_SELF(pipelayer/empty, "It is empty.")
MSG_DEF_SELF(pipelayer/thin_pipe, "It doesn't contain enough steel to recycle.")
MSG_DEF_SELF(pipelayer/full, "It is full.")
MSG_DEF_SELF(pipelayer/not_steel, "It only takes steel.")
MSG_DEF(pipelayer/recycled, "You recycle %I%.", "%U% recycles %I%.")
MSG_DEF(pipelayer/loaded, "You load metal into %T%.", "%U% has loaded metal into %T%.")
MSG_DEF(pipelayer/switched, "You switch %T%.", "%U% switches %T%.")
MSG_DEF(pipelayer/dismantling, "You switch its auto-dismantling.", "%U% switches the auto-dismantling of %T%.")

CAPABILITIES(/obj/machinery/pipelayer)
	owns_one(nameof(W), starts = /obj/item/tool/wrench)
	part_replacement()
	examine_line(PROC_REF(status_text))
	op("toggle", hand(), label("Toggle"), wait(0), when(PROC_REF(panel_shut)), when(cond_not(req(/obj/item))), needs(req_bool(PROC_REF(can_run), because = MSG(pipelayer/no_metal))),
		says(MSG(pipelayer/switched)), then(PROC_REF(toggled)))
	op("eject", hand(), label("Eject metal"), priority(OP_PRIORITY_PART), when(PROC_REF(panel_is_open)), when(cond_not(req(/obj/item))), needs(req_bool(PROC_REF(has_metal), because = MSG(pipelayer/empty))),
		asks(/datum/prompt/yes_no, fields = list("question" = "Do you want to eject all the metal?", "title" = "Eject?", "timeout" = 0)), then(PROC_REF(eject_answered)))
	op("recycle", item(/obj/item/pipe), label("Recycle pipe"), wait(0),
		needs(req_bool(PROC_REF(pipe_has_steel), because = MSG(pipelayer/thin_pipe)), req_bool(PROC_REF(room_for_pipe), because = MSG(pipelayer/full))),
		says(MSG(pipelayer/recycled)), then(PROC_REF(recycled)))
	op("load", item(/obj/item/stack/material), label("Load metal"), wait(0), needs(req_bool(PROC_REF(held_steel), because = MSG(pipelayer/not_steel)), req_bool(PROC_REF(room_for_sheet), because = MSG(pipelayer/full))),
		says(MSG(pipelayer/loaded)), then(PROC_REF(loaded)))
	op("pipe_type", tool(TOOL_WRENCH), label("Choose pipe type"), wait(0), when(PROC_REF(panel_shut)),
		asks(/datum/prompt/choice, fields = list("question" = "Choose pipe type", "title" = "Pipe type", "choices" = computed(PROC_REF(pipe_choices)), "timeout" = 0)), then(PROC_REF(pipe_type_chosen)))
	op("auto_dismantle", tool(TOOL_CROWBAR), label("Toggle auto-dismantling"), wait(0), when(PROC_REF(panel_shut)), toggles(nameof(a_dis)), says(MSG(pipelayer/dismantling)))
	op("dismantle", tool(TOOL_CROWBAR), label("Dismantle"), priority(OP_PRIORITY_TAKE_OUT), when(PROC_REF(panel_is_open)), then(PROC_REF(dismantled)))
	default_parts()


/obj/machinery/pipelayer/RefreshParts()
	var/mb_rating = get_part_rating(/obj/item/stock_parts/matter_bin)
	max_metal = mb_rating * initial(max_metal)

/obj/machinery/pipelayer/dismantle()
	eject_metal()
	..()

// Whenever we move, if enabled try and lay pipe
/obj/machinery/pipelayer/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()

	if(on && a_dis)
		dismantleFloor(old_turf())
	layPipe(old_turf(), direction, old_dir)

	rel_set(src, nameof(old_turf), loc)
	old_dir = turn(direction, 180)

/obj/machinery/pipelayer/proc/panel_shut(datum/act/op/A)
	return !panel_open

/obj/machinery/pipelayer/proc/panel_is_open(datum/act/op/A)
	return panel_open

/// It runs only with metal (switching it off always works).
/obj/machinery/pipelayer/proc/can_run(datum/act/A)
	return on || metal // ALLOW(reads): the store is read when it is switched, never from a cached menu

/obj/machinery/pipelayer/proc/has_metal(datum/act/A)
	return metal >= 1 // ALLOW(reads): the store is read when it is touched, never from a cached menu

/obj/machinery/pipelayer/proc/toggled(datum/act/op/A)
	set_on(!on)
	rel_set(src, nameof(old_turf), get_turf(src))
	old_dir = dir
	return OP_OK

/obj/machinery/pipelayer/proc/eject_answered(datum/act/op/A)
	var/datum/prompt/yes_no/answer = A.answer
	if(!answer?.value)
		return OP_OK
	var/amount_ejected = eject_metal()
	to_chat(A.actor, span_notice("You remove [amount_ejected] sheet\s of [MAT_STEEL] from [src]."))
	return OP_OK

/// A pipe is worth its steel (a free dispenser pipe is not: no infinite steel).
/obj/machinery/pipelayer/proc/pipe_has_steel(datum/act/op/A)
	var/obj/item/pipe/P = A.held
	return istype(P) && P.material_total >= pipe_cost * SHEET_MATERIAL_AMOUNT // ALLOW(reads): read when the tool or item is used on it, never from a cached menu or look

/obj/machinery/pipelayer/proc/room_for_pipe(datum/act/A)
	return metal + pipe_cost <= max_metal // ALLOW(reads): the store is read when a pipe is fed in, never from a cached menu

/obj/machinery/pipelayer/proc/recycled(datum/act/op/A)
	if(!consume(A.held, A.actor))
		return OP_FAILED
	metal += pipe_cost
	return OP_OK

/obj/machinery/pipelayer/proc/held_steel(datum/act/op/A)
	return istype(A.held, /obj/item/stack/material/steel)

/obj/machinery/pipelayer/proc/room_for_sheet(datum/act/A)
	return round(metal) < max_metal // ALLOW(reads): the store is read when sheets are fed in, never from a cached menu

/obj/machinery/pipelayer/proc/loaded(datum/act/op/A)
	load_metal(A.held)
	return OP_OK

/obj/machinery/pipelayer/proc/pipe_choices(datum/act/A)
	return Pipes

/obj/machinery/pipelayer/proc/pipe_type_chosen(datum/act/op/A)
	var/datum/prompt/choice/answer = A.answer
	P_type_t = answer.value
	P_type = Pipes[P_type_t]
	to_chat(A.actor, span_notice("You set [src] to manufacture [P_type_t]."))
	return OP_OK

/obj/machinery/pipelayer/proc/dismantled(datum/act/op/A)
	return dismantle() ? OP_OK : OP_FAILED

/obj/machinery/pipelayer/proc/status_text(datum/act/eval/A)
	return "[src] has [metal] sheet\s, is set to produce [P_type_t], and auto-dismantling is [!a_dis?"de":""]activated."

/obj/machinery/pipelayer/proc/reset()
	set_on(0)
	return

/obj/machinery/pipelayer/proc/load_metal(obj/item/stack/MM)
	if(istype(MM) && MM.get_amount())
		var/cur_amount = metal
		var/to_load = max(max_metal - round(cur_amount),0)
		if(to_load)
			to_load = min(MM.get_amount(), to_load)
			metal += to_load
			MM.use(to_load)
			return to_load
		else
			return 0
	return

/obj/machinery/pipelayer/proc/use_metal(amount)
	if(!metal || metal < amount)
		visible_message("\The [src] deactivates as its metal source depletes.")
		return
	metal -= amount
	return 1

/obj/machinery/pipelayer/proc/eject_metal()
	var/amount_ejected = 0
	while (metal >= 1)
		var/datum/material/M = get_material_by_name(MAT_STEEL)
		var/obj/item/stack/material/S = new M.stack_type(get_turf(src), metal)
		metal -= S.get_amount()
		amount_ejected += S.get_amount()
	return amount_ejected

/obj/machinery/pipelayer/proc/dismantleFloor(turf/new_turf)
	if(istype(new_turf, /turf/simulated/floor))
		var/turf/simulated/floor/T = new_turf
		if(!T.is_plating())
			T.make_plating(!(T.broken || T.burnt))
	return new_turf.is_plating()

/obj/machinery/pipelayer/proc/layPipe(turf/w_turf,M_Dir,old_dir)
	if(!on || !(M_Dir in list(NORTH, SOUTH, EAST, WEST)) || M_Dir==old_dir)
		return reset()
	if(!use_metal(pipe_cost))
		return reset()
	var/fdirn = turn(M_Dir, 180)
	var/obj/machinery/atmospherics/p_type = P_type
	var/p_layer = initial(p_type.piping_layer)
	var/p_dir
	if (fdirn!=old_dir)
		p_dir=old_dir+M_Dir
	else
		p_dir=M_Dir

	var/pi_type = initial(p_type.construction_type)
	var/obj/item/pipe/P = new pi_type(w_turf, p_type, p_dir)
	P.setPipingLayer(p_layer)
	// We used metal to make these, so should be reclaimable!
	P.material_total = pipe_cost * SHEET_MATERIAL_AMOUNT
	P.fasten(null)

	return 1

/// old turf (a relation view: it reads null once the target is deleted).
/obj/machinery/pipelayer/proc/old_turf() as /turf
	return old_turf
