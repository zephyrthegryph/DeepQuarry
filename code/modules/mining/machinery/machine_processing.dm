/**********************Mineral processing unit console**************************/
#define PROCESS_NONE		0
#define PROCESS_SMELT		1
#define PROCESS_COMPRESS	2
#define PROCESS_ALLOY		3

/obj/machinery/mineral/processing_unit_console
	name = "production machine console"
	icon = 'icons/obj/machines/mining_machines.dmi'
	icon_state = "console"
	layer = ABOVE_WINDOW_LAYER
	density = TRUE
	anchored = TRUE

	var/obj/item/card/id/inserted_id	// Inserted ID card, for points

	var/tmp/obj/machinery/mineral/processing_unit/machine
	var/show_all_ores = FALSE

/// Settings changed from the console (ore modes, power): the processing unit re-evaluates.
/obj/machinery/mineral/processing_unit_console/interaction_ran(mob/actor, datum/interaction/interaction)
	. = ..()
	machine()?.wake_mining()

/obj/machinery/mineral/processing_unit_console/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(machine), locate_in_list(range(5, src), /obj/machinery/mineral/processing_unit))
	if (machine())
		rel_set(machine(), nameof(/obj/machinery/bodyscanner::console), src)
	else
		log_mapping("Ore processing machine console at [src.x], [src.y], [src.z] could not find its machine!")
		return INITIALIZE_HINT_QDEL

CAPABILITIES(/obj/machinery/mineral/processing_unit_console)
	// The console's window: an ore's setting, when the button names none, is asked in the op (asks()). A named setting is
	// PROCESS_NONE .. PROCESS_ALLOY (0..3: the defines are file-local, the declaration compiles elsewhere).
	interface("MiningOreProcessingConsole")
	without("ui_open")
	op("toggleSmelting", ui_act("toggleSmelting", arg("ore", schema_text(4096)), arg("set", int(0, 3))),
		asks(/datum/prompt/choice/ore_processing_setting, fields = list("question" = computed(PROC_REF(ore_setting_question)), "title" = "Process Setting", "choices" = list("Smelting", "Compressing", "Alloying", "Nothing")), step = "setting", when = PROC_REF(ore_setting_unnamed)),
		then(PROC_REF(ui_act_togglesmelting)))
	op("logoff", ui_act("logoff"), then(PROC_REF(ui_act_logoff)))
	op("claim", ui_act("claim"), then(PROC_REF(ui_act_claim)))
	op("insert", ui_act("insert"), then(PROC_REF(ui_act_insert)))
	op("showAllOres", ui_act(), then(PROC_REF(ui_act_showallores)))
	op("speed_toggle", ui_act(), then(PROC_REF(ui_act_speed_toggle)))
	op("power", ui_act(), then(PROC_REF(ui_act_power)))
	owns_one(nameof(inserted_id), on_destroy = ON_DESTROY_SPILL)
	op("insert_id", item(/obj/item/card/id), priority(OP_PRIORITY_DEFAULT - 1), label("Insert ID"), then(PROC_REF(interaction_insert_id)))
	op("open_ui_impl", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req(PROC_REF(lets_in_holds), because = PROC_REF(lets_in_refusal))), then(PROC_REF(interaction_open_ui_impl)))

/obj/machinery/mineral/processing_unit_console/proc/interaction_insert_id(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/I = A.held
	if(!powered())
		return TRUE
	if(!inserted_id && move_into(src, nameof(src.inserted_id), I, user))
		SStgui.update_uis(src)
	return TRUE

/obj/machinery/mineral/processing_unit_console/proc/lets_in(mob/actor, atom/target, obj/item/held)
	return allowed(actor)

/// Requirement (was REQ_* lets_in): the legacy check answers TRUE to pass.
/obj/machinery/mineral/processing_unit_console/proc/lets_in_holds(datum/act/op/A)
	var/answer = lets_in(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why lets_in_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/mineral/processing_unit_console/proc/lets_in_refusal(datum/act/op/A)
	var/answer = lets_in(A.actor, src, A.held)
	return istext(answer) ? answer : "access denied"

/obj/machinery/mineral/processing_unit_console/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
	tgui_interact(user)
	return TRUE

/// The window data.
/obj/machinery/mineral/processing_unit_console/ui_data(datum/act/eval/A)
	var/list/data = ..()
	data["showAllOres"] = show_all_ores
	var/list/computed = ui_data_obj_machinery_mineral_processing_unit_console(A.actor, null, null)
	for(var/key in computed)
		data[key] = computed[key]
	return data

/// The computed part of the window data (ui_data()).
/obj/machinery/mineral/processing_unit_console/proc/ui_data_obj_machinery_mineral_processing_unit_console(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["unclaimedPoints"] = machine().points

	if(inserted_id)
		var/datum/money_account/account = get_account(inserted_id.associated_account_number)
		data["has_id"] = TRUE
		data["id"] = list(
			"name" = inserted_id.registered_name,
			"points" = account?.money || 0,
		)
	else
		data["has_id"] = FALSE

	var/list/ores = list()
	for(var/ore in machine().ores_processing)
		if(!machine().ores_stored[ore] && !show_all_ores)
			continue
		var/datum/ore/O = GLOB.ore_data[ore]
		if(!O)
			continue
		ores.Add(list(list(
			"ore" = ore,
			"name" = O.display_name,
			"amount" = machine().ores_stored[ore],
			"processing" = LAZYACCESS(machine().ores_processing, ore) ? LAZYACCESS(machine().ores_processing, ore) : 0,
		)))
	data["ores"] = ores
	data["power"] = machine().active
	data["speed"] = machine().speed_process

	return data

/// The ore button names its setting, or the op asks for it.
/obj/machinery/mineral/processing_unit_console/proc/ore_setting_unnamed(datum/act/op/A)
	return isnull(A.args["set"])

/obj/machinery/mineral/processing_unit_console/proc/ore_setting_question(datum/act/op/A)
	return "What setting do you wish to use for processing [A.args["ore"]]?"

/obj/machinery/mineral/processing_unit_console/proc/ui_act_togglesmelting(datum/act/op/A, ore, set_arg)
	add_fingerprint(A.actor)
	var/new_setting = set_arg
	if(isnull(new_setting))
		switch(A.step_value("setting"))
			if("Nothing")
				new_setting = PROCESS_NONE
			if("Smelting")
				new_setting = PROCESS_SMELT
			if("Compressing")
				new_setting = PROCESS_COMPRESS
			if("Alloying")
				new_setting = PROCESS_ALLOY
			else
				return TRUE
	return apply_ore_processing_setting(ore, new_setting)

/datum/prompt/choice/ore_processing_setting
	timeout = 0

/obj/machinery/mineral/processing_unit_console/proc/apply_ore_processing_setting(ore, new_setting)
	var/obj/machinery/mineral/processing_unit/unit = machine()
	LAZYSET(unit.ores_processing, ore, new_setting)
	. = TRUE

/obj/machinery/mineral/processing_unit_console/proc/ui_act_power(datum/act/op/A)
	add_fingerprint(A.actor)
	machine().set_active(!machine().active)
	return OP_OK

/obj/machinery/mineral/processing_unit_console/proc/ui_act_showallores(datum/act/op/A)
	add_fingerprint(A.actor)
	show_all_ores = !show_all_ores
	return OP_OK

/obj/machinery/mineral/processing_unit_console/proc/ui_act_logoff(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(!inserted_id)
		return
	user.put_in_hands(inserted_id)
	rel_take(src, nameof(inserted_id))
	return TRUE

/obj/machinery/mineral/processing_unit_console/proc/ui_act_claim(datum/act/op/A)
	add_fingerprint(A.actor)
	if(istype(inserted_id))
		if(ACCESS_MINING_STATION in inserted_id.GetAccess())
			var/datum/money_account/account = get_account(inserted_id.associated_account_number)
			if(account?.credit(machine().points, name, "Processed ore proceeds", name))
				machine().points = 0
		else
			to_chat(A.actor, span_warning("Required access not found."))
	return TRUE

/obj/machinery/mineral/processing_unit_console/proc/ui_act_insert(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	var/obj/item/card/id/I = user.get_active_hand()
	if(istype(I))
		move_into(src, nameof(src.inserted_id), I, user)
	else
		to_chat(user, span_warning("No valid ID."))
	return TRUE

/obj/machinery/mineral/processing_unit_console/proc/ui_act_speed_toggle(datum/act/op/A)
	add_fingerprint(A.actor)
	machine().toggle_speed()
	return OP_OK

/**********************Mineral processing unit**************************/

/obj/machinery/mineral/processing_unit
	name = "material processor" //This isn't actually a goddamn furnace, we're in space and it's processing platinum and flammable phoron...
	icon = 'icons/obj/machines/mining_machines.dmi'
	icon_state = "furnace"
	density = TRUE
	anchored = TRUE
	light_range = 3
	var/tmp/obj/machinery/mineral/input
	var/tmp/obj/machinery/mineral/output
	var/tmp/obj/machinery/mineral/console
	var/sheets_per_tick = 10
	var/list/ores_processing
	var/list/ores_stored = list() // ALLOW(instance_list): d: filled in New() with an entry per ore
	active = FALSE

	var/points = 0
	var/points_mult = 1 //- multiplier for points generated when ore hits the processors
	var/static/list/ore_values = list(
		ORE_SAND = 1,
		ORE_HEMATITE = 1,
		ORE_CARBON = 1,
		ORE_COPPER = 1,
		ORE_TIN = 1,
		ORE_VOPAL = 3,
		ORE_PAINITE = 3,
		ORE_QUARTZ= 3,
		ORE_BAUXITE = 5,
		ORE_PHORON = 15,
		ORE_SILVER = 16,
		ORE_GOLD = 18,
		ORE_MARBLE = 20,
		ORE_URANIUM = 30,
		ORE_DIAMOND = 50,
		ORE_PLATINUM = 40,
		ORE_LEAD = 40,
		ORE_MHYDROGEN = 40,
		ORE_VERDANTIUM = 60,
		ORE_RUTILE = 40)

/obj/machinery/mineral/processing_unit/Initialize(mapload)
	. = ..()
	for(var/ore, value in GLOB.ore_data)
		var/datum/ore/OD = value
		LAZYSET(ores_processing, OD.name, 0)
		ores_stored[OD.name] = 0

	// TODO - Eschew input/output machinery and just use dirs ~Leshana
	//Locate our output and input machinery.
	for (var/dir in GLOB.cardinal)
		rel_set(src, nameof(input), locate(/obj/machinery/mineral/input, get_step(src, dir)))
		if(src.input_marker()) break
	for (var/dir in GLOB.cardinal)
		rel_set(src, nameof(output), locate(/obj/machinery/mineral/output, get_step(src, dir)))
		if(src.output_marker()) break
	watch_input(input_marker())

/// Phase 2: drops the turf watch on its input marker.
/obj/machinery/mineral/processing_unit/lifecycle_dematerialize()
	. = ..()
	unwatch_input(input_marker())

/obj/machinery/mineral/processing_unit/proc/toggle_speed(forced)
	var/area/refinery_area = get_area(src)
	if(forced)
		set_speed_process(forced)
	else
		set_speed_process(!speed_process) // switching gears
	// The active declaration moves the work between the machine pipeline and the fast lane on
	// speed_process (code/datums/sys/periodic.dm).
	for(var/obj/machinery/mineral/unloading_machine/unloader in contents_of(refinery_area))
		unloader.toggle_speed()
	for(var/obj/machinery/conveyor_switch/cswitch in contents_of(refinery_area))
		cswitch.toggle_speed()
	for(var/obj/machinery/mineral/stacking_machine/stacker in contents_of(refinery_area))
		stacker.toggle_speed()

/// Takes in what is on its input plate and smelts while active (declared: switched off it neither
/// takes in nor smelts, ore waits on the plate); with nothing to make it sleeps until something
/// arrives (on_input_entered()).
// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/mineral/processing_unit)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = cond_all(nameof(active), cond_not(nameof(panel_open))), wakes_on = list(nameof(active), nameof(panel_open)))

/obj/machinery/mineral/processing_unit/proc/work_step(datum/act/timer/timer)

	if (!src.output_marker() || !src.input_marker())
		return PROCESS_KILL

	if(!powered())
		return work_wait_for_power(src)

	var/list/tick_alloys = list()

	//Grab some more ore to process this tick.
	for(var/obj/structure/ore_box/OB in input_marker().loc)
		for(var/ore in OB.stored_ore)
			if(OB.stored_ore[ore] > 0)
				var/ore_amount = OB.stored_ore[ore]									// How many ores does the box have?
				ores_stored[ore] += ore_amount 										// Add the ore to the machine.
				points += (ore_values[ore]*points_mult*ore_amount) // Give Points! or give lots of points! or less points! or no points!
				OB.stored_ore[ore] = 0 												// Set the value of the ore in the box to 0.

	for(var/obj/item/ore_chunk/ore_chunk in input_marker().loc) //Special ore chunk item. For conveyor belt. Completely unneeded but keeps asthetics.
		if(!LAZYLEN(ore_chunk.stored_ore))
			continue
		var/list/chunk_ores = ore_chunk.stored_ore.Copy()
		if(!consume(ore_chunk))
			continue
		for(var/ore in chunk_ores)
			if(chunk_ores[ore] > 0)
				var/ore_amount = chunk_ores[ore]
				ores_stored[ore] += ore_amount
				points += (ore_values[ore]*points_mult*ore_amount)

	for(var/obj/item/ore/O in input_marker().loc)
		var/ore_material = O.material
		if(!consume(O))
			continue
		if(!isnull(ores_stored[ore_material]))
			ores_stored[ore_material]++
			points += (ore_values[ore_material]*points_mult)

	//Process our stored ores and spit out sheets.
	var/sheets = 0
	for(var/metal in ores_stored)

		if(sheets >= sheets_per_tick) break

		if(ores_stored[metal] > 0 && LAZYACCESS(ores_processing, metal) != 0)

			var/datum/ore/O = GLOB.ore_data[metal]

			if(!O) continue

			if(LAZYACCESS(ores_processing, metal) == PROCESS_ALLOY && O.alloy) //Alloying.

				for(var/datum/alloy/A in GLOB.alloy_data)

					if(A.metaltag in tick_alloys)
						continue

					tick_alloys += A.metaltag
					var/enough_metal

					if(!isnull(A.requires[metal]) && ores_stored[metal] >= A.requires[metal]) //We have enough of our first metal, we're off to a good start.

						enough_metal = 1

						for(var/needs_metal in A.requires)
							//Check if we're alloying the needed metal and have it stored.
							if(LAZYACCESS(ores_processing, needs_metal) != PROCESS_ALLOY || ores_stored[needs_metal] < A.requires[needs_metal])
								enough_metal = 0
								break

					if(!enough_metal)
						continue
					else
						var/total = 0
						for(var/needs_metal in A.requires)
							ores_stored[needs_metal] -= A.requires[needs_metal]
							total += A.requires[needs_metal]
						total = max(1,round(total*A.product_mod)) //Always get at least one sheet.
						sheets += total-1

						for(var/i=0,i<total,i++)
							new A.product(output_marker().loc)

			else if(LAZYACCESS(ores_processing, metal) == PROCESS_COMPRESS && O.compresses_to) //Compressing.

				var/can_make = CLAMP(ores_stored[metal],0,sheets_per_tick-sheets)
				if(can_make%2>0) can_make--

				var/datum/material/M = get_material_by_name(O.compresses_to)

				if(!istype(M) || !can_make || ores_stored[metal] < 1)
					continue

				for(var/i=0,i<can_make,i+=2)
					ores_stored[metal]-=2
					sheets+=2
					new M.stack_type(output_marker().loc)

			else if(LAZYACCESS(ores_processing, metal) == PROCESS_SMELT && O.smelts_to) //Smelting.

				var/can_make = CLAMP(ores_stored[metal],0,sheets_per_tick-sheets)

				var/datum/material/M = get_material_by_name(O.smelts_to)
				if(!istype(M) || !can_make || ores_stored[metal] < 1)
					continue

				for(var/i=0,i<can_make,i++)
					ores_stored[metal]--
					sheets++
					new M.stack_type(output_marker().loc)
			else
				ores_stored[metal]--
				sheets++
				new /obj/item/ore/slag(output_marker().loc)
		else
			continue
	if(!sheets)
		return PROCESS_KILL

#undef PROCESS_NONE
#undef PROCESS_SMELT
#undef PROCESS_COMPRESS
#undef PROCESS_ALLOY

/// Accessor for the input var.
/obj/machinery/mineral/processing_unit/proc/input_marker() as /obj/machinery/mineral
	return input

/// Accessor for the output var.
/obj/machinery/mineral/processing_unit/proc/output_marker() as /obj/machinery/mineral
	return output

/// Accessor for the console var.
/obj/machinery/mineral/processing_unit/proc/linked_console() as /obj/machinery/mineral
	return console

/// Accessor for the machine var.
/obj/machinery/mineral/processing_unit_console/proc/machine() as /obj/machinery/mineral/processing_unit
	return machine
