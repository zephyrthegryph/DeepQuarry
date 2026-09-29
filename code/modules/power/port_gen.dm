//Baseline portable generator. Has all the default handling. Not intended to be used on it's own (since it generates unlimited power).
/obj/machinery/power/port_gen
	name = "Placeholder Generator"	//seriously, don't use this. It can't be anchored without VV magic.
	desc = "A portable generator for emergency backup power"
	icon = 'icons/obj/power_vr.dmi'
	icon_state = "portgen0"
	density = TRUE
	anchored = FALSE
	use_power = USE_POWER_OFF
	interact_offline = TRUE

	active = 0
	var/power_gen = 5000
	var/recent_fault = 0
	var/power_output = 1
	/// Until when an EMP keeps the generator down (EMP_DISABLE).
	EXPIRY_DECLARE(emp_until)

EMP_DISABLE(/obj/machinery/power/port_gen, 10 MINUTES, "emp_until")
DAMAGE_REACTION(/obj/machinery/power/port_gen, DAMAGE_EMP, PROC_REF(port_gen_emp_fault))

/obj/machinery/power/port_gen/proc/IsBroken()
	return (has_stat(BROKEN | EMPED))

/obj/machinery/power/port_gen/proc/HasFuel() //Placeholder for fuel check.
	return 1

/obj/machinery/power/port_gen/proc/UseFuel() //Placeholder for fuel use.
	return

/obj/machinery/power/port_gen/proc/DropFuel()
	return

/obj/machinery/power/port_gen/proc/handleInactive()
	return FALSE

/obj/machinery/power/port_gen/proc/TogglePower()
	if(active)
		set_active(FALSE)
	else if(HasFuel())
		set_active(TRUE)
	MACHINE_WAKE(src)

/obj/machinery/power/port_gen/machine_step()
	if(active && HasFuel() && !IsBroken() && anchored && power_region)
		set_power_supply(power_gen * power_output)
		UseFuel()
	else
		set_active(FALSE)
		set_power_supply(0)
		update_icon()
		if(!handleInactive())
			return PROCESS_KILL

APPEARANCE_TEMPLATE(/obj/machinery/power/port_gen, "{initial(icon_state)}{active?on:}")

/obj/machinery/power/powered()
	return 1 //doesn't require an external power source

/obj/machinery/power/port_gen/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/port_gen_touch,
	)
	..()

/// Old attack_hand: no-op placeholder (the anchored check did nothing observable either way).
/datum/interaction/machine_hand/port_gen_touch
	id = "port_gen_touch"
	name = "Use"
	effect = /obj/machinery/power/port_gen/proc/interaction_touch

/obj/machinery/power/port_gen/proc/interaction_touch(mob/user, obj/item/held, datum/interaction/interaction)
	return TRUE

/obj/machinery/power/port_gen/examine(mob/user)
	. = ..()
	if(Adjacent(user)) //It literally has a light on the sprite, are you sure this is necessary?
		if(active)
			. += span_notice("The generator is on.")
		else
			. += span_notice("The generator is off.")

/// A pulse can break the generator outright, or blow it up (the outage itself is the EMP_DISABLE).
/obj/machinery/power/port_gen/proc/port_gen_emp_fault(datum/damage_packet/packet)
	switch(packet.severity)
		if(EMP_HEAVY)
			stat_add(BROKEN)
			if(prob(75))
				explode()
				return DAMAGE_REACTION_BLOCK
		if(EMP_MEDIUM)
			if(prob(50)) stat_add(BROKEN)
			if(prob(10))
				explode()
				return DAMAGE_REACTION_BLOCK
		if(EMP_LIGHT)
			if(prob(25)) stat_add(BROKEN)
		if(EMP_HARMLESS)
			if(prob(10)) stat_add(BROKEN)

/obj/machinery/power/port_gen/proc/explode()
	explosion(src.loc, -1, 3, 5, -1)
	qdel(src)

#define TEMPERATURE_DIVISOR 40
#define TEMPERATURE_CHANGE_MAX 20

//A power generator that runs on solid plasma sheets.
/obj/machinery/power/port_gen/pacman
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "\improper P.A.C.M.A.N.-type Portable Generator"
	desc = "A power generator that runs on solid phoron sheets. Rated for 80 kW max safe output."
	circuit = /obj/item/circuitboard/pacman
	var/sheet_name = "Phoron Sheets"
	var/sheet_path = /obj/item/stack/material/phoron

	/*
		These values were chosen so that the generator can run safely up to 80 kW
		A full 50 phoron sheet stack should last 20 minutes at power_output = 4
		temperature_gain and max_temperature are set so that the max safe power level is 4.
		Setting to 5 or higher can only be done temporarily before the generator overheats.
	*/
	power_gen = 20000			//Watts output per power_output level
	var/max_power_output = 5	//The maximum power setting without emagging.
	var/max_safe_output = 4		// For UI use, maximal output that won't cause overheat.
	var/time_per_sheet = 96		//fuel efficiency - how long 1 sheet lasts at power level 1
	var/max_sheets = 100 		//max capacity of the hopper
	var/max_temperature = 300	//max temperature before overheating increases
	var/temperature_gain = 50	//how much the temperature increases per power output level, in degrees per level

	var/sheets = 0			//How many sheets of material are loaded in the generator
	var/sheet_left = 0		//How much is left of the current sheet
	var/temperature = 0		//The current temperature
	var/overheating = 0		//if this gets high enough the generator explodes

/obj/machinery/power/port_gen/pacman/Initialize(mapload)
	. = ..()
	default_apply_parts()

// its unburnt fuel drops as sheets.
/obj/machinery/power/port_gen/pacman/on_destroy(force)
	DropFuel()
	..()

/obj/machinery/power/port_gen/pacman/dismantle()
	while( sheets > 0 )
		DropFuel()
	return ..()

/obj/machinery/power/port_gen/pacman/RefreshParts()
	var/bin_rating = get_part_rating(/obj/item/stock_parts/matter_bin)
	if(bin_rating)
		max_sheets = bin_rating * bin_rating * 50
	var/temp_rating = get_part_rating(/obj/item/stock_parts/micro_laser) + get_part_rating(/obj/item/stock_parts/capacitor)

	power_gen = round(initial(power_gen) * (max(2, temp_rating) / 2))

/obj/machinery/power/port_gen/pacman/examine(mob/user)
	. = ..()
	. += "It appears to be producing [power_gen*power_output] W."
	. += "There [sheets == 1 ? "is" : "are"] [sheets] sheet\s left in the hopper."
	if(IsBroken())
		. += span_warning("It seems to have broken down.")
	if(overheating)
		. += span_danger("It is overheating!")

/obj/machinery/power/port_gen/pacman/HasFuel()
	var/needed_sheets = power_output / time_per_sheet
	if(sheets >= needed_sheets - sheet_left)
		return 1
	return 0

//Removes one stack's worth of material from the generator.
/obj/machinery/power/port_gen/pacman/DropFuel()
	if(sheets)
		var/obj/item/stack/material/S = new sheet_path(loc, sheets)
		sheets -= S.get_amount()

/obj/machinery/power/port_gen/pacman/UseFuel()

	//how much material are we using this iteration?
	var/needed_sheets = power_output / time_per_sheet

	//HasFuel() should guarantee us that there is enough fuel left, so no need to check that
	//the only thing we need to worry about is if we are going to rollover to the next sheet
	if (needed_sheets > sheet_left)
		sheets--
		sheet_left = (1 + sheet_left) - needed_sheets
	else
		sheet_left -= needed_sheets

	//calculate the "target" temperature range
	//This should probably depend on the external temperature somehow, but whatever.
	var/lower_limit = 56 + power_output * temperature_gain
	var/upper_limit = 76 + power_output * temperature_gain

	/*
		Hot or cold environments can affect the equilibrium temperature
		The lower the pressure the less effect it has. I guess it cools using a radiator or something when in vacuum.
		Gives traitors more opportunities to sabotage the generator or allows enterprising engineers to build additional
		cooling in order to get more power out.
	*/
	var/datum/gas_mixture/environment = loc.return_air()
	if (environment)
		var/ratio = min(environment.return_pressure()/ONE_ATMOSPHERE, 1)
		var/ambient = environment.return_temperature() - T20C
		lower_limit += ambient*ratio
		upper_limit += ambient*ratio

	var/average = (upper_limit + lower_limit)/2

	//calculate the temperature increase
	var/bias = 0
	if (temperature < lower_limit)
		bias = min(round((average - temperature)/TEMPERATURE_DIVISOR, 1), TEMPERATURE_CHANGE_MAX)
	else if (temperature > upper_limit)
		bias = max(round((temperature - average)/TEMPERATURE_DIVISOR, 1), -TEMPERATURE_CHANGE_MAX)

	//limit temperature increase so that it cannot raise temperature above upper_limit,
	//or if it is already above upper_limit, limit the increase to 0.
	var/inc_limit = max(upper_limit - temperature, 0)
	var/dec_limit = min(temperature - lower_limit, 0)
	temperature += between(dec_limit, rand(-7 + bias, 7 + bias), inc_limit)

	if (temperature > max_temperature)
		overheat()
	else if (overheating > 0)
		overheating--
		update_icon() //Port RS PR #484

/obj/machinery/power/port_gen/pacman/handleInactive()
	var/cooling_temperature = 20
	var/datum/gas_mixture/environment = loc.return_air()
	if(environment)
		var/ratio = min(environment.return_pressure()/ONE_ATMOSPHERE, 1)
		var/ambient = environment.return_temperature() - T20C
		cooling_temperature += ambient*ratio

	// Ambient temperature crosses the Rust FFI as a float, so tiny rounding
	// differences must not keep an otherwise cold, inactive generator polling.
	if(temperature > cooling_temperature + 0.1)
		var/temp_loss = (temperature - cooling_temperature)/TEMPERATURE_DIVISOR
		temp_loss = between(2, round(temp_loss, 1), TEMPERATURE_CHANGE_MAX)
		temperature = max(temperature - temp_loss, cooling_temperature)
	else
		temperature = cooling_temperature

	if(overheating)
		overheating--
		update_icon() //Port RS PR #484
	return temperature > cooling_temperature + 0.1 || overheating > 0

/obj/machinery/power/port_gen/pacman/proc/overheat()
	overheating++
	if (overheating > 60)
		explode()

/obj/machinery/power/port_gen/pacman/explode()
	//Vapourize all the phoron
	//When ground up in a grinder, 1 sheet produces 20 u of phoron -- Chemistry-Machinery.dm
	//1 mol = 10 u? I dunno. 1 mol of carbon is definitely bigger than a pill
	var/phoron = (sheets+sheet_left)*20
	var/datum/gas_mixture/environment = loc.return_air()
	if (environment)
		environment.adjust_gas_temp(GAS_PHORON, phoron/10, temperature + T0C)

	sheets = 0
	sheet_left = 0
	..()

DECLARE_EMAG_REPEATABLE(/obj/machinery/power/port_gen/pacman, PROC_REF(on_emag), null)
/obj/machinery/power/port_gen/pacman/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	if (active && prob(25))
		explode() //if they're foolish enough to emag while it's running

	if (!emagged)
		set_emagged(1)
		return 1

/obj/machinery/power/port_gen/pacman/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/pacman_add_sheets,
		/datum/interaction/machine_item/pacman_part_replacement,
		/datum/interaction/machine_hand/pacman_open_ui,
	)
	..()

/// Old attackby: add fuel sheets. `sheet_path` varies by subtype, so it's checked at runtime.
/datum/interaction/machine_item/pacman_add_sheets
	id = "pacman_add_sheets"
	name = "Add fuel"
	held_type = /obj/item/stack/material
	offered_when = list(REQ_ON(PRED_HELD, /obj/machinery/power/port_gen/pacman/proc/pacman_sheet_match, null))
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/power/port_gen/pacman/proc/pacman_has_room, "it's full"))
	effect = /obj/machinery/power/port_gen/pacman/proc/interaction_add_sheets

/obj/machinery/power/port_gen/pacman/proc/pacman_sheet_match(mob/actor, atom/target, obj/item/held)
	return istype(held, sheet_path)

/obj/machinery/power/port_gen/pacman/proc/pacman_has_room(mob/actor, atom/target, obj/item/held)
	if(!held)
		return TRUE
	var/obj/item/stack/addstack = held
	return min((max_sheets - sheets), addstack.get_amount()) >= 1

/obj/machinery/power/port_gen/pacman/proc/interaction_add_sheets(mob/user, obj/item/O, datum/interaction/interaction)
	var/obj/item/stack/addstack = O
	var/amount = min((max_sheets - sheets), addstack.get_amount())
	to_chat(user, span_notice("You add [amount] sheet\s to the [src.name]."))
	sheets += amount
	addstack.use(amount)
	return TRUE

/// Old attackby: `else if(!active) if(default_part_replacement(user, O)) return`.
/datum/interaction/machine_item/pacman_part_replacement
	id = "pacman_part_replacement"
	name = "Replace parts"
	category = INTERACTION_CAT_MAINTAIN
	held_type = /obj/item/storage/part_replacer
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/power/port_gen/pacman/proc/pacman_not_active, null))
	effect = /obj/machinery/power/port_gen/pacman/proc/interaction_part_replacement_impl

/obj/machinery/power/port_gen/pacman/proc/pacman_not_active(mob/actor, atom/target, obj/item/held)
	return !active

/obj/machinery/power/port_gen/pacman/proc/interaction_part_replacement_impl(mob/user, obj/item/held, datum/interaction/interaction)
	return default_part_replacement(user, held) ? TRUE : FALSE

/obj/machinery/power/port_gen/pacman/screwdriver_act(mob/user, obj/item/O)
	if(active)
		return ITEM_INTERACT_BLOCKING
	return ..()

/obj/machinery/power/port_gen/pacman/crowbar_act(mob/user, obj/item/O)
	if(active)
		return ITEM_INTERACT_BLOCKING
	return ..()

/obj/machinery/power/port_gen/pacman/wrench_act(mob/user, obj/item/O)
	if(active)
		return ITEM_INTERACT_BLOCKING
	if(!anchored)
		connect_to_network()
		to_chat(user, span_notice("You secure the generator to the floor."))
	else
		disconnect_from_network()
		to_chat(user, span_notice("You unsecure the generator from the floor."))
	play_sfx(src, SFX_ITEMS_DECONSTRUCT)
	set_anchored(!anchored)
	return ITEM_INTERACT_SUCCESS

/// Old attack_hand: base was always called first, then opened the interface if anchored.
/datum/interaction/machine_hand/pacman_open_ui
	id = "pacman_open_ui"
	name = "Use"
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/proc/can_operate_by_hand, null), REQ_ON(PRED_TARGET, /obj/machinery/power/port_gen/pacman/proc/pacman_anchored, null))
	effect = /obj/machinery/power/port_gen/pacman/proc/interaction_open_ui_impl

/obj/machinery/power/port_gen/pacman/proc/pacman_anchored(mob/actor, atom/target, obj/item/held)
	return !!anchored

/obj/machinery/power/port_gen/pacman/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	tgui_interact(user)
	return TRUE

/obj/machinery/power/port_gen/pacman
	silicon_use = SILICON_USE_UI

/obj/machinery/power/port_gen/tgui_status(mob/user, datum/tgui_state/state)
	if(IsBroken())
		return STATUS_CLOSE
	return ..()

DECLARE_UI(/obj/machinery/power/port_gen/pacman, "PortableGenerator")

UI_DATA_REPLACE(/obj/machinery/power/port_gen/pacman, "anchored:num", "temperature_current=temperature:num", "temperature_max=max_temperature:num", "temperature_overheat=overheating:num", "merge:ui_data_obj_machinery_power_port_gen_pacman{active:num,is_ai:bool,sheet_name:text,fuel_stored:num,fuel_capacity:num,fuel_usage:num,connected:num,ready_to_boot:bool,power_generated:unknown,power_output:num,unsafe_output:bool,power_available:unknown}")

/// The computed part of /obj/machinery/power/port_gen/pacman's window data (declared on its UI_DATA row).
/obj/machinery/power/port_gen/pacman/proc/ui_data_obj_machinery_power_port_gen_pacman(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["active"] = active

	if(isAI(user))
		data["is_ai"] = TRUE
	else if(isrobot(user) && !Adjacent(user))
		data["is_ai"] = TRUE
	else
		data["is_ai"] = FALSE

	data["sheet_name"] = capitalize(sheet_name)
	data["fuel_stored"] = round((sheets * 1000) + (sheet_left * 1000))
	data["fuel_capacity"] = round(max_sheets * 1000, 0.1)
	data["fuel_usage"] = active ? round((power_output / time_per_sheet) * 1000) : 0

	data["connected"] = (power_region ? 1 : 0)
	data["ready_to_boot"] = anchored && HasFuel()
	data["power_generated"] = DisplayPower(power_gen)
	data["power_output"] = DisplayPower(power_gen * power_output)
	data["unsafe_output"] = power_output > max_safe_output
	data["power_available"] = (!power_region ? 0 : DisplayPower(avail()))
	// 1 sheet = 1000cm3?

	return data

/obj/machinery/power/port_gen/pacman/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/machinery/power/port_gen/pacman, "toggle_power", ui_act_toggle_power)
UI_ACT_PROC(/obj/machinery/power/port_gen/pacman, ui_act_toggle_power)
	TogglePower()
	. = TRUE

UI_ACT(/obj/machinery/power/port_gen/pacman, "eject", ui_act_eject)
UI_ACT_PROC(/obj/machinery/power/port_gen/pacman, ui_act_eject)
	if(!active)
		DropFuel()
		. = TRUE

UI_ACT(/obj/machinery/power/port_gen/pacman, "lower_power", ui_act_lower_power)
UI_ACT_PROC(/obj/machinery/power/port_gen/pacman, ui_act_lower_power)
	if(power_output > 1)
		power_output--
		. = TRUE

UI_ACT(/obj/machinery/power/port_gen/pacman, "higher_power", ui_act_higher_power)
UI_ACT_PROC(/obj/machinery/power/port_gen/pacman, ui_act_higher_power)
	if(power_output < max_power_output || (emagged && power_output < round(max_power_output * 2.5)))
		power_output++
		. = TRUE

/obj/machinery/power/port_gen/pacman/super
	name = "S.U.P.E.R.P.A.C.M.A.N.-type Portable Generator"
	desc = "A power generator that utilizes uranium sheets as fuel. Can run for much longer than the standard PACMAN type generators. Rated for 80 kW max safe output."
	icon_state = "portgen1"
	sheet_path = /obj/item/stack/material/uranium
	sheet_name = "Uranium Sheets"
	time_per_sheet = 576 //same power output, but a 50 sheet stack will last 2 hours at max safe power
	circuit = /obj/item/circuitboard/pacman/super

/obj/machinery/power/port_gen/pacman/super/UseFuel()
	//produces a tiny amount of radiation when in use
	if (prob(2*power_output))
		radiation_pulse(
			src,
			max_range = 2,
			threshold = RAD_HEAVY_INSULATION,
			chance = DEFAULT_RADIATION_CHANCE,
			strength = power_gen * 0.01
		)
	..()

/obj/machinery/power/port_gen/pacman/super/explode()
	//a nice burst of radiation
	var/rads = 50 + (sheets + sheet_left)*1.5
	radiation_pulse(
		src,
		max_range = (rads/10),
		threshold = RAD_HEAVY_INSULATION,
		chance = DEFAULT_RADIATION_CHANCE,
		strength = rads
	)

	explosion(src.loc, 3, 3, 5, 3)
	qdel(src)

/obj/machinery/power/port_gen/pacman/mrs
	name = "M.R.S.P.A.C.M.A.N.-type Portable Generator"
	desc = "An advanced power generator that runs on tritium. Rated for 200 kW maximum safe output!"
	icon_state = "portgen2"
	sheet_path = /obj/item/stack/material/tritium
	sheet_name = "Tritium Fuel Sheets"

	//I don't think tritium has any other use, so we might as well make this rewarding for players
	//max safe power output (power level = 8) is 200 kW and lasts for 1 hour - 3 or 4 of these could power the station
	power_gen = 25000 //watts
	max_power_output = 10
	max_safe_output = 8
	time_per_sheet = 576
	max_temperature = 800
	temperature_gain = 90
	circuit = /obj/item/circuitboard/pacman/mrs

/obj/machinery/power/port_gen/pacman/mrs/explode()
	//no special effects, but the explosion is pretty big (same as a supermatter shard).
	explosion(src.loc, 3, 6, 12, 16, 1)
	qdel(src)

#undef TEMPERATURE_DIVISOR
#undef TEMPERATURE_CHANGE_MAX

/obj/machinery/power/port_gen/pacman/super/potato
	name = "nuclear reactor"
	desc = "PTTO-3, an industrial all-in-one nuclear power plant by Neo-Chernobyl GmbH. It uses uranium as a fuel source. Rated for 200 kW max safe output."
	icon = 'icons/obj/power.dmi'
	icon_state = "potato"
	time_per_sheet = 1152 //same power output, but a 50 sheet stack will last 4 hours at max safe power
	power_gen = 50000 //watts
	anchored = TRUE

//Port Start, RS PR #484

APPEARANCE_NONE(/obj/machinery/power/port_gen/pacman/super/potato)
DECLARE_APPEARANCE_PROC(/obj/machinery/power/port_gen/pacman/super/potato, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/power/port_gen/pacman/super/potato/appearance_overlays()
	. = list()
	set_light(0)
	//if there was an unexploded broken state, this is where it would go. + return
	if(active && !overheating)
		icon_state = "potatoon"
		var/mutable_appearance/reactorglow = mutable_appearance(icon, "eggrad", alpha = 90) //v.faint glow for reasons. the reasons being it's producing radiation as per code
		. += reactorglow
		set_light(l_range = 2, l_power = 2, l_color = "#A8B0F8")
		return .
	else if(overheating)	//The warp core is overloading, Captain!
		icon_state = "potatodanger"	//show that it's angry, even when it's off. something something subroutine. Visual feedback!
		if(active)	//but only glow if it's also still on, since the reaction is ongoing.
			var/mutable_appearance/reactorglow = mutable_appearance(icon, "eggrad", alpha = 190) //more intense glow, lightings
			. += reactorglow
			set_light(l_range = 5, l_power = 4, l_color = "#A8B0F8")
		return .
	else	//off and it isn't angry, so we just vibe as 'off'
		icon_state = initial(icon_state)
//Port Emd, RS PR #484

// Circuits for the RTGs below
/obj/item/circuitboard/machine/rtg
	name = T_BOARD("radioisotope TEG")
	build_path = /obj/machinery/power/rtg
	board_type = new /datum/frame/frame_types/machine
	req_components = list(
		/obj/item/stack/cable_coil = 5,
		/obj/item/stock_parts/capacitor = 1,
		/obj/item/stack/material/uranium = 10) // We have no Pu-238, and this is the closest thing to it.

/obj/item/circuitboard/machine/rtg/advanced
	name = T_BOARD("advanced radioisotope TEG")
	build_path = /obj/machinery/power/rtg/advanced
	req_components = list(
		/obj/item/stack/cable_coil = 5,
		/obj/item/stock_parts/capacitor = 1,
		/obj/item/stock_parts/micro_laser = 1,
		/obj/item/stack/material/uranium = 10,
		/obj/item/stack/material/phoron = 5)

/obj/item/circuitboard/machine/abductor/core
	name = T_BOARD("void generator")
	build_path = /obj/machinery/power/rtg/abductor
	board_type = new /datum/frame/frame_types/machine
	req_components = list(
		/obj/item/stack/cable_coil = 5,
		/obj/item/stock_parts/capacitor = 1)
	hidden = TRUE

/obj/item/circuitboard/machine/abductor/core/hybrid
	name = T_BOARD("void generator (hybrid)")
	build_path = /obj/machinery/power/rtg/abductor/hybrid
	board_type = new /datum/frame/frame_types/machine
	req_components = list(
		/obj/item/stack/cable_coil = 5,
		/obj/item/stock_parts/capacitor = 1,
		/obj/item/stock_parts/micro_laser = 1)
	hidden = TRUE

// Radioisotope Thermoelectric Generator (RTG)
// Simple power generator that would replace "magic SMES" on various derelicts.
/obj/machinery/power/rtg
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "radioisotope thermoelectric generator"
	desc = "A simple nuclear power generator, used in small outposts to reliably provide power for decades."
	icon = 'icons/obj/power_vr.dmi'
	icon_state = "rtg"
	density = TRUE
	use_power = USE_POWER_OFF
	circuit = /obj/item/circuitboard/machine/rtg

	// You can buckle someone to RTG, then open its panel. Fun stuff.
	can_buckle = TRUE
	buckle_lying = FALSE

	var/power_gen = 1000 // Enough to power a single APC. 4000 output with T4 capacitor.
	var/irradiate = TRUE // RTGs irradiate surroundings, but only when panel is open.

/obj/machinery/power/rtg/Initialize(mapload)
	. = ..()
	default_apply_parts()
	if(mapload)
		return INITIALIZE_HINT_LATELOAD

/obj/machinery/power/rtg/LateInitialize()
	apply_mapped_upgrades()

/obj/machinery/power/rtg/apply_mapped_upgrades()
	// Detect new parts placed by mappers
	var/list/parts_found = list()
	for(var/i = 1, i <= contents_count(loc), i++)
		var/obj/item/W = loc.contents[i]
		if(istype(W, /obj/item/stock_parts/capacitor))
			parts_found.Add(W)
		if(istype(W, /obj/item/stock_parts/micro_laser))
			parts_found.Add(W)

	// Wipe old parts for new ones!
	if(parts_found.len == 0)
		return
	materialize_parts()
	if(locate_in_list(parts_found, /obj/item/stock_parts/capacitor))
		while(TRUE)
			var/obj/item/stock_parts/capacitor/C = locate_in_list(component_parts, /obj/item/stock_parts/capacitor)
			if(isnull(C))
				break
			own_take_member(src, "component_parts", C)
			qdel(C)
	if(locate_in_list(parts_found, /obj/item/stock_parts/micro_laser))
		while(TRUE)
			var/obj/item/stock_parts/micro_laser/M = locate_in_list(component_parts, /obj/item/stock_parts/micro_laser)
			if(isnull(M))
				break
			own_take_member(src, "component_parts", M)
			qdel(M)

	// Rebuild from mapper's parts
	for(var/i = 1, i <= parts_found.len, i++)
		var/obj/item/W = parts_found[i]
		own_add(src, "component_parts", W)
		W.move_into(src, CONTAINER_SLOT_INTERNALS)
	RefreshParts()

/obj/machinery/power/rtg/machine_step()
	..()
	add_avail(power_gen)
	if(panel_open && irradiate)
		radiation_pulse(
			src,
			max_range = 3,
			threshold = RAD_MEDIUM_INSULATION,
			chance = DEFAULT_RADIATION_CHANCE,
			minimum_exposure_time = URANIUM_RADIATION_MINIMUM_EXPOSURE_TIME,
			strength = power_gen * 0.01 //1000 power = 10 rads. 10000 power = 100 rads. You can get creative with rad collectors if you want.
		)

/obj/machinery/power/rtg/RefreshParts()
	var/part_level = total_component_rating_of_type(/obj/item/stock_parts)

	power_gen = initial(power_gen) * part_level

/obj/machinery/power/rtg/examine(mob/user)
	. = ..()
	if(Adjacent(user, src) || isobserver(user))
		. += span_notice("The status display reads: Power generation now at <b>[power_gen*0.001]</b>kW.")

/obj/machinery/power/rtg/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/part_replacement,
	)
	..()

APPEARANCE_TEMPLATE(/obj/machinery/power/rtg, "{initial(icon_state)}{panel_open?-open:}")

/obj/machinery/power/rtg/advanced
	desc = "An advanced RTG capable of moderating isotope decay, increasing power output but reducing lifetime. It uses plasma-fueled radiation collectors to increase output even further."
	power_gen = 1250 // 2500 on T1, 10000 on T4.
	circuit = /obj/item/circuitboard/machine/rtg/advanced

/obj/machinery/power/rtg/fake_gen
	name = "area power generator"
	desc = "Some power generation equipment that might be powering the current area."
	icon_state = "rtg_gen"
	power_gen = 6000
	circuit = /obj/item/circuitboard/machine/rtg
	can_buckle = FALSE

/obj/machinery/power/rtg/fake_gen/RefreshParts()
	return
/// Old attackby: blocked entirely (never called ..()), so fake_gen never offers the base rtg's part replacement.
/obj/machinery/power/rtg/fake_gen/declare_interactions(list/into)
	return
APPEARANCE_NONE(/obj/machinery/power/rtg/fake_gen)

/obj/machinery/power/rtg/fake_gen/grid
	desc = "An array of conventional power storage units, for when the added charge longivity and cost of a SMES unit is unneded or impractical."
	icon = 'icons/obj/power.dmi'
	icon_state = "gridchecker_off"
	name = "capacitor bank"
	power_gen = 12000

// Void Core, power source for Abductor ships and bases.
// Provides a lot of power, but tends to explode when mistreated.
/obj/machinery/power/rtg/abductor
	name = "Void Core"
	icon_state = "core-nocell"
	desc = "An alien power source that produces energy seemingly out of nowhere."
	circuit = /obj/item/circuitboard/machine/abductor/core
	power_gen = 10000
	irradiate = FALSE // Green energy!
	can_buckle = FALSE
	pixel_y = 7
	var/going_kaboom = FALSE // Is it about to explode?
	var/obj/item/cell/void/cell

	var/icon_base = "core"
	var/state_change = TRUE

/obj/machinery/power/rtg/abductor/RefreshParts()
	..()
	if(!cell)
		power_gen = 0

/obj/machinery/power/rtg/abductor/proc/asplod()
	if(going_kaboom)
		return
	going_kaboom = TRUE
	visible_message(span_danger("\The [src] lets out an shower of sparks as it starts to lose stability!"),\
		span_warningplain("You hear a loud electrical crack!"))
	play_sfx(src, SFX_EFFECTS_LIGHTNINGSHOCK)
	tesla_zap(src, 5, power_gen * 0.05, current_jumps = 1)
	om_after(null, 100, GLOBAL_PROC_REF(explosion), get_turf(src), 2, 3, 4, 8) // Not a normal explosion.

/obj/machinery/power/rtg/abductor/bullet_act(obj/item/projectile/Proj)
	. = ..()
	if(!QDELETED(src) && !going_kaboom && istype(Proj) && !Proj.nodamage && ((Proj.obj_damage_type() == BURN) || (Proj.obj_damage_type() == BRUTE)))
		log_and_message_admins("[ADMIN_LOOKUPFLW(Proj.firer)] triggered an Abductor Core explosion at [x],[y],[z] via projectile.", Proj.firer)
		asplod()

/obj/machinery/power/rtg/abductor/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/abductor_eject_cell,
		/datum/interaction/machine_item/abductor_insert_cell,
		/datum/interaction/machine_item/abductor_insert_cell_real,
	)
	..()

/// Old attack_hand: eject the void cell. `!istype(user)` (never true for a mob/living param) is kept as a requirement for fidelity.
/datum/interaction/machine_hand/abductor_eject_cell
	id = "abductor_eject_cell"
	name = "Take out"
	category = INTERACTION_CAT_EJECT
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/proc/can_operate_by_hand, null), REQ_ON(PRED_ACTOR, /obj/machinery/power/rtg/abductor/proc/abductor_actor_is_living, null), REQ_ON(PRED_TARGET, /obj/machinery/power/rtg/abductor/proc/abductor_has_cell, null))
	effect = /obj/machinery/power/rtg/abductor/proc/interaction_eject_cell

/obj/machinery/power/rtg/abductor/proc/abductor_actor_is_living(mob/actor, atom/target, obj/item/held)
	return isliving(actor)

/obj/machinery/power/rtg/abductor/proc/abductor_has_cell(mob/actor, atom/target, obj/item/held)
	return !!cell

/obj/machinery/power/rtg/abductor/proc/interaction_eject_cell(mob/user, obj/item/held, datum/interaction/interaction)
	cell.forceMove(get_turf(src))
	user.put_in_active_hand(cell)
	own_take(src, "cell")
	state_change = TRUE
	RefreshParts()
	update_icon()
	play_sfx(src, SFX_EFFECTS_METAL_CLOSE)
	return TRUE

/// Old attackby: `state_change = TRUE` ran unconditionally first, then a void cell was inserted if there wasn't one already.
/datum/interaction/machine_item/abductor_insert_cell
	id = "abductor_insert_cell"
	name = "Use"
	held_type = /obj/item
	consumes_input = FALSE
	effect = /obj/machinery/power/rtg/abductor/proc/interaction_state_change_marker

/obj/machinery/power/rtg/abductor/proc/interaction_state_change_marker(mob/user, obj/item/held, datum/interaction/interaction)
	state_change = TRUE //Can't tell if parent did something
	return FALSE

/datum/interaction/machine_item/abductor_insert_cell_real
	id = "abductor_insert_cell_real"
	name = "Insert void cell"
	category = INTERACTION_CAT_INSERT
	held_type = /obj/item/cell/void
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/power/rtg/abductor/proc/abductor_no_cell, null))
	effect = /obj/machinery/power/rtg/abductor/proc/interaction_insert_cell

/obj/machinery/power/rtg/abductor/proc/abductor_no_cell(mob/actor, atom/target, obj/item/held)
	return !cell

/obj/machinery/power/rtg/abductor/proc/interaction_insert_cell(mob/user, obj/item/I, datum/interaction/interaction)
	if(!own_set(src, nameof(src.cell), I, user = user))
		return TRUE
	RefreshParts()
	update_icon()
	play_sfx(src, SFX_EFFECTS_METAL_CLOSE)
	return TRUE

APPEARANCE_TEMPLATE(/obj/machinery/power/rtg/abductor, "{icon_base}{appearance_core_suffix}")

/// Sprite suffix: no cell, open panel, or closed.
/obj/machinery/power/rtg/abductor/proc/appearance_core_suffix()
	if(!cell)
		return "-nocell"
	return panel_open ? "-open" : ""

DAMAGE_REACTION(/obj/machinery/power/rtg/abductor, DAMAGE_BLOB, PROC_REF(void_core_hit_asplod))
DAMAGE_REACTION(/obj/machinery/power/rtg/abductor, DAMAGE_EXPLOSION, PROC_REF(void_core_blast))

/// A blob arms the core instead of damaging it.
/obj/machinery/power/rtg/abductor/proc/void_core_hit_asplod(datum/damage_packet/packet)
	asplod()
	return DAMAGE_REACTION_BLOCK

/// A blast arms the core, or finishes one already armed.
/obj/machinery/power/rtg/abductor/proc/void_core_blast(datum/damage_packet/packet)
	// Exception: asplod() is this volatile core's already-armed detonation lifecycle.
	// qdel here only completes that lifecycle; ordinary shell damage enters through
	// the inherited obj_integrity projectile path before arming the core.
	if(going_kaboom)
		qdel(src)
	else
		asplod()
	return DAMAGE_REACTION_BLOCK

/// Heat behaviour rule: fire sets off a void core.
/obj/machinery/power/rtg/abductor/proc/rule_asplod(datum/rule/rule)
	asplod()

// Comes with an installed cell
/obj/machinery/power/rtg/abductor/built
	icon_state = "core"

DECLARE_DEFAULT_CHILD(/obj/machinery/power/rtg/abductor/built, "cell", /obj/item/cell/void)

/obj/machinery/power/rtg/abductor/built/Initialize(mapload)
	. = ..()
	RefreshParts()

// Bloo version
/obj/machinery/power/rtg/abductor/hybrid
	icon_state = "coreb-nocell"
	icon_base = "coreb"
	circuit = /obj/item/circuitboard/machine/abductor/core/hybrid

/obj/machinery/power/rtg/abductor/hybrid/built
	icon_state = "coreb"

DECLARE_DEFAULT_CHILD(/obj/machinery/power/rtg/abductor/hybrid/built, "cell", /obj/item/cell/void/hybrid)

/obj/machinery/power/rtg/abductor/hybrid/built/Initialize(mapload)
	. = ..()
	RefreshParts()

// Kugelblitz generator, confined black hole like a singulo but smoller and higher tech
// Presumably whoever made these has better tech than most
/obj/machinery/power/rtg/kugelblitz
	name = "kugelblitz generator"
	desc = "A power source harnessing a small black hole."
	icon = 'icons/obj/props/decor64x64.dmi'
	icon_state = "bigdice"
	bound_width = 64
	bound_height = 64
	power_gen = 30000
	irradiate = FALSE // Green energy!
	can_buckle = FALSE

/obj/machinery/power/rtg/kugelblitz/proc/asplod()
	visible_message(span_danger("\The [src] lets out an shower of sparks as it starts to lose stability!"),\
		span_warningplain("You hear a loud electrical crack!"))
	play_sfx(src, SFX_EFFECTS_LIGHTNINGSHOCK)
	var/turf/T = get_turf(src)
	qdel(src)
	new /obj/singularity(T)

DAMAGE_REACTION(/obj/machinery/power/rtg/kugelblitz, DAMAGE_BLOB, PROC_REF(kugelblitz_hit_asplod))
DAMAGE_REACTION(/obj/machinery/power/rtg/kugelblitz, DAMAGE_EXPLOSION, PROC_REF(kugelblitz_hit_asplod))

/// A blob or a blast collapses the containment.
/obj/machinery/power/rtg/kugelblitz/proc/kugelblitz_hit_asplod(datum/damage_packet/packet)
	asplod()
	return DAMAGE_REACTION_BLOCK

/// Heat behaviour rule: fire sets off a kugelblitz.
/obj/machinery/power/rtg/kugelblitz/proc/rule_asplod(datum/rule/rule)
	asplod()

/obj/machinery/power/rtg/kugelblitz/bullet_act(obj/item/projectile/Proj)
	. = ..()
	if(istype(Proj) && !Proj.nodamage && ((Proj.obj_damage_type() == BURN) || (Proj.obj_damage_type() == BRUTE)) && Proj.damage >= 20)
		log_and_message_admins("[ADMIN_LOOKUPFLW(Proj.firer)] triggered a kugelblitz core explosion at [x],[y],[z] via projectile.", Proj.firer)
		asplod()

/obj/machinery/power/rtg/reg
	name = "d-type rotary electric generator"
	desc = "It looks kind of like a large hamster wheel."
	icon = 'icons/obj/power_vrx96.dmi'
	icon_state = "reg"
	circuit = /obj/item/circuitboard/machine/reg_d
	irradiate = FALSE
	power_gen = 0
	var/default_power_gen = 1000000	//It's big but it gets adjusted based on what you put into it!!!
	var/part_mult = 0
	var/nutrition_drain = 1
	pixel_x = -32
	plane = ABOVE_MOB_PLANE
	layer = ABOVE_MOB_LAYER
	buckle_dir = EAST
	interact_offline = TRUE
	density = FALSE

/obj/machinery/power/rtg/reg/Initialize(mapload)
	pixel_x = -32
	. = ..()

/obj/machinery/power/rtg/reg/user_buckle_mob(mob/living/M, mob/user, forced = FALSE, silent = TRUE)
	. = ..()
	M.pixel_y = 8
	act_message(M, src, others = span_notice("%U%, hops up onto %T% and begins running!"))

/obj/machinery/power/rtg/reg/unbuckle_mob(mob/living/buckled_mob, force = FALSE)
	. = ..()
	buckled_mob.pixel_y = buckled_mob.default_pixel_y

/obj/machinery/power/rtg/reg/RefreshParts()
	part_mult = total_component_rating_of_type(/obj/item/stock_parts)

/obj/machinery/power/rtg/reg/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/reg_pixel_fix,
	)
	..()

/// Old attackby: `pixel_x = -32` ran unconditionally first, then the base rtg's part replacement.
/datum/interaction/machine_item/reg_pixel_fix
	id = "reg_pixel_fix"
	name = "Use"
	held_type = /obj/item
	consumes_input = FALSE
	effect = /obj/machinery/power/rtg/reg/proc/interaction_pixel_fix

/obj/machinery/power/rtg/reg/proc/interaction_pixel_fix(mob/user, obj/item/held, datum/interaction/interaction)
	pixel_x = -32
	return FALSE

APPEARANCE_NONE(/obj/machinery/power/rtg/reg)
DECLARE_APPEARANCE_PROC(/obj/machinery/power/rtg/reg, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/power/rtg/reg/appearance_overlays()
	. = list()
	pixel_x = -32
	if(panel_open)
		icon_state = "reg-o"
	else if(length(src?.buckled_mob_list()) > 0)
		icon_state = "reg-a"
	else
		icon_state = "reg"

/obj/machinery/power/rtg/reg/machine_step()
	..()
	if(length(src?.buckled_mob_list()) > 0)
		for(var/mob/living/L in src?.buckled_mob_list())
			runner_process(L)
	else
		power_gen = 0
	update_icon()

/obj/machinery/power/rtg/reg/proc/runner_process(mob/living/runner)
	if(runner.stat != CONSCIOUS)
		unbuckle_mob(runner)
		act_message(runner, src, others = span_warning("%U%, topples off of %T%!"))
		return
	var/cool_rotations
	if(ishuman(runner))
		var/mob/living/carbon/human/R = runner
		cool_rotations = R.movement_delay()
	else if (isanimal(runner))
		var/mob/living/simple_mob/R = runner
		cool_rotations = R.movement_delay()
	if(cool_rotations <= 0)
		cool_rotations = 0.5
	cool_rotations = default_power_gen / cool_rotations
	switch(runner.nutrition)
		if(1000 to INFINITY)	//VERY WELL FED, ZOOM!!!!
			cool_rotations *= (runner.nutrition * 0.001)
		if(500 to 1000)	//Well fed!
			cool_rotations = cool_rotations
		if(400 to 500)
			cool_rotations *= 0.9
		if(300 to 400)
			cool_rotations *= 0.75
		if(200 to 300)
			cool_rotations *= 0.5
		if(100 to 200)
			cool_rotations *= 0.25
		else	//TOO HUNGY IT TIME TO STOP!!!
			unbuckle_mob(runner)
			act_message(runner, src, others = span_notice("%U%, panting and exhausted hops off of %T%!"))
	if(part_mult > 1)
		cool_rotations += (cool_rotations * (part_mult - 1)) / 4
	power_gen = cool_rotations
	runner.adjust_nutrition(-(nutrition_drain))

/obj/item/circuitboard/machine/reg_d
	name = T_BOARD("D-Type-REG")
	build_path = /obj/machinery/power/rtg/reg
	board_type = new /datum/frame/frame_types/machine
	req_components = list(
		/obj/item/stack/cable_coil = 5,
		/obj/item/stock_parts/capacitor = 1)

/obj/item/circuitboard/machine/reg_c
	name = T_BOARD("C-Type-REG")
	build_path = /obj/machinery/power/rtg/reg/c
	board_type = new /datum/frame/frame_types/machine
	req_components = list(
		/obj/item/stack/cable_coil = 5,
		/obj/item/stock_parts/capacitor = 1)

/obj/machinery/power/rtg/reg/c
	name = "c-type rotary electric generator"
	circuit = /obj/item/circuitboard/machine/reg_c
	default_power_gen = 500000 //Half power
	nutrition_drain = 0.5	//for half cost - EQUIVALENT EXCHANGE >:O

// Big altevian version of pacman. has a lot of copypaste from regular kind, but less flexible.
/obj/machinery/power/port_gen/large_altevian
	name = "Phoronic Conversion System"
	desc = "A reactor system similar to the PACMAN generators seen throughout the stars. This one is a specific model created by the altevians. It seems this reactor has a way to maximize the fuel usage one would see with this kind of process. \
			However, due to its construction and size it is nearly impossible to break apart. It still can be moved if need be with special tools."
	icon = 'icons/obj/props/decor64x64.dmi'
	icon_state = "alteviangen"
	bound_width = 64
	bound_height = 64
	anchored = TRUE
	power_gen = 250000

	var/sheet_name = "Phoron Sheets"
	var/sheet_path = /obj/item/stack/material/phoron
	var/sheets = 0			//How many sheets of material are loaded in the generator
	var/sheet_left = 0		//How much is left of the current sheet
	var/time_per_sheet = 120		//fuel efficiency - how long 1 sheet lasts at power level 1
	var/max_sheets = 100 		//max capacity of the hopper

// its unburnt fuel drops as sheets.
/obj/machinery/power/port_gen/large_altevian/on_destroy(force)
	DropFuel()
	..()

/obj/machinery/power/port_gen/large_altevian/examine(mob/user)
	. = ..()
	. += "There [sheets == 1 ? "is" : "are"] [sheets] sheet\s left in the hopper."

/obj/machinery/power/port_gen/large_altevian/HasFuel()
	var/needed_sheets = power_output / time_per_sheet
	if(sheets >= needed_sheets - sheet_left)
		return 1
	return 0

/obj/machinery/power/port_gen/large_altevian/DropFuel()
	if(sheets)
		var/obj/item/stack/material/S = new sheet_path(loc, sheets)
		sheets -= S.get_amount()

/obj/machinery/power/port_gen/large_altevian/UseFuel()
	var/needed_sheets = power_output / time_per_sheet
	if (needed_sheets > sheet_left)
		sheets--
		sheet_left = (1 + sheet_left) - needed_sheets
	else
		sheet_left -= needed_sheets

/obj/machinery/power/port_gen/large_altevian/declare_interactions(list/into)
	var/static/list/actor_specs = list(
		INTERACT_SILICON("Toggle power", PROC_REF(large_altevian_silicon_toggle)),
	)
	for(var/actor_spec in actor_specs)
		into += dq_interaction_from_spec(type, actor_spec)
	into += list(
		/datum/interaction/machine_item/large_altevian_add_sheets,
		/datum/interaction/machine_hand/large_altevian_toggle,
	)
	..()

/// Old attackby: add fuel sheets.
/datum/interaction/machine_item/large_altevian_add_sheets
	id = "large_altevian_add_sheets"
	name = "Add fuel"
	held_type = /obj/item/stack/material
	offered_when = list(REQ_ON(PRED_HELD, /obj/machinery/power/port_gen/large_altevian/proc/large_altevian_sheet_match, null))
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/power/port_gen/large_altevian/proc/large_altevian_has_room, "it's full"))
	effect = /obj/machinery/power/port_gen/large_altevian/proc/interaction_add_sheets

/obj/machinery/power/port_gen/large_altevian/proc/large_altevian_sheet_match(mob/actor, atom/target, obj/item/held)
	return istype(held, sheet_path)

/obj/machinery/power/port_gen/large_altevian/proc/large_altevian_has_room(mob/actor, atom/target, obj/item/held)
	if(!held)
		return TRUE
	var/obj/item/stack/addstack = held
	return min((max_sheets - sheets), addstack.get_amount()) >= 1

/obj/machinery/power/port_gen/large_altevian/proc/interaction_add_sheets(mob/user, obj/item/O, datum/interaction/interaction)
	var/obj/item/stack/addstack = O
	var/amount = min((max_sheets - sheets), addstack.get_amount())
	to_chat(user, span_notice("You add [amount] sheet\s to the [src.name]."))
	sheets += amount
	addstack.use(amount)
	update_icon()
	return TRUE

/// Old attack_hand: the base port_gen behaviour always ran, then toggled power if anchored.
/datum/interaction/machine_hand/large_altevian_toggle
	id = "large_altevian_toggle"
	name = "Toggle"
	category = INTERACTION_CAT_TOGGLE
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/proc/can_operate_by_hand, null), REQ_ON(PRED_TARGET, /obj/machinery/power/port_gen/large_altevian/proc/large_altevian_anchored, null))
	effect = /obj/machinery/power/port_gen/large_altevian/proc/interaction_toggle_power

/obj/machinery/power/port_gen/large_altevian/proc/large_altevian_anchored(mob/actor, atom/target, obj/item/held)
	return !!anchored

/obj/machinery/power/port_gen/large_altevian/proc/interaction_toggle_power(mob/user, obj/item/held, datum/interaction/interaction)
	TogglePower()
	return TRUE

/// Old attack_ai: toggle the generator.
/obj/machinery/power/port_gen/large_altevian/proc/large_altevian_silicon_toggle(mob/user, obj/item/held, datum/interaction/interaction)
	TogglePower()
	return TRUE

DECLARE_APPEARANCE(/obj/machinery/power/port_gen/large_altevian, "appearance_fuel_level", list("100" = list(APPEARANCE_OVERLAYS = list("alteviangen-fuel-100")), "66" = list(APPEARANCE_OVERLAYS = list("alteviangen-fuel-66")), "33" = list(APPEARANCE_OVERLAYS = list("alteviangen-fuel-33"))))

/// Fuel gauge step for the hopper overlay ("" when empty).
/obj/machinery/power/port_gen/large_altevian/proc/appearance_fuel_level()
	if(sheets > 75)
		return "100"
	if(sheets > 25)
		return "66"
	if(sheets > 0)
		return "33"
	return ""

/obj/machinery/power/rtg/antimatter_core
	name = "\improper Antique Anti-Matter Reactor"
	desc = "Reacts hydrogen and anti-hydrogen with a phoron moderator to produce near limitless power! The magnetic fields are prone to easily rupturing, so the reactor design never took off."
	icon = 'icons/am_engine.dmi'
	icon_state = "core_on"
	power_gen = 1000000 // 1MW
	irradiate = FALSE // Green energy!
	can_buckle = FALSE
	plane = ABOVE_MOB_PLANE
	layer = ABOVE_MOB_LAYER

/obj/machinery/power/rtg/antimatter_core/Initialize(mapload)
	. = ..()
	set_light(3, 6, "#66FFFF")

/obj/machinery/power/rtg/antimatter_core/proc/asplod()
	visible_message(span_danger("\The [src] ruptures!"), span_danger("You hear a loud reverberating bang!"))
	var/turf/T = get_turf(src)
	qdel(src)
	if(T)
		radiation_pulse(
			T,
			max_range = 50,
			threshold = RAD_HEAVY_INSULATION,
			chance = DEFAULT_RADIATION_CHANCE * 3,
			strength = power_gen * 0.01 ///1MW = 1000 rads. If you blow up a BLACK HOLE ENGINE, you deserve the radiation that comes with it.
		)
		empulse(T, 12, 14, 16, 18)
		explosion(T, 7, 12, 18, 20)
		new /obj/effect/bhole(T)

DAMAGE_REACTION(/obj/machinery/power/rtg/antimatter_core, DAMAGE_BLOB, TYPE_PROC_REF(/atom, damage_reaction_block))
DAMAGE_REACTION(/obj/machinery/power/rtg/antimatter_core, DAMAGE_EXPLOSION, PROC_REF(antimatter_core_blast))

/// A blast ruptures the reactor.
/obj/machinery/power/rtg/antimatter_core/proc/antimatter_core_blast(datum/damage_packet/packet)
	asplod()
	return DAMAGE_REACTION_BLOCK

/obj/machinery/power/rtg/antimatter_core/bullet_act(obj/item/projectile/Proj)
	. = ..()
	if(istype(Proj) && !Proj.nodamage && ((Proj.obj_damage_type() == BURN) || (Proj.obj_damage_type() == BRUTE)) && Proj.damage >= 20)
		log_and_message_admins("[ADMIN_LOOKUPFLW(Proj.firer)] triggered an antimatter core explosion at [x],[y],[z] via projectile.", Proj.firer)
		asplod()


/// Its declared start condition (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/power/rtg/step_start_condition()
	return anchored

/// Its declared start condition (machine_pipeline.dm, materialize_wakes()).
/obj/machinery/power/port_gen/step_start_condition()
	return active

OWN(/obj/machinery/power/rtg/abductor, cell, OWN_CONTAINED)
