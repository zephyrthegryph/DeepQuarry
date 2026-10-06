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
	/// Fraction of the Carnot COP its cooling side achieves (the heat pump's COP is Rust's, Carnot-bounded).
	var/regulator_carnot_fraction = 0.4
	/// Upper bound on the pump's COP.
	var/regulator_max_cop = 25
	/// TRUE while it works the room's air: its heat pump exists exactly while this is set.
	var/pumping = FALSE
	clicksound = SFX_SWITCH
	interact_offline = TRUE
	bubble_icon = "engineering"
	circuit = /obj/item/circuitboard/space_heater

// The cell comes from cell_type (null: none); icon_state follows state, the open-hatch overlay
// panel_open (doc/rewrite/declarative_lifecycle.md).
// Rows by state: SHEATER_OFF, SHEATER_STANDBY, SHEATER_HEAT, SHEATER_COOL.
DECLARE_APPEARANCE(/obj/machinery/space_heater, "state", list( 	"0" = list(APPEARANCE_ICON_STATE = "sheater0"), 	"1" = list(APPEARANCE_ICON_STATE = "sheater1"), 	"2" = list(APPEARANCE_ICON_STATE = "sheater2"), 	"3" = list(APPEARANCE_ICON_STATE = "sheater3") ))
DECLARE_APPEARANCE(/obj/machinery/space_heater, "panel_open", list("1" = list(APPEARANCE_OVERLAYS = list("sheater-open"))))
// Regulates the air while switched on (any state but SHEATER_OFF).
DECLARE_PERIODIC_WHILE(/obj/machinery/space_heater, MACHINE_PIPELINE, "state")

TRACKED(/obj/machinery/space_heater, pumping)

CAPABILITIES(/obj/machinery/space_heater)
	climb()
	// A heat pump on the room's air toward the thermostat: it heats resistively, one joule of heat per joule drawn, and cools by
	// pumping into the station's heat-rejection loop at a Carnot-bounded COP. Its work is paid from the cell (machine_step()).
	when(nameof(pumping), heat_pump(HEAT_AIR, HEAT_AMBIENT, nameof(heating_power), nameof(set_temperature), HEAT_PUMP_BOTH, TRUE, nameof(regulator_carnot_fraction), nameof(regulator_max_cop)))
	interface("SpaceHeater", state = nameof(GLOB.tgui_physical_state))
	op("temp", ui_act("temp", arg("newtemp", num())), needs(req(PROC_REF(ui_gate), silent = TRUE)), then(PROC_REF(ui_act_temp)))
	op("cellremove", ui_act("cellremove"), needs(req(PROC_REF(ui_gate), silent = TRUE)), then(PROC_REF(ui_act_cellremove)))
	op("cellinstall", ui_act("cellinstall"), needs(req(PROC_REF(ui_gate), silent = TRUE)), then(PROC_REF(ui_act_cellinstall)))

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with and redraws for them
/obj/machinery/space_heater/Initialize(mapload)
	. = ..()
	default_apply_parts()
	update_icon()

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
	if(!move_into(src, nameof(src.cell), C, user))
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
		if(state == SHEATER_OFF)
			set_pumping(FALSE)
		act_message(user, src, MSG_SELF(span_notice("You switch [state ? "on" : "off"] %T%.")),
			MSG_OTHERS(span_notice("%U% switches [state ? "on" : "off"] %T%.")))
	return

/obj/machinery/space_heater/tgui_status(mob/user)
	if(!panel_open)
		return STATUS_CLOSE
	return ..()

/obj/machinery/space_heater/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["temp"] = set_temperature
	data["minTemp"] = min_temperature
	data["maxTemp"] = max_temperature
	var/list/merged_1 = ui_data_obj_machinery_space_heater(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/space_heater's window data.
/obj/machinery/space_heater/proc/ui_data_obj_machinery_space_heater(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["cell"] = !!cell
	data["power"] = round(cell?.percent(), 1)

	return data

/obj/machinery/space_heater/proc/ui_gate(datum/act/op/A)
	if(!panel_open)
		return FALSE
	return TRUE

/obj/machinery/space_heater/proc/ui_act_temp(datum/act/op/A, newtemp)
	// limit to 0-90 degC
	set_temperature = clamp(newtemp, min_temperature, max_temperature)
	heat_entries_refresh(src)
	. = TRUE

/obj/machinery/space_heater/proc/ui_act_cellremove(datum/act/op/A)
	var/mob/user = A.actor
	if(cell && !user.get_active_hand())
		act_message(user, src, MSG_SELF(span_notice("You remove [cell] from %T%.")), MSG_OTHERS(span_notice("%U% removes [cell] from %T%.")))
		cell.update_icon()
		user.put_in_hands(cell)
		cell.add_fingerprint(user)
		own_take(src, nameof(/obj/mecha::cell))
		power_change()
		. = TRUE

/obj/machinery/space_heater/proc/ui_act_cellinstall(datum/act/op/A)
	var/mob/user = A.actor
	if(!cell)
		var/obj/item/cell/C = user.get_active_hand()
		if(istype(C))
			if(!move_into(src, nameof(src.cell), C, user))
				return
			C.add_fingerprint(user)
			power_change()
			act_message(user, src, MSG_SELF(span_notice("You insert %I% into %T%.")), \
				MSG_OTHERS(span_notice("%U% inserts %I% into %T%.")), \
				item = C)
		. = TRUE

/// The heat pump (its CAPABILITIES entry) works the air in Rust; the step pays its work from the cell and shows what it does.
/obj/machinery/space_heater/machine_step()
	if(!cell || !cell.charge)
		set_pumping(FALSE)
		set_state(SHEATER_OFF)
		power_change()
		update_icon()
		return PROCESS_KILL
	var/drawn = heat_entries_bill(src)
	if(drawn > 0)
		cell.use(drawn * CELLRATE * power_efficiency)
	if(!pumping)
		set_pumping(TRUE)
	var/datum/gas_mixture/env = loc.return_air()
	var/gap = env ? set_temperature - env.return_temperature() : 0
	if(abs(gap) <= 0.1)
		set_state(SHEATER_STANDBY)
	else
		set_state(gap > 0 ? SHEATER_HEAT : SHEATER_COOL)

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


/obj/machinery/space_heater/ownership()
	. = ..()
	. += owns(nameof(cell), policy = OWN_CONTAINED, starts = nameof(cell_type))
