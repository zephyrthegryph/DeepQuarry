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

// The portable generators (doc/rewrite/final_api.html section 16): switched on and fuelled, bolted down and wired, every machine service
// interval a generator burns its fuel and supplies power_gen * power_output W to its cable network (a persistent supply: set_power_supply());
// off, it cools down on the same step until it is cold. A pulse knocks it out for 10 minutes and may break it or blow it up.
CAPABILITIES(/obj/machinery/power/port_gen)
	emp_disable(10 MINUTES)
	extend(/datum/act/hit/emp, instead(then(PROC_REF(port_gen_emp_fault))))
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(gen_step)), when = PROC_REF(has_work))

/obj/machinery/power/port_gen/proc/IsBroken()
	return broken_now() || emp_disabled(src)

/obj/machinery/power/port_gen/proc/HasFuel() //Placeholder for fuel check.
	return 1

/obj/machinery/power/port_gen/proc/UseFuel() //Placeholder for fuel use.
	return

/obj/machinery/power/port_gen/proc/DropFuel()
	return

/// Off and cooling: TRUE while it still has cooling to do.
/obj/machinery/power/port_gen/proc/handleInactive()
	return FALSE

/// Off and cold, it has nothing to do (cooling_needed(): a hot generator cools on its step).
/obj/machinery/power/port_gen/proc/cooling_needed()
	return FALSE

/// Its step runs while it is on, or still has heat to lose.
/obj/machinery/power/port_gen/proc/has_work(datum/act/A)
	return active || cooling_needed()

/obj/machinery/power/port_gen/proc/TogglePower()
	if(active)
		set_active(FALSE)
	else if(HasFuel())
		set_active(TRUE)

/// One step: running, it supplies and burns fuel; otherwise it stops supplying and cools.
/obj/machinery/power/port_gen/proc/gen_step(datum/act/timer/A)
	if(active && HasFuel() && !IsBroken() && anchored && power_region)
		set_power_supply(power_gen * power_output)
		UseFuel()
		return
	set_active(FALSE)
	set_power_supply(0)
	handleInactive()

/obj/machinery/power/port_gen/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][active ? "on" : ""]")

/obj/machinery/power/powered()
	return 1 //doesn't require an external power source

/obj/machinery/power/port_gen/examine(mob/user)
	. = ..()
	if(Adjacent(user)) //It literally has a light on the sprite, are you sure this is necessary?
		if(active)
			. += span_notice("The generator is on.")
		else
			. += span_notice("The generator is off.")

/// A pulse can break the generator outright, or blow it up (the outage itself is emp_disable()). The pulse goes on unless it blew up.
/obj/machinery/power/port_gen/proc/port_gen_emp_fault(datum/act/hit/emp/A)
	. = HOOK_DECLINE
	var/datum/damage_packet/packet = A.packet
	switch(packet.severity)
		if(EMP_HEAVY)
			atom_break()
			if(prob(75))
				explode()
				return TRUE
		if(EMP_MEDIUM)
			if(prob(50)) atom_break()
			if(prob(10))
				explode()
				return TRUE
		if(EMP_LIGHT)
			if(prob(25)) atom_break()
		if(EMP_HARMLESS)
			if(prob(10)) atom_break()

/obj/machinery/power/port_gen/proc/explode()
	explosion(src.loc, -1, 3, 5, -1)
	destroyed(src)

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
TRACKED(/obj/machinery/power/port_gen/pacman, overheating)

TRACKED(/obj/machinery/power/port_gen/pacman, sheets)
TRACKED(/obj/machinery/power/port_gen/pacman, max_sheets)

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
		set_max_sheets(bin_rating * bin_rating * 50)
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
		set_sheets(sheets - S.get_amount())

/obj/machinery/power/port_gen/pacman/UseFuel()

	//how much material are we using this iteration?
	var/needed_sheets = power_output / time_per_sheet

	//HasFuel() should guarantee us that there is enough fuel left, so no need to check that
	//the only thing we need to worry about is if we are going to rollover to the next sheet
	if (needed_sheets > sheet_left)
		set_sheets(sheets - 1)
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
		set_overheating(overheating - 1)
		changed(src) //Port RS PR #484

/// The temperature it cools to while off: 20, plus the room's offset from 20 C scaled by its pressure.
/obj/machinery/power/port_gen/pacman/proc/cooling_temperature()
	var/cooling_temperature = 20
	var/datum/gas_mixture/environment = loc?.return_air()
	if(environment)
		var/ratio = min(environment.return_pressure()/ONE_ATMOSPHERE, 1)
		var/ambient = environment.return_temperature() - T20C
		cooling_temperature += ambient*ratio
	return cooling_temperature

/obj/machinery/power/port_gen/pacman/cooling_needed()
	return overheating > 0 || temperature > cooling_temperature() + 0.1

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
		set_overheating(overheating - 1)
		changed(src) //Port RS PR #484
	return temperature > cooling_temperature + 0.1 || overheating > 0

/obj/machinery/power/port_gen/pacman/proc/overheat()
	set_overheating(overheating + 1)
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

	set_sheets(0)
	sheet_left = 0
	..()

/// A card lets the output go to 2.5 times its maximum; on a running generator it may set it off.
/obj/machinery/power/port_gen/pacman/proc/on_emag(datum/act/op/A)
	if(active && prob(25))
		explode() //if they're foolish enough to emag while it's running
	return OP_OK

/obj/machinery/power/port_gen/pacman/proc/sheet_match(datum/act/op/A)
	return istype(A.held, sheet_path)

/obj/machinery/power/port_gen/pacman/proc/has_room(datum/act/op/A)
	return sheets < max_sheets

/obj/machinery/power/port_gen/pacman/proc/sheets_added(datum/act/op/A)
	var/obj/item/stack/addstack = A.held
	var/amount = min((max_sheets - sheets), addstack.get_amount())
	to_chat(A.actor, span_notice("You add [amount] sheet\s to the [src.name]."))
	set_sheets(sheets + amount)
	addstack.use(amount)
	return OP_OK

/obj/machinery/power/port_gen/pacman/proc/screwdriver_used(datum/act/op/A)
	if(active)
		return OP_OK
	return OP_DECLINE

/obj/machinery/power/port_gen/pacman/proc/crowbar_used(datum/act/op/A)
	if(active)
		return OP_OK
	return OP_DECLINE

/// Bolted down it joins its cable network; loose it leaves it.
/obj/machinery/power/port_gen/pacman/proc/anchoring_changed(datum/act/A)
	if(anchored)
		connect_to_network()
	else
		disconnect_from_network()

/obj/machinery/power/port_gen/pacman/proc/not_broken(datum/act/A)
	return !IsBroken()

MSG_DEF_SELF(pacman/full, "It's full.")
MSG_DEF_SELF(pacman/running, "Turn it off first.")
MSG_DEF_SELF(pacman/broken, "It seems to have broken down.")

// The PACMAN: sheets of its fuel in the hopper, a window for its switch and output, a wrench to bolt it (not while it runs), a part replacer
// (not while it runs), and an emag that lifts its output limit.
CAPABILITIES(/obj/machinery/power/port_gen/pacman)
	anchor()
	extend("anchor.toggle", needs(req_is(nameof(active), FALSE, because = MSG(pacman/running))))
	on_change(nameof(anchored), ANY, then(PROC_REF(anchoring_changed)))
	part_replacement()
	extend("part_replacement.replace", needs(req_is(nameof(active), FALSE, because = MSG(pacman/running))))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)
	op("add_fuel", item(/obj/item/stack/material), label("Add fuel"), wait(0), when(req_bool(PROC_REF(sheet_match))),
		needs(req_bool(PROC_REF(has_room), because = MSG(pacman/full))), then(PROC_REF(sheets_added)))
	interface("PortableGenerator")
	extend("ui_open", when(nameof(anchored)))
	extend(TAG_UI, needs(req_bool(PROC_REF(not_broken), because = MSG(pacman/broken))))
	op("toggle_power", ui_act("toggle_power"), then(PROC_REF(ui_act_toggle_power)))
	op("eject", ui_act("eject"), then(PROC_REF(ui_act_eject)))
	op("lower_power", ui_act("lower_power"), then(PROC_REF(ui_act_lower_power)))
	op("higher_power", ui_act("higher_power"), then(PROC_REF(ui_act_higher_power)))
	op("use_crowbar", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(crowbar_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	default_parts()

/obj/machinery/power/port_gen/pacman/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["anchored"] = anchored
	data["temperature_current"] = temperature
	data["temperature_max"] = max_temperature
	data["temperature_overheat"] = overheating
	data["active"] = active

	data["is_ai"] = !A.actor?.Adjacent(src) // worked from afar (a silicon's link): no hands on the hopper

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

/obj/machinery/power/port_gen/pacman/proc/ui_act_toggle_power(datum/act/op/A)
	add_fingerprint(A.actor)
	TogglePower()
	. = TRUE

/obj/machinery/power/port_gen/pacman/proc/ui_act_eject(datum/act/op/A)
	add_fingerprint(A.actor)
	if(!active)
		DropFuel()
		. = TRUE

/obj/machinery/power/port_gen/pacman/proc/ui_act_lower_power(datum/act/op/A)
	add_fingerprint(A.actor)
	if(power_output > 1)
		power_output--
		. = TRUE

/obj/machinery/power/port_gen/pacman/proc/ui_act_higher_power(datum/act/op/A)
	add_fingerprint(A.actor)
	if(power_output < max_power_output || (is_emagged(src) && power_output < round(max_power_output * 2.5)))
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
	destroyed(src)

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
	destroyed(src)

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

/obj/machinery/power/port_gen/pacman/super/potato/draw(datum/look/look)
	..()
	if(active && !overheating)
		look.state("potatoon")
		look.overlay(mutable_appearance(icon, "eggrad", alpha = 90)) //v.faint glow for reasons. the reasons being it's producing radiation as per code
		look.light(2, 2, "#A8B0F8")
	else if(overheating)	//The warp core is overloading, Captain!
		look.state("potatodanger")	//show that it's angry, even when it's off. something something subroutine. Visual feedback!
		if(active)	//but only glow if it's also still on, since the reaction is ongoing.
			look.overlay(mutable_appearance(icon, "eggrad", alpha = 190)) //more intense glow, lightings
			look.light(5, 4, "#A8B0F8")
	else	//off and it isn't angry, so we just vibe as 'off'
		look.state(initial(icon_state))
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

// The RTG (doc/rewrite/final_api.html section 16): bolted down, it supplies power_gen W to its cable network every machine service interval
// (rtg_step()), and irradiates its surroundings while its panel is open.
CAPABILITIES(/obj/machinery/power/rtg)
	after_init(0, then(PROC_REF(mapped_upgrades_after_init)))
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(rtg_step)), when = nameof(anchored))
	part_replacement()
	default_parts()

/// A mapped RTG takes the parts laid on its tile.
/obj/machinery/power/rtg/proc/mapped_upgrades_after_init(datum/act/timer/A)
	if(!A.mapload)
		return
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
			rel_take(src, nameof(component_parts), C)
			consumed(C, src)
	if(locate_in_list(parts_found, /obj/item/stock_parts/micro_laser))
		while(TRUE)
			var/obj/item/stock_parts/micro_laser/M = locate_in_list(component_parts, /obj/item/stock_parts/micro_laser)
			if(isnull(M))
				break
			rel_take(src, nameof(component_parts), M)
			consumed(M, src)

	// Rebuild from mapper's parts
	for(var/i = 1, i <= parts_found.len, i++)
		var/obj/item/W = parts_found[i]
		rel_add(src, nameof(component_parts), W)
		move_into(src, CONTAINER_SLOT_INTERNALS, W)
	RefreshParts()

/// One step: its supply for the next power step, and its radiation while open.
/obj/machinery/power/rtg/proc/rtg_step(datum/act/timer/A)
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

/obj/machinery/power/rtg/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][panel_open ? "-open" : ""]")

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
/// No parts to replace.
CAPABILITIES(/obj/machinery/power/rtg/fake_gen)
	without("part_replacement.replace")

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
	/// The cell a core placed built starts with.
	var/starting_cell

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
	after(null, 10 SECONDS, GLOBAL_PROC_REF(explosion), with = list(get_turf(src), 2, 3, 4, 8)) // Not a normal explosion.

/obj/machinery/power/rtg/abductor/bullet_act(obj/item/projectile/Proj)
	. = ..()
	if(!QDELETED(src) && !going_kaboom && istype(Proj) && !Proj.nodamage && ((Proj.obj_damage_type() == BURN) || (Proj.obj_damage_type() == BRUTE)))
		log_and_message_admins("[ADMIN_LOOKUPFLW(Proj.firer)] triggered an Abductor Core explosion at [x],[y],[z] via projectile.", Proj.firer)
		asplod()

CAPABILITIES(/obj/machinery/power/rtg/abductor)
	owns_one(nameof(cell), /obj/item/cell/void, starts = nameof(starting_cell))
	op("take_cell", hand(), label("Take out"), wait(0), when(req_empty_hand()), when(nameof(cell)), needs(req_operable()), then(PROC_REF(cell_taken)))
	op("insert_cell", item(/obj/item/cell/void), label("Insert void cell"), wait(0), when(cond_not(nameof(cell))), put_in(nameof(cell)), then(PROC_REF(cell_inserted)))
	extend(/datum/act/hit/blob, instead(then(PROC_REF(void_core_hit_asplod))))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(void_core_blast))))

/obj/machinery/power/rtg/abductor/proc/cell_taken(datum/act/op/A)
	var/obj/item/cell/void/taken = rel_take(src, nameof(cell))
	taken.forceMove(get_turf(src))
	A.actor.put_in_active_hand(taken)
	state_change = TRUE
	RefreshParts()
	play_sfx(src, SFX_EFFECTS_METAL_CLOSE)
	return OP_OK

/obj/machinery/power/rtg/abductor/proc/cell_inserted(datum/act/op/A)
	RefreshParts()
	play_sfx(src, SFX_EFFECTS_METAL_CLOSE)
	return OP_OK

/obj/machinery/power/rtg/abductor/draw(datum/look/look)
	..()
	look.state("[icon_base][appearance_core_suffix()]")

/// Sprite suffix: no cell, open panel, or closed.
/obj/machinery/power/rtg/abductor/proc/appearance_core_suffix()
	if(!cell)
		return "-nocell"
	return panel_open ? "-open" : ""

/// A blob arms the core instead of damaging it.
/obj/machinery/power/rtg/abductor/proc/void_core_hit_asplod(datum/act/hit/blob/A)
	asplod()
	return TRUE

/// A blast arms the core, or finishes one already armed.
/obj/machinery/power/rtg/abductor/proc/void_core_blast(datum/act/hit/explosion/A)
	// Exception: asplod() is this volatile core's already-armed detonation lifecycle.
	// qdel here only completes that lifecycle; ordinary shell damage enters through
	// the inherited obj_integrity projectile path before arming the core.
	if(going_kaboom)
		spent(src)
	else
		asplod()
	return TRUE

/// Heat behaviour rule: fire sets off a void core.
/obj/machinery/power/rtg/abductor/proc/rule_asplod(datum/rule/rule)
	asplod()

// Comes with an installed cell
/obj/machinery/power/rtg/abductor/built
	icon_state = "core"

/obj/machinery/power/rtg/abductor/built
	starting_cell = /obj/item/cell/void

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

/obj/machinery/power/rtg/abductor/hybrid/built
	starting_cell = /obj/item/cell/void/hybrid

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
	spent(src)
	new /obj/singularity(T)

CAPABILITIES(/obj/machinery/power/rtg/kugelblitz)
	extend(/datum/act/hit/blob, instead(then(PROC_REF(kugelblitz_hit_asplod))))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(kugelblitz_hit_asplod))))

/// A blob or a blast collapses the containment.
/obj/machinery/power/rtg/kugelblitz/proc/kugelblitz_hit_asplod(datum/act/A)
	asplod()
	return TRUE

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

/obj/machinery/power/rtg/reg/draw(datum/look/look)
	..()
	if(panel_open)
		look.state("reg-o")
	else if(length(src?.buckled_mob_list()) > 0)
		look.state("reg-a")
	else
		look.state("reg")

/obj/machinery/power/rtg/reg/rtg_step(datum/act/timer/A)
	..()
	if(length(src?.buckled_mob_list()) > 0)
		for(var/mob/living/L in src?.buckled_mob_list())
			runner_process(L)
	else
		power_gen = 0

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
		set_sheets(sheets - S.get_amount())

/obj/machinery/power/port_gen/large_altevian/UseFuel()
	var/needed_sheets = power_output / time_per_sheet
	if (needed_sheets > sheet_left)
		set_sheets(sheets - 1)
		sheet_left = (1 + sheet_left) - needed_sheets
	else
		sheet_left -= needed_sheets

TRACKED(/obj/machinery/power/port_gen/large_altevian, sheets)
TRACKED(/obj/machinery/power/port_gen/large_altevian, max_sheets)

// The altevian reactor: its sheets, a hand (or a silicon's touch) that switches it, and its fuel gauge.
CAPABILITIES(/obj/machinery/power/port_gen/large_altevian)
	op("add_fuel", item(/obj/item/stack/material), label("Add fuel"), wait(0), when(req_bool(PROC_REF(sheet_match))),
		needs(req_bool(PROC_REF(has_room), because = MSG(pacman/full))), then(PROC_REF(sheets_added)))
	op("toggle", hand(), label("Toggle"), wait(0), when(req_empty_hand()), when(nameof(anchored)), then(PROC_REF(toggled)))
	extend("toggle", binds(remote()))

/obj/machinery/power/port_gen/large_altevian/proc/sheet_match(datum/act/op/A)
	return istype(A.held, sheet_path)

/obj/machinery/power/port_gen/large_altevian/proc/has_room(datum/act/op/A)
	return sheets < max_sheets

/obj/machinery/power/port_gen/large_altevian/proc/sheets_added(datum/act/op/A)
	var/obj/item/stack/addstack = A.held
	var/amount = min((max_sheets - sheets), addstack.get_amount())
	to_chat(A.actor, span_notice("You add [amount] sheet\s to the [src.name]."))
	set_sheets(sheets + amount)
	addstack.use(amount)
	return OP_OK

/obj/machinery/power/port_gen/large_altevian/proc/toggled(datum/act/op/A)
	TogglePower()
	return OP_OK

/obj/machinery/power/port_gen/large_altevian/draw(datum/look/look)
	..()
	var/level = appearance_fuel_level()
	look.overlay("alteviangen-fuel-[level]", when = level)

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

/obj/machinery/power/rtg/antimatter_core
	light_range = 3
	light_power = 6
	light_color = "#66FFFF"
	light_on = TRUE

/obj/machinery/power/rtg/antimatter_core/proc/asplod()
	visible_message(span_danger("\The [src] ruptures!"), span_danger("You hear a loud reverberating bang!"))
	var/turf/T = get_turf(src)
	spent(src)
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

CAPABILITIES(/obj/machinery/power/rtg/antimatter_core)
	extend(/datum/act/hit/blob, instead(then(PROC_REF(blob_shrugged))))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(antimatter_core_blast))))

/// A blob does nothing to it.
/obj/machinery/power/rtg/antimatter_core/proc/blob_shrugged(datum/act/A)
	return TRUE

/// A blast ruptures the reactor.
/obj/machinery/power/rtg/antimatter_core/proc/antimatter_core_blast(datum/act/A)
	asplod()
	return TRUE

/obj/machinery/power/rtg/antimatter_core/bullet_act(obj/item/projectile/Proj)
	. = ..()
	if(istype(Proj) && !Proj.nodamage && ((Proj.obj_damage_type() == BURN) || (Proj.obj_damage_type() == BRUTE)) && Proj.damage >= 20)
		log_and_message_admins("[ADMIN_LOOKUPFLW(Proj.firer)] triggered an antimatter core explosion at [x],[y],[z] via projectile.", Proj.firer)
		asplod()

