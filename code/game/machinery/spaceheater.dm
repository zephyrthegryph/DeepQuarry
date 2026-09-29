#define SHEATER_OFF 0
#define SHEATER_STANDBY 1
#define SHEATER_HEAT 2
#define SHEATER_COOL 3

#define DEFAULT_MIN_TEMP T0C
#define DEFAULT_MAX_TEMP T0C + 90
#define DEFAULT_HEATING_POWER 40000

/obj/machinery/space_heater
	anchored = FALSE
	density = TRUE
	icon = 'icons/obj/atmos.dmi'
	icon_state = "sheater0"
	name = "space heater"
	desc = "Made by Space Amish using traditional space techniques, this heater is guaranteed not to set the station on fire."

	light_system = STATIC_LIGHT // runtime cleanup
	light_range = 3
	light_power = 1
	light_on = FALSE

	var/obj/item/cell/cell
	var/cell_type = /obj/item/cell/high
	state = 0
	var/set_temperature = T0C + 20	//K
	var/min_temperature = DEFAULT_MIN_TEMP
	var/max_temperature = DEFAULT_MAX_TEMP
	var/heating_power = 40000
	var/power_efficiency = 1 //Inverse. The lower, the more power efficient we are.
	/// Fraction of the Carnot COP this heater's cooling side achieves (H4:
	/// the real Carnot-bounded COP formula lives once in Rust now,
	/// rust_core.md §15, replacing the old `removed.return_temperature() /
	/// T20C` approximation below).
	var/regulator_carnot_fraction = 0.4
	/// Upper bound on the pump's COP.
	var/regulator_max_cop = 25
	clicksound = SFX_SWITCH
	interact_offline = TRUE
	bubble_icon = "engineering"
	circuit = /obj/item/circuitboard/space_heater

// The cell comes from cell_type (null: none); icon_state follows state, the open-hatch overlay
// panel_open (doc/rewrite/declarative_lifecycle.md).
DECLARE_DEFAULT_CHILD(/obj/machinery/space_heater, "cell", "cell_type")
// Rows by state: SHEATER_OFF, SHEATER_STANDBY, SHEATER_HEAT, SHEATER_COOL.
DECLARE_APPEARANCE(/obj/machinery/space_heater, "state", list( 	"0" = list(APPEARANCE_ICON_STATE = "sheater0"), 	"1" = list(APPEARANCE_ICON_STATE = "sheater1"), 	"2" = list(APPEARANCE_ICON_STATE = "sheater2"), 	"3" = list(APPEARANCE_ICON_STATE = "sheater3") ))
DECLARE_APPEARANCE(/obj/machinery/space_heater, "panel_open", list("1" = list(APPEARANCE_OVERLAYS = list("sheater-open"))))
// Regulates the air while switched on (any state but SHEATER_OFF).
DECLARE_PERIODIC_WHILE(/obj/machinery/space_heater, MACHINE_PIPELINE, "state")

/obj/machinery/space_heater/Initialize(mapload)
	. = ..()
	default_apply_parts()
	update_icon()
	make_climbable()

/obj/machinery/space_heater/RefreshParts(limited = 0)
	min_temperature = DEFAULT_MIN_TEMP
	max_temperature = DEFAULT_MAX_TEMP
	heating_power = DEFAULT_HEATING_POWER
	power_efficiency = 1
	var/laser_over = get_part_rating(/obj/item/stock_parts/micro_laser) - get_part_count(/obj/item/stock_parts/micro_laser)
	heating_power += laser_over * 25000 // Increases the maximum heating/cooling possible. Doesn't affect the heat it pumps out/sucks in. That depends on the difference between the thermostat and the environment. This just clamps that temp change.
	var/manip_over = get_part_rating(/obj/item/stock_parts/manipulator) - get_part_count(/obj/item/stock_parts/manipulator)
	min_temperature -= manip_over * 23	//min_temperature starts at 273. A level 5 (omni) will decrease it by 92. -92 x 3 = 276, which we clamp to 0. It still sucks cooling down normal temp areas, but whatever it's a heater. Get a temp pump if you want to cool.
	max_temperature += manip_over * 121	//max_temperature starts at 363. A level 5 (omni) will increase it by 484. 484 x 3 = 1936. Giving us a total of 2299K/2026C.
	var/cap_over = get_part_rating(/obj/item/stock_parts/capacitor) - get_part_count(/obj/item/stock_parts/capacitor)
	power_efficiency -= cap_over * 0.06 //Four T2 parts = 24% more efficient. Four T5 parts = 96% more efficient
	min_temperature = max(1, min_temperature)
DECLARE_APPEARANCE_PROC(/obj/machinery/space_heater, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/space_heater/appearance_overlays()
	. = list()
	. += ..()
	switch(state)
		// start, fixing runtimes
		if(SHEATER_OFF)
			set_light(0)
			set_light_on(FALSE)
		if(SHEATER_STANDBY)
			set_light(0)
			set_light_on(FALSE)
		if(SHEATER_HEAT)
			set_light_color("#FFCC00")
			set_light(3)
			set_light_on(TRUE)
		if(SHEATER_COOL)
			set_light_color("#00ccff")
			set_light(3)
			set_light_on(TRUE)
		// end

/obj/machinery/space_heater/examine(mob/user)
	. = ..()

	. += "The heater is [state ? "on" : "off"] and the hatch is [panel_open ? "open" : "closed"]."
	if(panel_open)
		. += "The power cell is [cell ? "installed" : "missing"]."
	else
		. += "The charge meter reads [cell ? round(cell.percent(),1) : 0]%"
	return

/obj/machinery/space_heater/powered()
	if(cell && cell.charge)
		return 1
	return 0

/obj/machinery/space_heater/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/space_heater_insert_cell,
		/datum/interaction/machine_item/part_replacement,
		/datum/interaction/machine_hand/ungated/space_heater_interact,
	)
	..()

/// Old attackby: insert a power cell through the open hatch.
/datum/interaction/machine_item/space_heater_insert_cell
	id = "space_heater_insert_cell"
	name = "Insert power cell"
	held_type = /obj/item/cell
	requires = list(REQ_INTERACTION_REACH,
		REQ_ON(PRED_TARGET, /obj/machinery/space_heater/proc/hatch_open, "the hatch must be open to insert a power cell"),
		REQ_ON(PRED_TARGET, /obj/machinery/space_heater/proc/no_cell_installed, "there is already a power cell inside"))
	effect = /obj/machinery/space_heater/proc/interaction_insert_cell

/obj/machinery/space_heater/proc/hatch_open(mob/actor, atom/target, obj/item/held)
	return panel_open

/obj/machinery/space_heater/proc/no_cell_installed(mob/actor, atom/target, obj/item/held)
	return !cell

/obj/machinery/space_heater/proc/interaction_insert_cell(mob/user, obj/item/held, datum/interaction/interaction)
	var/obj/item/cell/C = held
	if(!own_set(src, nameof(src.cell), C, user = user))
		return TRUE
	C.add_fingerprint(user)
	act_message(user, src, MSG_SELF(span_notice("You insert the power cell into %T%.")), MSG_OTHERS(span_notice("%U% inserts a power cell into %T%.")))
	power_change()
	return TRUE

/// Old attack_hand: `add_fingerprint(user); interact(user)`, no gate (never called ..()).
/datum/interaction/machine_hand/ungated/space_heater_interact
	id = "space_heater_interact"
	name = "Use"
	category = INTERACTION_CAT_CONFIGURE
	effect = /obj/machinery/space_heater/proc/interaction_hand_interact

/obj/machinery/space_heater/proc/interaction_hand_interact(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	interact(user)
	return TRUE

/obj/machinery/space_heater/screwdriver_act(mob/user, obj/item/tool)
	set_panel_open(!panel_open)
	playsound(src, tool.usesound, 50, TRUE)
	act_message(user, src, MSG_SELF(span_notice("You [panel_open ? "open" : "close"] the hatch on %T%.")), \
		MSG_OTHERS(span_notice("%U% [panel_open ? "opens" : "closes"] the hatch on %T%.")))
	update_icon()
	if(!panel_open && user.check_current_machine(src))
		SStgui.close_uis(src)
		user.unset_machine()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/space_heater/interact(mob/user as mob)
	if(panel_open)
		tgui_interact(user)
	else
		set_state(state ? SHEATER_OFF : SHEATER_STANDBY)
		act_message(user, src, MSG_SELF(span_notice("You switch [state ? "on" : "off"] %T%.")),
			MSG_OTHERS(span_notice("%U% switches [state ? "on" : "off"] %T%.")))
	return

DECLARE_UI_STATE(/obj/machinery/space_heater, GLOB.tgui_physical_state)

/obj/machinery/space_heater/tgui_status(mob/user)
	if(!panel_open)
		return STATUS_CLOSE
	return ..()

DECLARE_UI(/obj/machinery/space_heater, "SpaceHeater")

UI_DATA_REPLACE(/obj/machinery/space_heater, "temp=set_temperature", "minTemp=min_temperature", "maxTemp=max_temperature:num", "merge:ui_data_obj_machinery_space_heater{cell:bool,power:num}")

/// The computed part of /obj/machinery/space_heater's window data (declared on its UI_DATA row).
/obj/machinery/space_heater/proc/ui_data_obj_machinery_space_heater(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["cell"] = !!cell
	data["power"] = round(cell?.percent(), 1)

	return data

/obj/machinery/space_heater/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!panel_open)
		return FALSE
	return TRUE

UI_ACT(/obj/machinery/space_heater, "temp", ui_act_temp, UI_ARG_NUM("newtemp"))
UI_ACT_PROC(/obj/machinery/space_heater, ui_act_temp)
	// limit to 0-90 degC
	set_temperature = clamp(params["newtemp"], min_temperature, max_temperature)
	. = TRUE

UI_ACT(/obj/machinery/space_heater, "cellremove", ui_act_cellremove)
UI_ACT_PROC(/obj/machinery/space_heater, ui_act_cellremove)
	if(cell && !ui.user.get_active_hand())
		act_message(ui.user, src, MSG_SELF(span_notice("You remove [cell] from %T%.")), MSG_OTHERS(span_notice("%U% removes [cell] from %T%.")))
		cell.update_icon()
		ui.user.put_in_hands(cell)
		cell.add_fingerprint(ui.user)
		own_take(src, "cell")
		power_change()
		. = TRUE

UI_ACT(/obj/machinery/space_heater, "cellinstall", ui_act_cellinstall)
UI_ACT_PROC(/obj/machinery/space_heater, ui_act_cellinstall)
	if(!cell)
		var/obj/item/cell/C = ui.user.get_active_hand()
		if(istype(C))
			if(!own_set(src, nameof(src.cell), C, user = ui.user))
				return
			C.add_fingerprint(ui.user)
			power_change()
			act_message(ui.user, src, MSG_SELF(span_notice("You insert %I% into %T%.")), \
				MSG_OTHERS(span_notice("%U% inserts %I% into %T%.")), \
				item = C)
		. = TRUE

/obj/machinery/space_heater/machine_step()
	if(cell && cell.charge)
		var/datum/gas_mixture/env = loc.return_air()
		if(env && abs(env.return_temperature() - set_temperature) > 0.1)
			var/transfer_moles = 0.25 * env.total_moles()
			var/datum/gas_mixture/removed = env.remove(transfer_moles)
			if(removed)
				var/heat_transfer = removed.get_thermal_energy_change(set_temperature)
				if(heat_transfer > 0)	//heating air
					if(state == SHEATER_STANDBY)
						set_state(SHEATER_HEAT)
					heat_transfer = min(heat_transfer , heating_power) //limit by the power rating of the heater

					removed.add_thermal_energy(heat_transfer)
					cell.use(heat_transfer*CELLRATE*power_efficiency)
				else	//cooling air
					if(state == SHEATER_STANDBY)
						set_state(SHEATER_COOL)
					heat_transfer = abs(heat_transfer)

					//Assume the heat is being pumped into the hull which is fixed at 20 C
					var/cop = vg_heat_regulator_cooling_cop(removed.return_temperature(), T20C, regulator_carnot_fraction, regulator_max_cop) //power used = heat_transfer/cop
					heat_transfer = min(heat_transfer, cop * heating_power)	//limit heat transfer by available power
					heat_transfer = removed.add_thermal_energy(-heat_transfer)	//get the actual heat transfer

					var/power_used = abs(heat_transfer)/cop
					cell.use(power_used*CELLRATE*power_efficiency)

			env.merge(removed)
	else
		set_state(SHEATER_OFF)
		power_change()
		update_icon()
		return PROCESS_KILL

/obj/machinery/space_heater/power_change()
	. = ..()
	if(. && state && cell?.charge)
		MACHINE_WAKE(src)

#undef SHEATER_OFF
#undef SHEATER_STANDBY
#undef SHEATER_HEAT
#undef SHEATER_COOL
#undef DEFAULT_MIN_TEMP
#undef DEFAULT_MAX_TEMP
#undef DEFAULT_HEATING_POWER


OWN(/obj/machinery/space_heater, cell, OWN_CONTAINED)
