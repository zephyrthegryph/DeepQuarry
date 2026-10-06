/obj/machinery/atmospherics/binary/algae_farm
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "algae oxygen generator"
	desc = "An oxygen generator using algae to convert carbon dioxide to oxygen."
	icon = 'icons/obj/machines/algae_vr.dmi'
	icon_state = "algae-off"
	circuit = /obj/item/circuitboard/algae_farm
	anchored = TRUE
	density = TRUE
	power_channel = EQUIP
	use_power = USE_POWER_IDLE
	idle_power_usage = 100		// Minimal lights to keep algae alive
	active_power_usage = 5000	// Powerful grow lights to stimulate oxygen production
	//power_rating = 7500			//7500 W ~ 10 HP
	pipe_flags = PIPING_DEFAULT_LAYER_ONLY|PIPING_ONE_PER_TURF

	var/list/stored_material =  list(MAT_ALGAE = 0, MAT_GRAPHITE = 0) // ALLOW(instance_list): d: edited in place per instance (5 writers)
	// Capacity increases with matter bin quality
	var/list/storage_capacity = list(MAT_ALGAE = 10000, MAT_GRAPHITE = 10000) // ALLOW(instance_list): d: edited in place per instance (1 writers)
	// Speed at which we convert CO2 to O2.  Increases with manipulator quality
	var/moles_per_tick = 1
	// Power required to convert one mole of CO2 to O2 (this is powering the grow lights).  Improves with capacitors
	var/power_per_mole = 1000
	var/algae_per_mole = 2
	var/carbon_per_mole = 2

	var/recent_power_used = 0
	var/recent_moles_transferred = 0
	var/ui_error = null // For error messages to show up in nano ui.

	/// The farm's own working mixture (owned).
	var/datum/gas_mixture/internal
	var/const/input_gas = GAS_CO2
	var/const/output_gas = GAS_O2
	/// It has work each service interval: switched on and working, with algae, room for graphite and CO2 to convert (reconsider()).
	var/working = FALSE

TRACKED(/obj/machinery/atmospherics/binary/algae_farm, working)


CAPABILITIES(/obj/machinery/atmospherics/binary/algae_farm)
	owns_one(nameof(internal), /datum/gas_mixture)
	interface("AlgaeFarm")
	part_replacement()
	gas_watch(air = nameof(air1), changed = PROC_REF(gas_changed), mask = GAS_DEPENDENCY_COMPOSITION)
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(farm_step)), when = nameof(working))
	on_change(nameof(use_power), ANY, then(PROC_REF(reconsider)))
	op("load", item(/obj/item/stack/material), label("Insert materials"), wait(0), then(PROC_REF(materials_loaded)))
	op("toggle", ui_act("toggle"), then(PROC_REF(ui_act_toggle)))
	op("ejectMaterial", ui_act("ejectMaterial", arg("mat", schema_text(4096))), then(PROC_REF(ui_act_ejectmaterial)))

/// Switched to active (grow lights on) and operable.
/obj/machinery/atmospherics/binary/algae_farm/proc/farming()
	return operable() && use_power >= USE_POWER_ACTIVE

/// Not farming: clear the error and report only the idle draw (what the step did when it parked).
/obj/machinery/atmospherics/binary/algae_farm/proc/show_idle_readout()
	recent_moles_transferred = 0
	ui_error = null
	if(use_power == USE_POWER_IDLE)
		last_power_draw = idle_power_usage
	else
		last_power_draw = 0

/obj/machinery/atmospherics/binary/algae_farm/filled
	stored_material = list(MAT_ALGAE = 10000, MAT_GRAPHITE = 0)

/obj/machinery/atmospherics/binary/algae_farm/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(internal), new /datum/gas_mixture)
	desc = initial(desc) + " Its outlet port is to the [dir2text(dir)]."
	default_apply_parts()
	// TODO - Make these in actual icon states so its not silly like this
	var/image/I = image(icon = icon, icon_state = "algae-pipe-overlay", dir = dir)
	I.color = PIPE_COLOR_BLUE
	add_overlay(I)
	I = image(icon = icon, icon_state = "algae-pipe-overlay", dir = GLOB.reverse_dir[dir])
	I.color = PIPE_COLOR_BLACK
	add_overlay(I)

/obj/machinery/atmospherics/binary/algae_farm/power_change()
	. = ..()
	if(.)
		reconsider()

/// Its input's gas changed (its gas watch): it looks again whether it has work.
/obj/machinery/atmospherics/binary/algae_farm/proc/gas_changed(list/observation, index)
	reconsider()

/// Whether it has work: farming, with algae, room for graphite and CO2 on its input (or left inside). Idle, it shows its idle readout.
/obj/machinery/atmospherics/binary/algae_farm/proc/reconsider(datum/act/A)
	var/now = farming() && stored_material[MAT_ALGAE] >= algae_per_mole && stored_material[MAT_GRAPHITE] + carbon_per_mole <= storage_capacity[MAT_GRAPHITE] \
		&& LINDA_GAS_AMT(air1, input_gas) + LINDA_GAS_AMT(internal, input_gas) >= MINIMUM_MOLES_TO_FILTER
	set_working(now)
	if(!farming())
		show_idle_readout()

/// One service interval of farming (its every(), while it has work).
/obj/machinery/atmospherics/binary/algae_farm/proc/farm_step(datum/act/A)
	recent_moles_transferred = 0
	last_power_draw = active_power_usage

	// STEP 1 - Check material resources
	if(stored_material[MAT_ALGAE] < algae_per_mole)
		ui_error = "Insufficient [material_display_name(MAT_ALGAE)] to process."
		reconsider()
		return
	if(stored_material[MAT_GRAPHITE] + carbon_per_mole > storage_capacity[MAT_GRAPHITE])
		ui_error = "[material_display_name(MAT_GRAPHITE)] output storage is full."
		reconsider()
		return
	var/moles_to_convert = min(moles_per_tick,\
		stored_material[MAT_ALGAE] * algae_per_mole,\
		storage_capacity[MAT_GRAPHITE] - stored_material[MAT_GRAPHITE])

	// STEP 2 - Take the CO2 out of the input!
	var/power_draw = scrub_gas(src, list(input_gas), air1, internal, moles_to_convert)
	gas_touched(air1)
	if (power_draw > 0)
		use_power(power_draw)
		last_power_draw += power_draw

	// STEP 3 - Convert CO2 to O2  (Note: We know our internal group multipier is 1, so just be cool)
	var/co2_moles = LINDA_GAS_AMT(internal, input_gas)
	if(co2_moles < MINIMUM_MOLES_TO_FILTER)
		ui_error = "Insufficient [GLOB.gas_data.name[input_gas]] to process."
		reconsider()
		return

	// STEP 4 - Consume the resources
	var/converted_moles = min(co2_moles, moles_per_tick)
	use_power(converted_moles * power_per_mole)
	last_power_draw += converted_moles * power_per_mole
	stored_material[MAT_ALGAE] -= converted_moles * algae_per_mole
	stored_material[MAT_GRAPHITE] += converted_moles * carbon_per_mole

	// STEP 5 - Output the converted oxygen. Fow now we output for free!
	internal.adjust_gas(input_gas, -converted_moles)
	air2.adjust_gas_temp(output_gas, converted_moles, internal.return_temperature())
	gas_touched(air2)
	recent_moles_transferred = converted_moles
	ui_error = null // Success!

/obj/machinery/atmospherics/binary/algae_farm/draw(datum/look/look)
	..()
	if(!operable() || !anchored || use_power < USE_POWER_ACTIVE)
		look.state("algae-off")
	else
		look.state(recent_moles_transferred > 0 ? "algae-full" : "algae-on") // ALLOW(derived_reads): every write of the readout is followed by update_icon()

/obj/machinery/atmospherics/binary/algae_farm/derived()
	. = ..()
	. += drawn_from(nameof(use_power), nameof(anchored))

/obj/machinery/atmospherics/binary/algae_farm/proc/materials_loaded(datum/act/op/A)
	try_load_materials(A.actor, A.held)
	reconsider()
	return OP_OK

/obj/machinery/atmospherics/binary/algae_farm/RefreshParts()
	..()

	var/cap_rating = 0
	var/bin_rating = 0
	var/manip_rating = get_part_rating(/obj/item/stock_parts/manipulator)
	cap_rating = get_part_rating(/obj/item/stock_parts/capacitor)
	bin_rating = get_part_rating(/obj/item/stock_parts/matter_bin)

	power_per_mole = round(initial(power_per_mole) / cap_rating)

	var/storage = 5000 * (bin_rating**2)/2
	for(var/mat in storage_capacity)
		storage_capacity[mat] = storage

	moles_per_tick = initial(moles_per_tick) + (manip_rating**2 - 1)

/obj/machinery/atmospherics/binary/algae_farm/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["panelOpen"] = panel_open
	data["last_flow_rate"] = last_flow_rate
	data["last_power_draw"] = last_power_draw
	data["usePower"] = use_power
	data["errorText"] = ui_error
	var/list/merged_1 = ui_data_obj_machinery_atmospherics_binary_algae_farm(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/atmospherics/binary/algae_farm's window data.
/obj/machinery/atmospherics/binary/algae_farm/proc/ui_data_obj_machinery_atmospherics_binary_algae_farm(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	var/list/materials_ui = list()
	for(var/M in stored_material)
		materials_ui[++materials_ui.len] = list(
				"name" = M,
				"display" = material_display_name(M),
				"qty" = stored_material[M],
				"max" = storage_capacity[M],
				"percent" = (stored_material[M] / storage_capacity[M] * 100))
	data["materials"] = materials_ui
	data["inputDir"] = dir2text(GLOB.reverse_dir[dir])
	data["outputDir"] = dir2text(dir)

	if(air1 && network1 && node1)
		data["input"] = list(
			"pressure" = air1.return_pressure(),
			"name" = GLOB.gas_data.name[input_gas],
			"percent" = air1.total_moles() > 0 ? round((LINDA_GAS_AMT(air1, input_gas) / air1.total_moles()) * 100) : 0,
			"moles" = round(LINDA_GAS_AMT(air1, input_gas), 0.01))
	if(air2 && network2 && node2)
		data["output"] = list(
			"pressure" = air2.return_pressure(),
			"name" = GLOB.gas_data.name[output_gas],
			"percent" = air2.total_moles() ? round((LINDA_GAS_AMT(air2, output_gas) / air2.total_moles()) * 100) : 0,
			"moles" = round(LINDA_GAS_AMT(air2, output_gas), 0.01))

	return data

/obj/machinery/atmospherics/binary/algae_farm/proc/ui_act_toggle(datum/act/op/A)
	if(use_power == USE_POWER_IDLE)
		set_use_power(USE_POWER_ACTIVE)
	else
		set_use_power(USE_POWER_IDLE)
	return OP_OK

/obj/machinery/atmospherics/binary/algae_farm/proc/ui_act_ejectmaterial(datum/act/op/A, mat)
	if(!(mat in stored_material))
		return OP_OK
	eject_materials(mat, 0)
	reconsider()
	return OP_OK

// TODO - These should be replaced with materials datum.

// 0 amount = 0 means ejecting a full stack; -1 means eject everything
/obj/machinery/atmospherics/binary/algae_farm/proc/eject_materials(material_name, amount)
	if(!stored_material[material_name])
		return
	var/datum/material/matdata = get_material_by_name(material_name)
	if(!matdata)
		return

	var/obj/item/stack/material/new_stack = new matdata.stack_type(loc)
	var/perunit = new_stack.perunit

	var/available_units = stored_material[material_name] / perunit

	var/units_to_eject
	if(!amount)
		units_to_eject = available_units
	else
		units_to_eject = min(amount, available_units)

	var/to_set = min(units_to_eject, new_stack.max_amount)
	if(!new_stack.set_amount(to_set))
		return

	stored_material[material_name] -= to_set * perunit
	units_to_eject -= to_set

	while(units_to_eject > 0)
		new_stack = new matdata.stack_type(loc)
		to_set = min(units_to_eject, new_stack.max_amount)

		if(!new_stack.set_amount(to_set))
			break

		stored_material[material_name] -= to_set * perunit
		units_to_eject -= to_set

// Attept to load materials.  Returns 0 if item wasn't a stack of materials, otherwise 1 (even if failed to load)
/obj/machinery/atmospherics/binary/algae_farm/proc/try_load_materials(mob/user, obj/item/stack/material/S)
	if(!istype(S))
		return 0
	if(!(S.material.name in stored_material))
		to_chat(user, span_warning("\The [src] doesn't accept [material_display_name(S.material)]!"))
		return 1
	var/max_res_amount = storage_capacity[S.material.name]
	if(stored_material[S.material.name] + S.perunit <= max_res_amount)
		var/count = 0
		while(stored_material[S.material.name] + S.perunit <= max_res_amount && S.get_amount() >= 1)
			stored_material[S.material.name] += S.perunit
			S.use(1)
			count++
		act_message(user, src, MSG_SELF(span_notice("You insert [count] [S.name] into %T%.")), MSG_OTHERS("%U% inserts [S.name] into %T%."))
	else
		to_chat(user, span_warning("\The [src] cannot hold more [S.name]."))
	return 1

/datum/material/algae
	name = MAT_ALGAE
	stack_type = /obj/item/stack/material/algae
	icon_colour = "#557722"
	shard_type = SHARD_STONE_PIECE
	density = 10 // weight renamed to density.
	hardness = 10
	sheet_singular_name = "sheet"
	sheet_plural_name = "sheets"
	supply_conversion_value = 0.25

/obj/item/stack/material/algae
	name = "algae sheet"
	icon_state = "sheet-uranium"
	color = "#557722"
	default_type = MAT_ALGAE

/obj/item/stack/material/algae/ten
	amount = 10
