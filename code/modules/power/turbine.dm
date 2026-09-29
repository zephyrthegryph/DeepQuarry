// TURBINE v2 AKA rev4407 Engine reborn!

// How to use it? - Mappers
//
// This is a very good power generating mechanism. All you need is a blast furnace with soaring flames and output.
// Not everything is included yet so the turbine can run out of fuel quiet quickly. The best thing about the turbine is that even
// though something is on fire that passes through it, it won't be on fire as it passes out of it. So the exhaust fumes can still
// containt unreacted fuel - plasma and oxygen that needs to be filtered out and re-routed back. This of course requires smart piping
// For a computer to work with the turbine the compressor requires a comp_id matching with the turbine computer's id. This will be
// subjected to a change in the near future mind you. Right now this method of generating power is a good backup but don't expect it
// become a main power source unless some work is done. Have fun. At 50k RPM it generates 60k power. So more than one turbine is needed!
//
// - Numbers
//
// Example setup	 S - sparker
//					 B - Blast doors into space for venting
// *BBB****BBB*		 C - Compressor
// S    CT    *		 T - Turbine
// * ^ *  * V *		 D - Doors with firedoor
// **|***D**|**      ^ - Fuel feed (Not vent, but a gas outlet)
//   |      |        V - Suction vent (Like the ones in atmos
//

/obj/machinery/compressor
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	maintenance_wrench_time = 2 SECONDS
	name = "compressor"
	desc = "The compressor stage of a gas turbine generator."
	icon = 'icons/obj/pipes.dmi'
	icon_state = "compressor"
	anchored = TRUE
	density = TRUE
	can_atmos_pass = ATMOS_PASS_PROC
	circuit = /obj/item/circuitboard/machine/power_compressor
	var/tmp/obj/machinery/power/turbine/turbine
	var/datum/gas_mixture/gas_contained
	var/tmp/turf/simulated/inturf
	var/starter = 0
	var/rpm = 0
	var/rpmtarget = 0
	var/capacity = 1e6
	var/comp_id = 0
	var/efficiency

/obj/machinery/power/turbine
	maintenance_flags = MACHINE_MAINT_STANDARD_MOVABLE
	maintenance_wrench_time = 2 SECONDS
	name = "gas turbine generator"
	desc = "A gas turbine used for backup power generation."
	icon = 'icons/obj/pipes.dmi'
	icon_state = "turbine"
	anchored = TRUE
	density = TRUE
	circuit = /obj/item/circuitboard/machine/power_turbine
	var/tmp/obj/machinery/compressor/compressor
	var/tmp/turf/simulated/outturf
	var/lastgen
	var/productivity = 1

/// Started by its control computer: set_starter() is the setter.
OM_FIELD_SETTER(/obj/machinery/compressor, starter, CHANGE_MACHINE_SETTINGS)
/// Not BROKEN (BROKEN also marks "no partner connected"; see locate_machinery()).
OM_DERIVE_FIELD(/obj/machinery/compressor, unbroken, list("stat"))
/obj/machinery/compressor/proc/unbroken()
	return !has_stat(BROKEN)
OM_DERIVE_FIELD(/obj/machinery/power/turbine, unbroken, list("stat"))
/obj/machinery/power/turbine/proc/unbroken()
	return !has_stat(BROKEN)

DECLARE_PERIODIC_WHILE_ALL(/obj/machinery/compressor, MACHINE_PIPELINE, list("starter", "unbroken"))
DECLARE_PERIODIC_WHILE(/obj/machinery/power/turbine, MACHINE_PIPELINE, "unbroken")

/obj/machinery/computer/turbine_computer
	name = "gas turbine control computer"
	desc = "A computer to remotely control a gas turbine."
	icon_keyboard = "tech_key"
	icon_screen = "turbinecomp"
	circuit = /obj/item/circuitboard/turbine_control
	var/tmp/obj/machinery/compressor/compressor
	/// The vent blast doors found by locate_machinery() (relation list).
	var/list/obj/machinery/door/blast/doors
	var/id = 0
	var/door_status = 0

/obj/item/circuitboard/machine/power_compressor
	name = T_BOARD("power compressor")
	build_path = /obj/machinery/compressor
	board_type = new /datum/frame/frame_types/machine
	req_components = list(/obj/item/stack/cable_coil = 5, /obj/item/stock_parts/manipulator = 6)
	hidden = TRUE // todo - Make properly constructable in round

/obj/item/circuitboard/machine/power_turbine
	name = T_BOARD("power turbine")
	build_path = /obj/machinery/power/turbine
	board_type = new /datum/frame/frame_types/machine
	req_components = list(/obj/item/stack/cable_coil = 5, /obj/item/stock_parts/capacitor = 6)
	hidden = TRUE // todo - Make properly constructable in round

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Compressor
// the inlet stage of the gas turbine electricity generator
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define COMPFRICTION 5e5
#define COMPSTARTERLOAD 2800

/obj/machinery/compressor/Initialize(mapload)
	. = ..()
	default_apply_parts()
	own_set(src, nameof(gas_contained), new /datum/gas_mixture())
	rel_set(src, nameof(inturf), get_step(src, dir))
	locate_machinery()
	if(!turbine())
		stat_add(BROKEN)

// When anchored, don't let air past us.
/obj/machinery/compressor/CanZASPass(turf/T, is_zone)
	return !anchored

/obj/machinery/compressor/proc/locate_machinery()
	if(turbine())
		return
	rel_set(src, nameof(turbine), locate_within(get_step(src, get_dir(inturf(), src)), /obj/machinery/power/turbine))
	if(turbine())
		turbine().locate_machinery()

/obj/machinery/compressor/RefreshParts()
	var/E = get_part_rating(/obj/item/stock_parts/manipulator)
	efficiency = E / 6

/obj/machinery/compressor/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/compressor_fingerprint,
		/datum/interaction/machine_item/part_replacement,
		/datum/interaction/machine_item/compressor_set_ident,
	)
	..()

/// Old attackby: added a fingerprint for any item before trying the part replacer.
/datum/interaction/machine_item/compressor_fingerprint
	id = "compressor_fingerprint"
	name = "Touch"
	held_type = /obj/item
	effect = /atom/proc/interaction_fingerprint

/// Old attackby: a multitool sets the comp ident tag.
/datum/interaction/machine_item/compressor_set_ident
	id = "compressor_set_ident"
	name = "Set ident tag"
	category = INTERACTION_CAT_CONFIGURE
	tool = TOOL_MULTITOOL
	tool_volume = 0
	effect = /obj/machinery/compressor/proc/interaction_set_ident

/obj/machinery/compressor/proc/interaction_set_ident(mob/user, obj/item/W, datum/interaction/interaction)
	var/new_ident = rerun_ask(user, "k146", PROC_REF(interaction_set_ident), args, /datum/om/prompt/text, message = "Enter a new ident tag.", title = name, default = comp_id, max_length = MAX_NAME_LEN)
	if(isnull(new_ident))
		return
	if(new_ident && user.Adjacent(src))
		comp_id = new_ident
	return TRUE

/obj/machinery/compressor/wrench_act(mob/user, obj/item/W)
	if((. = ..()))
		rel_clear(src, nameof(turbine))
		if(anchored)
			rel_set(src, nameof(inturf), get_step(src, dir))
			locate_machinery()
			if(turbine())
				to_chat(user, span_notice("Turbine connected."))
				stat_remove(BROKEN)
			else
				to_chat(user, span_warning("Turbine not connected."))
				stat_add(BROKEN)

/// Starts or stops the compressor; the compressor and its turbine run only while it is started.
/// The compressor's own work is declared on `starter`; its turbine reads it, so it is woken here.
/obj/machinery/compressor/proc/set_starter(value)
	if(starter == value)
		return FALSE
	starter = value
	om_changed(src, CHANGE_MACHINE_SETTINGS)
	if(starter && turbine())
		MACHINE_WAKE(turbine())
	return TRUE

/obj/machinery/compressor/machine_step()
	if(!turbine())
		set_stat(BROKEN)
		return
	if(panel_open)
		return
	cut_overlays()

	rpm = 0.9* rpm + 0.1 * rpmtarget
	var/datum/gas_mixture/environment = inturf().return_air()

	// It's a simplified version taking only 1/10 of the moles from the turf nearby. It should be later changed into a better version
	var/transfer_moles = environment.total_moles() / 10
	var/datum/gas_mixture/removed = inturf().remove_air(transfer_moles)
	gas_contained.merge(removed)

	// RPM function to include compression friction - be advised that too low/high of a compfriction value can make things screwy
	rpm = max(0, rpm - (rpm*rpm)/(COMPFRICTION*efficiency))

	if(starter && !has_stat(NOPOWER))
		use_power(2800)
		if(rpm<1000)
			rpmtarget = 1000
	else
		if(rpm<1000)
			rpmtarget = 0

	if(rpm>50000)
		add_overlay(image('icons/obj/pipes.dmi', "comp-o4", FLY_LAYER))
	else if(rpm>10000)
		add_overlay(image('icons/obj/pipes.dmi', "comp-o3", FLY_LAYER))
	else if(rpm>2000)
		add_overlay(image('icons/obj/pipes.dmi', "comp-o2", FLY_LAYER))
	else if(rpm>500)
		add_overlay(image('icons/obj/pipes.dmi', "comp-o1", FLY_LAYER))
	//TODO: DEFERRED


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Turbine
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// These are crucial to working of a turbine - the stats modify the power output. TurbGenQ modifies how much raw energy can you get from
// rpms, TurbGenG modifies the shape of the curve - the lower the value the less straight the curve is.

#define TURBPRES 9000000
#define TURBGENQ 100000
#define TURBGENG 0.8

/obj/machinery/power/turbine/Initialize(mapload)
	. = ..()
	default_apply_parts()
	// The outlet is pointed at the direction of the turbine component
	rel_set(src, nameof(outturf), get_step(src, dir))
	locate_machinery()
	if(!compressor())
		stat_add(BROKEN)

/obj/machinery/power/turbine/RefreshParts()
	var/P = get_part_rating(/obj/item/stock_parts/capacitor)
	productivity = P / 6

/obj/machinery/power/turbine/proc/locate_machinery()
	if(compressor())
		return
	rel_set(src, nameof(compressor), locate_within(get_step(src, get_dir(outturf(), src)), /obj/machinery/compressor))
	if(compressor())
		compressor().locate_machinery()

/// Old attackby: added a fingerprint for any item before trying the part replacer.
/datum/interaction/machine_item/turbine_fingerprint
	id = "turbine_fingerprint"
	name = "Touch"
	held_type = /obj/item
	effect = /atom/proc/interaction_fingerprint

/obj/machinery/power/turbine/wrench_act(mob/user, obj/item/W)
	if((. = ..()))
		rel_clear(src, nameof(compressor))
		if(anchored)
			rel_set(src, nameof(outturf), get_step(src, dir))
			locate_machinery()
			if(compressor())
				to_chat(user, span_notice("Compressor connected."))
				stat_remove(BROKEN)
			else
				to_chat(user, span_warning("Compressor not connected."))
				stat_add(BROKEN)

/obj/machinery/power/turbine/machine_step()
	if(!compressor())
		set_stat(BROKEN)
		return
	if(!compressor().starter)
		return PROCESS_KILL
	if(panel_open)
		return
	cut_overlays()

	// This is the power generation function. If anything is needed it's good to plot it in EXCEL before modifying
	// the TURBGENQ and TURBGENG values
	lastgen = ((compressor().rpm / TURBGENQ)**TURBGENG) * TURBGENQ * productivity

	add_avail(lastgen)

	// Weird function but it works. Should be something else...
	var/newrpm = ((compressor().gas_contained.return_temperature()) * compressor().gas_contained.total_moles())/4

	newrpm = max(0, newrpm)

	if(!compressor().starter || newrpm > 1000)
		compressor().rpmtarget = newrpm

	if(compressor().gas_contained.total_moles()>0)
		var/oamount = min(compressor().gas_contained.total_moles(), (compressor().rpm+100)/35000*compressor().capacity)
		var/datum/gas_mixture/removed = compressor().gas_contained.remove(oamount)
		outturf().assume_air(removed)
		qdel(removed)

	// If it works, put an overlay that it works!
	if(lastgen > 100)
		add_overlay(image('icons/obj/pipes.dmi', "turb-o", FLY_LAYER))

/obj/machinery/power/turbine/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/turbine_fingerprint,
		/datum/interaction/machine_item/part_replacement,
		/datum/interaction/machine_hand/open_ui,
	)
	..()

DECLARE_UI(/obj/machinery/power/turbine, "Turbine")

/obj/machinery/power/turbine/ui_prepare(mob/user, datum/tgui/ui)
	if(!Adjacent(user) && !issilicon(user))
		return FALSE
	if(!operable())
		return FALSE
	return TRUE

UI_DATA_REPLACE(/obj/machinery/power/turbine, "merge:ui_data_obj_machinery_power_turbine{display_power:unknown,turbine_rpm:num,starter:num}")

/// The computed part of /obj/machinery/power/turbine's window data (declared on its UI_DATA row).
/obj/machinery/power/turbine/proc/ui_data_obj_machinery_power_turbine(mob/user, datum/tgui/ui, datum/tgui_state/state)
	return list(
		"display_power" = lastgen,
		"turbine_rpm" = compressor()?.rpm,
		"starter" = compressor()?.starter
	)

UI_ACT(/obj/machinery/power/turbine, "start_stop", ui_act_start_stop)
UI_ACT_PROC(/obj/machinery/power/turbine, ui_act_start_stop)
	if(!compressor())
		return FALSE
	compressor().set_starter(!compressor().starter)
	return TRUE

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Turbine Computer
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/obj/machinery/computer/turbine_computer/Initialize(mapload)
	..()
	return INITIALIZE_HINT_LATELOAD

/obj/machinery/computer/turbine_computer/LateInitialize()
	locate_machinery()

/obj/machinery/computer/turbine_computer/proc/locate_machinery()
	if(!id)
		return
	for(var/obj/machinery/compressor/C in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(C.comp_id == id)
			rel_set(src, nameof(compressor), C)
	rel_clear(src, nameof(doors))
	for(var/obj/machinery/door/blast/P in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(P.id == id) //This will never work because the ID on the blast doors is a number while the ID on the turbine (if set mid-round) is a string.
			rel_add(src, nameof(doors), P)

/obj/machinery/computer/turbine_computer/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/turbine_computer_set_ident,
		/datum/interaction/machine_item/turbine_computer_swallow_item,
		/datum/interaction/machine_hand/open_ui,
	)
	..()

/// Old attackby: a multitool sets the ident tag.
/datum/interaction/machine_item/turbine_computer_set_ident
	id = "turbine_computer_set_ident"
	name = "Set ident tag"
	category = INTERACTION_CAT_CONFIGURE
	tool = TOOL_MULTITOOL
	tool_volume = 0
	effect = /obj/machinery/computer/turbine_computer/proc/interaction_set_ident

/obj/machinery/computer/turbine_computer/proc/interaction_set_ident(mob/user, obj/item/W, datum/interaction/interaction)
	var/new_ident = rerun_ask(user, "k382", PROC_REF(interaction_set_ident), args, /datum/om/prompt/text, message = "Enter a new ident tag.", title = name, default = id, max_length = MAX_NAME_LEN)
	if(isnull(new_ident))
		return
	if(new_ident && user.Adjacent(src))
		id = new_ident
	return TRUE

/// Old attackby: never called ..(), so any other item did nothing (no signal, no base attack).
/datum/interaction/machine_item/turbine_computer_swallow_item
	id = "turbine_computer_swallow_item"
	name = "Use"
	held_type = /obj/item
	effect = /atom/proc/interaction_swallow

DECLARE_UI(/obj/machinery/computer/turbine_computer, "TurbineControl")

UI_DATA_REPLACE(/obj/machinery/computer/turbine_computer, "merge:ui_data_obj_machinery_computer_turbine_computer{connected:bool,compressor_broke:bool,turbine_broke:bool,broken:bool,door_status:bool,online:num,power:unknown,rpm:num,temp:unknown}")

/// The computed part of /obj/machinery/computer/turbine_computer's window data (declared on its UI_DATA row).
/obj/machinery/computer/turbine_computer/proc/ui_data_obj_machinery_computer_turbine_computer(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["connected"] = (compressor() && compressor().turbine()) ? TRUE : FALSE
	data["compressor_broke"] = (!compressor() || (compressor().stat & BROKEN)) ? TRUE : FALSE
	data["turbine_broke"] = (!compressor() || !compressor().turbine() || (compressor().turbine().stat & BROKEN)) ? TRUE : FALSE
	data["broken"] = (data["compressor_broke"] || data["turbine_broke"])
	data["door_status"] = door_status ? TRUE : FALSE

	data["online"] = FALSE
	data["power"] = 0
	data["rpm"] = 0
	data["temp"] = 0

	if(compressor() && compressor().turbine())
		data["online"] = compressor().starter
		data["power"] = compressor().turbine().lastgen // DisplayPower
		data["rpm"] = compressor().rpm
		data["temp"] = compressor().gas_contained.return_temperature()

	return data

UI_ACT(/obj/machinery/computer/turbine_computer, "power-on", ui_act_power_on)
UI_ACT_PROC(/obj/machinery/computer/turbine_computer, ui_act_power_on)
	if(compressor() && compressor().turbine())
		compressor().set_starter(TRUE)
		. = TRUE

UI_ACT(/obj/machinery/computer/turbine_computer, "power-off", ui_act_power_off)
UI_ACT_PROC(/obj/machinery/computer/turbine_computer, ui_act_power_off)
	if(compressor() && compressor().turbine())
		compressor().set_starter(FALSE)
		. = TRUE

UI_ACT(/obj/machinery/computer/turbine_computer, "reconnect", ui_act_reconnect)
UI_ACT_PROC(/obj/machinery/computer/turbine_computer, ui_act_reconnect)
	locate_machinery()
	. = TRUE

UI_ACT(/obj/machinery/computer/turbine_computer, "doors", ui_act_doors)
UI_ACT_PROC(/obj/machinery/computer/turbine_computer, ui_act_doors)
	door_status = !door_status
	for(var/obj/machinery/door/blast/D as anything in doors?.Copy())
		if (door_status)
			D.close()
		else
			D.open()
	. = TRUE

#undef COMPFRICTION
#undef COMPSTARTERLOAD
#undef TURBPRES
#undef TURBGENQ
#undef TURBGENG


/// the compressor this refers to: a relation view, null once that is deleted.
/obj/machinery/computer/turbine_computer/proc/compressor() as /obj/machinery/compressor
	return compressor

/// the inturf this refers to: a relation view, null once that is deleted.
/obj/machinery/compressor/proc/inturf() as /turf/simulated
	return inturf

/// the outturf this refers to: a relation view, null once that is deleted.
/obj/machinery/power/turbine/proc/outturf() as /turf/simulated
	return outturf

/// the compressor this refers to: a relation view, null once that is deleted.
/obj/machinery/power/turbine/proc/compressor() as /obj/machinery/compressor
	return compressor

/// the turbine this refers to: a relation view, null once that is deleted.
/obj/machinery/compressor/proc/turbine() as /obj/machinery/power/turbine
	return turbine

/obj/machinery/computer/turbine_computer/declare_ownership(decl)
	..()
	rel(decl, nameof(doors), list = TRUE)
