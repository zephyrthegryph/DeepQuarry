/**********************Mineral stacking unit console**************************/

/obj/machinery/mineral/stacking_unit_console
	name = "stacking machine console"
	icon = 'icons/obj/machines/mining_machines.dmi'
	icon_state = "console"
	layer = ABOVE_WINDOW_LAYER
	density = TRUE
	anchored = TRUE
	var/tmp/obj/machinery/mineral/stacking_machine/machine

/obj/machinery/mineral/stacking_unit_console/Initialize(mapload)
	. = ..()
	rel_set(src, "machine", locate_in_list(range(5,src), /obj/machinery/mineral/stacking_machine))
	if (machine())
		rel_set(machine(), "console", src)
	else
		//Silently failing and causing mappers to scratch their heads while runtiming isn't ideal.
		stack_trace(span_danger("Warning: Stacking machine console at [src.x], [src.y], [src.z] could not find its machine!"))
		return INITIALIZE_HINT_QDEL

/obj/machinery/mineral/stacking_unit_console/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/stacking_console_use,
	)
	..()

/datum/interaction/machine_hand/ungated/stacking_console_use
	id = "stacking_console_use"
	name = "Use"
	effect = /obj/machinery/mineral/stacking_unit_console/proc/interaction_use

/obj/machinery/mineral/stacking_unit_console/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	tgui_interact(user)
	return TRUE

/obj/machinery/mineral/stacking_unit_console/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "MiningStackingConsole", name)
		ui.open()

/obj/machinery/mineral/stacking_unit_console/tgui_data(mob/user)
	var/list/data = ..()

	var/list/stacktypes = list()
	for(var/stacktype in machine().stack_storage)
		if(LAZYACCESS(machine().stack_storage, stacktype) > 0)
			stacktypes.Add(list(list(
				"type" = stacktype,
				"amt" = LAZYACCESS(machine().stack_storage, stacktype),
			)))
	data["stacktypes"] = stacktypes
	data["stackingAmt"] = machine().stack_amt
	return data

/obj/machinery/mineral/stacking_unit_console/tgui_act(action, list/params, datum/tgui/ui)
	if(..())
		return TRUE

	switch(action)
		if("change_stack")
			machine().stack_amt = clamp(text2num(params["amt"]), 1, 50)
			machine().wake_mining()
			. = TRUE

		if("release_stack")
			var/stack = params["stack"]
			if(LAZYACCESS(machine().stack_storage, stack) > 0)
				var/stacktype = LAZYACCESS(machine().stack_paths, stack)
				new stacktype(get_turf(machine().output_marker()), LAZYACCESS(machine().stack_storage, stack))
				var/obj/machinery/mineral/stacking_machine/stacker = machine()
				LAZYSET(stacker.stack_storage, stack, 0)
			. = TRUE

	add_fingerprint(ui.user)

/**********************Mineral stacking unit**************************/

/obj/machinery/mineral/stacking_machine
	name = "stacking machine"
	icon = 'icons/obj/machines/mining_machines.dmi'
	icon_state = "stacker"
	density = TRUE
	anchored = TRUE
	var/tmp/obj/machinery/mineral/stacking_unit_console/console
	var/tmp/obj/machinery/mineral/input
	var/tmp/obj/machinery/mineral/output
	var/list/stack_storage
	var/list/stack_paths
	var/stack_amt = 50; // Amount to stack before releassing

/obj/machinery/mineral/stacking_machine/Initialize(mapload)
	. = ..()
	// stack_paths holds type paths (material id -> stack type), not instances.
	for(var/stack_path in (subtypesof(/obj/item/stack/material) - typesof(/obj/item/stack/material/cyborg)))
		var/obj/item/stack/material/S = stack_path
		var/s_matname = initial(S.default_type)
		LAZYSET(stack_storage, s_matname, 0)
		LAZYSET(stack_paths, s_matname, stack_path)

	for (var/dir in GLOB.cardinal)
		rel_set(src, "input", locate(/obj/machinery/mineral/input, get_step(src, dir)))
		if(src.input_marker()) break
	for (var/dir in GLOB.cardinal)
		rel_set(src, "output", locate(/obj/machinery/mineral/output, get_step(src, dir)))
		if(src.output_marker()) break
	watch_input(input_marker())

/// Phase 2: drops the turf watch on its input marker.
/obj/machinery/mineral/stacking_machine/lifecycle_dematerialize()
	. = ..()
	unwatch_input(input_marker())

/obj/machinery/mineral/stacking_machine/proc/toggle_speed(forced)
	if(forced)
		set_speed_process(forced)
	else
		set_speed_process(!speed_process) // switching gears
	if(speed_process) // high gear
		MACHINE_SLEEP(src)
		om_task_periodic(src, PERIODIC_FAST)
	else // low gear
		om_task_periodic_stop(src)
		MACHINE_WAKE(src)

/obj/machinery/mineral/stacking_machine/machine_step()
	var/did_work = FALSE
	if (src.output_marker() && src.input_marker())
		var/turf/T = get_turf(input_marker())
		for(var/obj/item/O in turf_contents_of_type(T, /obj/item))
			if(!O)
				continue
			did_work = TRUE
			if(istype(O,/obj/item/stack/material))
				var/obj/item/stack/material/S = O
				var/matname = S.material.name
				if(!isnull(LAZYACCESS(stack_storage, matname)))
					LAZYADDASSOC(stack_storage, matname, S.get_amount())
					qdel(S)
				else
					O.forceMove(output_marker().loc)
			else
				O.forceMove(output_marker().loc)

	//Output amounts that are past stack_amt.
	for(var/sheet in stack_storage)
		if(LAZYACCESS(stack_storage, sheet) >= stack_amt)
			did_work = TRUE
			var/stacktype = LAZYACCESS(stack_paths, sheet)
			new stacktype (get_turf(output_marker()), stack_amt)
			stack_storage[sheet] -= stack_amt
	if(!did_work)
		return PROCESS_KILL

/// Accessor for the input var.
/obj/machinery/mineral/stacking_machine/proc/input_marker() as /obj/machinery/mineral
	return input

/// Accessor for the output var.
/obj/machinery/mineral/stacking_machine/proc/output_marker() as /obj/machinery/mineral
	return output

/// Accessor for the console var.
/obj/machinery/mineral/stacking_machine/proc/console() as /obj/machinery/mineral/stacking_unit_console
	return console

/// Accessor for the machine var.
/obj/machinery/mineral/stacking_unit_console/proc/machine() as /obj/machinery/mineral/stacking_machine
	return machine
