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
TRACKED(/obj/machinery/space_heater, pumping)

MSG_DEF(space_heater/cell_in, span_notice("You insert the power cell into %T%."), span_notice("%U% inserts a power cell into %T%."))
MSG_DEF_SELF(space_heater/hatch_closed, "the hatch must be open to insert a power cell")
MSG_DEF_SELF(space_heater/cell_present, "there is already a power cell inside")

CAPABILITIES(/obj/machinery/space_heater)
	climb()
	owns_one(nameof(cell), /obj/item/cell, starts = nameof(cell_type))
	// Regulates the air while switched on (any state but SHEATER_OFF); a step with no charge left switches it off and stops the work.
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(state))
	op("insert_cell", item(/obj/item/cell), label("Insert power cell"), wait(0),
		needs(req(PROC_REF(hatch_open), because = MSG(space_heater/hatch_closed)), req(PROC_REF(no_cell_installed), because = MSG(space_heater/cell_present))),
		then(PROC_REF(interaction_insert_cell)))
	part_replacement()
	op("use", hand(), ungated(), label("Use"), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(interaction_hand_interact)))
	op("hatch", tool(TOOL_SCREWDRIVER), wait(0), label("Open hatch"), then(PROC_REF(hatch_toggled)))
	// A heat pump on the room's air toward the thermostat: it heats resistively, one joule of heat per joule drawn, and cools by
	// pumping into the station's heat-rejection loop at a Carnot-bounded COP. Its work is paid from the cell (work_step()).
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

/obj/machinery/space_heater/proc/hatch_open(datum/act/op/A)
	return panel_open

/obj/machinery/space_heater/proc/no_cell_installed(datum/act/op/A)
	return !cell

/obj/machinery/space_heater/proc/interaction_insert_cell(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/cell/C = A.held
	if(!move_into(src, nameof(src.cell), C, user))
		return
	C.add_fingerprint(user)
	act_message(user, src, MSG_SELF(span_notice("You insert the power cell into %T%.")), MSG_OTHERS(span_notice("%U% inserts a power cell into %T%.")))
	power_change()

/obj/machinery/space_heater/proc/interaction_hand_interact(datum/act/op/A)
	add_fingerprint(A.actor)
	interact(A.actor)

/obj/machinery/space_heater/proc/hatch_toggled(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	set_panel_open(!panel_open)
	playsound(src, tool.usesound, 50, TRUE)
	act_message(user, src, MSG_SELF(span_notice("You [panel_open ? "open" : "close"] the hatch on %T%.")), \
		MSG_OTHERS(span_notice("%U% [panel_open ? "opens" : "closes"] the hatch on %T%.")))
	update_icon()
	if(!panel_open && user.check_current_machine(src))
		SStgui.close_uis(src)
		user.unset_machine()

/obj/machinery/space_heater/interact(mob/user as mob)
	if(panel_open)
		tgui_interact(user)
	else
		set_state(state ? SHEATER_OFF : SHEATER_STANDBY)
		if(state == SHEATER_OFF)
			set_pumping(FALSE)
		else
			work_start(src)
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
/obj/machinery/space_heater/proc/work_step(datum/act/timer/A)
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
		work_start(src)

#undef SHEATER_OFF
#undef SHEATER_STANDBY
#undef SHEATER_HEAT
#undef SHEATER_COOL
#undef DEFAULT_MIN_TEMP
#undef DEFAULT_MAX_TEMP
#undef DEFAULT_HEATING_POWER

