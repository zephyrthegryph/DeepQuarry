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

	var/active = 0
	var/power_gen = 5000
	var/recent_fault = 0
	var/power_output = 1

/obj/machinery/power/port_gen/proc/IsBroken()
	return (stat & (BROKEN|EMPED))

/obj/machinery/power/port_gen/proc/HasFuel() //Placeholder for fuel check.
	return 1

/obj/machinery/power/port_gen/proc/UseFuel() //Placeholder for fuel use.
	return

/obj/machinery/power/port_gen/proc/DropFuel()
	return

/obj/machinery/power/port_gen/proc/handleInactive()
	return

/obj/machinery/power/port_gen/proc/TogglePower()
	if(active)
		active = FALSE
		update_icon()
		// soundloop.stop()
	else if(HasFuel())
		active = TRUE
		update_icon()
		// soundloop.start()

/obj/machinery/power/port_gen/process()
	if(active && HasFuel() && !IsBroken() && anchored && powernet)
		add_avail(power_gen * power_output)
		UseFuel()
	else
		active = FALSE
		update_icon()
		handleInactive()

/obj/machinery/power/port_gen/update_icon()
	if(active)
		icon_state = "[initial(icon_state)]on"
	else
		icon_state = initial(icon_state)

/obj/machinery/power/powered()
	return 1 //doesn't require an external power source

/obj/machinery/power/port_gen/attack_hand(mob/user as mob)
	if(..())
		return
	if(!anchored)
		return

/obj/machinery/power/port_gen/examine(mob/user)
	. = ..()
	if(Adjacent(user)) //It literally has a light on the sprite, are you sure this is necessary?
		if(active)
			. += span_notice("The generator is on.")
		else
			. += span_notice("The generator is off.")

/obj/machinery/power/port_gen/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	var/duration = 6000 //ten minutes
	switch(severity)
		if(EMP_HEAVY)
			stat |= BROKEN
			if(prob(75)) explode()
		if(EMP_MEDIUM)
			if(prob(50)) stat |= BROKEN
			if(prob(10)) explode()
		if(EMP_LIGHT)
			if(prob(25)) stat |= BROKEN
			duration = 300
		if(EMP_HARMLESS)
			if(prob(10)) stat |= BROKEN
			duration = 300

	stat |= EMPED
	if(duration)
		spawn(duration)
			stat &= ~EMPED

/obj/machinery/power/port_gen/proc/explode()
	explosion(src.loc, -1, 3, 5, -1)
	qdel(src)

#define TEMPERATURE_DIVISOR 40
#define TEMPERATURE_CHANGE_MAX 20

//A power generator that runs on solid plasma sheets.
/obj/machinery/power/port_gen/pacman
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
	if(anchored)
		connect_to_network()

/obj/machinery/power/port_gen/pacman/Destroy()
	DropFuel()
	return ..()

/obj/machinery/power/port_gen/pacman/dismantle()
	while( sheets > 0 )
		DropFuel()
	return ..()

/obj/machinery/power/port_gen/pacman/RefreshParts()
	var/temp_rating = 0
	for(var/obj/item/stock_parts/SP in component_parts)
		if(istype(SP, /obj/item/stock_parts/matter_bin))
			max_sheets = SP.rating * SP.rating * 50
		else if(istype(SP, /obj/item/stock_parts/micro_laser) || istype(SP, /obj/item/stock_parts/capacitor))
			temp_rating += SP.rating

	power_gen = round(initial(power_gen) * (max(2, temp_rating) / 2))

	dq_apply_material_synergies(src)
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
		var/ambient = environment.temperature - T20C
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
		var/ambient = environment.temperature - T20C
		cooling_temperature += ambient*ratio

	if(temperature > cooling_temperature)
		var/temp_loss = (temperature - cooling_temperature)/TEMPERATURE_DIVISOR
		temp_loss = between(2, round(temp_loss, 1), TEMPERATURE_CHANGE_MAX)
		temperature = max(temperature - temp_loss, cooling_temperature)

	if(overheating)
		overheating--
		update_icon() //Port RS PR #484

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

/obj/machinery/power/port_gen/pacman/emag_act(remaining_charges, mob/user)
	if (active && prob(25))
		explode() //if they're foolish enough to emag while it's running

	if (!emagged)
		emagged = 1
		return 1

/obj/machinery/power/port_gen/pacman/attackby(obj/item/O, mob/user)
	if(istype(O, sheet_path))
		var/obj/item/stack/addstack = O
		var/amount = min((max_sheets - sheets), addstack.get_amount())
		if(amount < 1)
			to_chat(user, span_warning("The [src.name] is full!"))
			return
		to_chat(user, span_notice("You add [amount] sheet\s to the [src.name]."))
		sheets += amount
		addstack.use(amount)
		return
	else if(!active)
		if(O.has_tool_quality(TOOL_WRENCH))
			if(!anchored)
				connect_to_network()
				to_chat(user, span_notice("You secure the generator to the floor."))
			else
				disconnect_from_network()
				to_chat(user, span_notice("You unsecure the generator from the floor."))
			playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
			anchored = !anchored
			return
		else if(default_deconstruction_screwdriver(user, O))
			return
		else if(default_deconstruction_crowbar(user, O))
			return
		else if(default_part_replacement(user, O))
			return
	return ..()

/obj/machinery/power/port_gen/pacman/attack_hand(mob/user)
	..()
	if (!anchored)
		return
	tgui_interact(user)

/obj/machinery/power/port_gen/pacman/attack_ai(mob/user as mob)
	tgui_interact(user)

/obj/machinery/power/port_gen/tgui_status(mob/user, datum/tgui_state/state)
	if(IsBroken())
		return STATUS_CLOSE
	return ..()

/obj/machinery/power/port_gen/pacman/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PortableGenerator", name)
		ui.open()

/obj/machinery/power/port_gen/pacman/tgui_data(mob/user)
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

	data["anchored"] = anchored
	data["connected"] = (powernet == null ? 0 : 1)
	data["ready_to_boot"] = anchored && HasFuel()
	data["power_generated"] = DisplayPower(power_gen)
	data["power_output"] = DisplayPower(power_gen * power_output)
	data["unsafe_output"] = power_output > max_safe_output
	data["power_available"] = (powernet == null ? 0 : DisplayPower(avail()))
	data["temperature_current"] = temperature
	data["temperature_max"] = max_temperature
	data["temperature_overheat"] = overheating
	// 1 sheet = 1000cm3?

	return data

/obj/machinery/power/port_gen/pacman/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return

	add_fingerprint(ui.user)
	switch(action)
		if("toggle_power")
			TogglePower()
			. = TRUE

		if("eject")
			if(!active)
				DropFuel()
				. = TRUE

		if("lower_power")
			if(power_output > 1)
				power_output--
				. = TRUE

		if("higher_power")
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


// === merged from port_gen_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/machinery/power/port_gen/pacman/super/potato
	name = "nuclear reactor"
	desc = "PTTO-3, an industrial all-in-one nuclear power plant by Neo-Chernobyl GmbH. It uses uranium as a fuel source. Rated for 200 kW max safe output."
	icon = 'icons/obj/power.dmi'
	icon_state = "potato"
	time_per_sheet = 1152 //same power output, but a 50 sheet stack will last 4 hours at max safe power
	power_gen = 50000 //watts
	anchored = TRUE

//Port Start, RS PR #484
/obj/machinery/power/port_gen/pacman/super/potato/Destroy()
	. = ..()
	cut_overlays() // sanity checks
	set_light(0)

/obj/machinery/power/port_gen/pacman/super/potato/update_icon()
	cut_overlays()
	set_light(0)
	//if there was an unexploded broken state, this is where it would go. + return
	if(active && !overheating)
		icon_state = "potatoon"
		var/mutable_appearance/reactorglow = mutable_appearance(icon, "eggrad", alpha = 90) //v.faint glow for reasons. the reasons being it's producing radiation as per code
		add_overlay(reactorglow)
		set_light(l_range = 2, l_power = 2, l_color = "#A8B0F8")
		return
	else if(overheating)	//The warp core is overloading, Captain!
		icon_state = "potatodanger"	//show that it's angry, even when it's off. something something subroutine. Visual feedback!
		if(active)	//but only glow if it's also still on, since the reaction is ongoing.
			var/mutable_appearance/reactorglow = mutable_appearance(icon, "eggrad", alpha = 190) //more intense glow, lightings
			add_overlay(reactorglow)
			set_light(l_range = 5, l_power = 4, l_color = "#A8B0F8")
		return
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
	connect_to_network()
	if(mapload)
		return INITIALIZE_HINT_LATELOAD

/obj/machinery/power/rtg/LateInitialize()
	apply_mapped_upgrades()

/obj/machinery/power/rtg/apply_mapped_upgrades()
	// Detect new parts placed by mappers
	var/list/parts_found = list()
	for(var/i = 1, i <= loc.contents.len, i++)
		var/obj/item/W = loc.contents[i]
		if(istype(W, /obj/item/stock_parts/capacitor))
			parts_found.Add(W)
		if(istype(W, /obj/item/stock_parts/micro_laser))
			parts_found.Add(W)

	// Wipe old parts for new ones!
	if(parts_found.len == 0)
		return
	if(locate(/obj/item/stock_parts/capacitor) in parts_found)
		while(TRUE)
			var/obj/item/stock_parts/capacitor/C = locate(/obj/item/stock_parts/capacitor) in component_parts
			if(isnull(C))
				break
			component_parts.Remove(C)
			qdel(C)
	if(locate(/obj/item/stock_parts/micro_laser) in parts_found)
		while(TRUE)
			var/obj/item/stock_parts/micro_laser/M = locate(/obj/item/stock_parts/micro_laser) in component_parts
			if(isnull(M))
				break
			component_parts.Remove(M)
			qdel(M)

	// Rebuild from mapper's parts
	for(var/i = 1, i <= parts_found.len, i++)
		var/obj/item/W = parts_found[i]
		component_parts.Add(W)
		W.forceMove(src)
	RefreshParts()

/obj/machinery/power/rtg/process()
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
	var/part_level = 0
	for(var/obj/item/stock_parts/SP in component_parts)
		part_level += SP.rating

	power_gen = initial(power_gen) * part_level

	dq_apply_material_synergies(src)
/obj/machinery/power/rtg/examine(mob/user)
	. = ..()
	if(Adjacent(user, src) || isobserver(user))
		. += span_notice("The status display reads: Power generation now at <b>[power_gen*0.001]</b>kW.")

/obj/machinery/power/rtg/attackby(obj/item/I, mob/user, params)
	if(default_deconstruction_screwdriver(user, I))
		return
	else if(default_deconstruction_crowbar(user, I))
		return
	else if(default_part_replacement(user, I))
		return
	return ..()

/obj/machinery/power/rtg/update_icon()
	if(panel_open)
		icon_state = "[initial(icon_state)]-open"
	else
		icon_state = initial(icon_state)

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
	dq_apply_material_synergies(src)
	return
/obj/machinery/power/rtg/fake_gen/attackby(obj/item/I, mob/user, params)
	return
/obj/machinery/power/rtg/fake_gen/update_icon()
	return

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

	dq_apply_material_synergies(src)
/obj/machinery/power/rtg/abductor/proc/asplod()
	if(going_kaboom)
		return
	going_kaboom = TRUE
	visible_message(span_danger("\The [src] lets out an shower of sparks as it starts to lose stability!"),\
		span_warningplain("You hear a loud electrical crack!"))
	playsound(src, 'sound/effects/lightningshock.ogg', 100, 1, extrarange = 5)
	tesla_zap(src, 5, power_gen * 0.05, current_jumps = 1)
	addtimer(CALLBACK(GLOBAL_PROC, PROC_REF(explosion), get_turf(src), 2, 3, 4, 8), 100) // Not a normal explosion.

/obj/machinery/power/rtg/abductor/bullet_act(obj/item/projectile/Proj)
	. = ..()
	if(!going_kaboom && istype(Proj) && !Proj.nodamage && ((Proj.damage_type == BURN) || (Proj.damage_type == BRUTE)))
		log_and_message_admins("[ADMIN_LOOKUPFLW(Proj.firer)] triggered an Abductor Core explosion at [x],[y],[z] via projectile.", Proj.firer)
		asplod()

/obj/machinery/power/rtg/abductor/attack_hand(mob/living/user)
	if(!istype(user) || (. = ..()))
		return

	if(cell)
		cell.forceMove(get_turf(src))
		user.put_in_active_hand(cell)
		cell = null
		state_change = TRUE
		RefreshParts()
		update_icon()
		playsound(src, 'sound/effects/metal_close.ogg', 50, 1)
		return TRUE

/obj/machinery/power/rtg/abductor/attackby(obj/item/I, mob/user, params)
	state_change = TRUE //Can't tell if parent did something
	if(istype(I, /obj/item/cell/void) && !cell)
		user.remove_from_mob(I)
		I.forceMove(src)
		cell = I
		RefreshParts()
		update_icon()
		playsound(src, 'sound/effects/metal_close.ogg', 50, 1)
		return
	return ..()

/obj/machinery/power/rtg/abductor/update_icon()
	if(!state_change)
		return //Stupid cells constantly update our icon so trying to be efficient

	if(cell)
		if(panel_open)
			icon_state = "[icon_base]-open"
		else
			icon_state = "[icon_base]"
	else
		icon_state = "[icon_base]-nocell"

	state_change = FALSE

/obj/machinery/power/rtg/abductor/blob_act(obj/structure/blob/B)
	asplod()

/obj/machinery/power/rtg/abductor/ex_act()
	if(going_kaboom)
		qdel(src)
	else
		asplod()

/obj/machinery/power/rtg/abductor/fire_act(exposed_temperature, exposed_volume)
	asplod()

// Comes with an installed cell
/obj/machinery/power/rtg/abductor/built
	icon_state = "core"

/obj/machinery/power/rtg/abductor/built/Initialize(mapload)
	. = ..()
	cell = new(src)
	RefreshParts()

// Bloo version
/obj/machinery/power/rtg/abductor/hybrid
	icon_state = "coreb-nocell"
	icon_base = "coreb"
	circuit = /obj/item/circuitboard/machine/abductor/core/hybrid

/obj/machinery/power/rtg/abductor/hybrid/built
	icon_state = "coreb"

/obj/machinery/power/rtg/abductor/hybrid/built/Initialize(mapload)
	. = ..()
	cell = new /obj/item/cell/void/hybrid(src)
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
	playsound(src, 'sound/effects/lightningshock.ogg', 100, 1, extrarange = 5)
	var/turf/T = get_turf(src)
	qdel(src)
	new /obj/singularity(T)

/obj/machinery/power/rtg/kugelblitz/blob_act(obj/structure/blob/B)
	asplod()

/obj/machinery/power/rtg/kugelblitz/ex_act()
	asplod()

/obj/machinery/power/rtg/kugelblitz/fire_act(exposed_temperature, exposed_volume)
	asplod()

/obj/machinery/power/rtg/kugelblitz/bullet_act(obj/item/projectile/Proj)
	. = ..()
	if(istype(Proj) && !Proj.nodamage && ((Proj.damage_type == BURN) || (Proj.damage_type == BRUTE)) && Proj.damage >= 20)
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

/obj/machinery/power/rtg/reg/Destroy()
	. = ..()

/obj/machinery/power/rtg/reg/user_buckle_mob(mob/living/M, mob/user, forced = FALSE, silent = TRUE)
	. = ..()
	M.pixel_y = 8
	M.visible_message(span_notice("\The [M], hops up onto \the [src] and begins running!"))

/obj/machinery/power/rtg/reg/unbuckle_mob(mob/living/buckled_mob, force = FALSE)
	. = ..()
	buckled_mob.pixel_y = buckled_mob.default_pixel_y

/obj/machinery/power/rtg/reg/RefreshParts()
	var/n = 0
	for(var/obj/item/stock_parts/SP in component_parts)
		n += SP.rating
	part_mult = n

	dq_apply_material_synergies(src)
/obj/machinery/power/rtg/reg/attackby(obj/item/I, mob/user, params)
	pixel_x = -32
	if(default_deconstruction_screwdriver(user, I))
		return
	else if(default_deconstruction_crowbar(user, I))
		return
	return ..()

/obj/machinery/power/rtg/reg/update_icon()
	pixel_x = -32
	if(panel_open)
		icon_state = "reg-o"
	else if(buckled_mobs && buckled_mobs.len > 0)
		icon_state = "reg-a"
	else
		icon_state = "reg"

/obj/machinery/power/rtg/reg/process()
	..()
	if(buckled_mobs && buckled_mobs.len > 0)
		for(var/mob/living/L in buckled_mobs)
			runner_process(L)
	else
		power_gen = 0
	update_icon()

/obj/machinery/power/rtg/reg/proc/runner_process(mob/living/runner)
	if(runner.stat != CONSCIOUS)
		unbuckle_mob(runner)
		runner.visible_message(span_warning("\The [runner], topples off of \the [src]!"))
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
			runner.visible_message(span_notice("\The [runner], panting and exhausted hops off of \the [src]!"))
	if(part_mult > 1)
		cool_rotations += (cool_rotations * (part_mult - 1)) / 4
	power_gen = cool_rotations
	runner.nutrition -= nutrition_drain

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

/obj/machinery/power/port_gen/large_altevian/Initialize(mapload)
	.=..()
	if(anchored)
		connect_to_network()

/obj/machinery/power/port_gen/large_altevian/Destroy()
	DropFuel()
	return ..()

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

/obj/machinery/power/port_gen/large_altevian/attackby(obj/item/O as obj, mob/user as mob)
	if(istype(O, sheet_path))
		var/obj/item/stack/addstack = O
		var/amount = min((max_sheets - sheets), addstack.get_amount())
		if(amount < 1)
			to_chat(user, span_warning("The [src.name] is full!"))
			return
		to_chat(user, span_notice("You add [amount] sheet\s to the [src.name]."))
		sheets += amount
		addstack.use(amount)
		update_icon()
		return
	return ..()

/obj/machinery/power/port_gen/large_altevian/attack_hand(mob/user as mob)
	..()
	if (!anchored)
		return
	TogglePower()

/obj/machinery/power/port_gen/large_altevian/attack_ai(mob/user as mob)
	TogglePower()

/obj/machinery/power/port_gen/large_altevian/update_icon()
	..()

	cut_overlays()
	if(sheets > 75)
		add_overlay("alteviangen-fuel-100")
	else if(sheets > 25)
		add_overlay("alteviangen-fuel-66")
	else if(sheets > 0)
		add_overlay("alteviangen-fuel-33")

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

/obj/machinery/power/rtg/antimatter_core/blob_act(obj/structure/blob/B)
	return

/obj/machinery/power/rtg/antimatter_core/ex_act()
	asplod()

/obj/machinery/power/rtg/antimatter_core/fire_act(exposed_temperature, exposed_volume)
	return

/obj/machinery/power/rtg/antimatter_core/bullet_act(obj/item/projectile/Proj)
	. = ..()
	if(istype(Proj) && !Proj.nodamage && ((Proj.damage_type == BURN) || (Proj.damage_type == BRUTE)) && Proj.damage >= 20)
		log_and_message_admins("[ADMIN_LOOKUPFLW(Proj.firer)] triggered an antimatter core explosion at [x],[y],[z] via projectile.", Proj.firer)
		asplod()
