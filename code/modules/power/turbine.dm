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
	var/tmp/turbine_handle
	var/datum/gas_mixture/gas_contained
	var/tmp/inturf_handle
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
	var/tmp/compressor_handle
	var/tmp/outturf_handle
	var/lastgen
	var/productivity = 1

/obj/machinery/computer/turbine_computer
	name = "gas turbine control computer"
	desc = "A computer to remotely control a gas turbine."
	icon_keyboard = "tech_key"
	icon_screen = "turbinecomp"
	circuit = /obj/item/circuitboard/turbine_control
	var/tmp/compressor_handle
	var/list/doors	// OM handles of the vent doors (om_resolve_all())
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
	gas_contained = new()
	inturf_handle = om_handle(get_step(src, dir))
	locate_machinery()
	if(!turbine())
		stat |= BROKEN

// When anchored, don't let air past us.
/obj/machinery/compressor/CanZASPass(turf/T, is_zone)
	return !anchored

/obj/machinery/compressor/proc/locate_machinery()
	if(turbine())
		return
	turbine_handle = om_handle(locate(/obj/machinery/power/turbine) in get_step(src, get_dir(inturf(), src)))
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
	effect = /obj/machinery/compressor/proc/interaction_fingerprint

/obj/machinery/compressor/proc/interaction_fingerprint(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	return FALSE

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
		turbine_handle = null
		if(anchored)
			inturf_handle = om_handle(get_step(src, dir))
			locate_machinery()
			if(turbine())
				to_chat(user, span_notice("Turbine connected."))
				stat &= ~BROKEN
			else
				to_chat(user, span_warning("Turbine not connected."))
				stat |= BROKEN

/// Starts or stops the compressor; the compressor and its turbine run only while it is started.
/obj/machinery/compressor/proc/set_starter(value)
	starter = value
	if(starter)
		MACHINE_WAKE(src)
		if(turbine())
			MACHINE_WAKE(turbine())

/obj/machinery/compressor/machine_step()
	if(!turbine())
		stat = BROKEN
	if(stat & BROKEN)
		return PROCESS_KILL
	if(!starter)
		return PROCESS_KILL
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

	if(starter && !(stat & NOPOWER))
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
	outturf_handle = om_handle(get_step(src, dir))
	locate_machinery()
	if(!compressor())
		stat |= BROKEN

/obj/machinery/power/turbine/RefreshParts()
	var/P = get_part_rating(/obj/item/stock_parts/capacitor)
	productivity = P / 6

/obj/machinery/power/turbine/proc/locate_machinery()
	if(compressor())
		return
	compressor_handle = om_handle(locate(/obj/machinery/compressor) in get_step(src, get_dir(outturf(), src)))
	if(compressor())
		compressor().locate_machinery()

/// Old attackby: added a fingerprint for any item before trying the part replacer.
/datum/interaction/machine_item/turbine_fingerprint
	id = "turbine_fingerprint"
	name = "Touch"
	held_type = /obj/item
	effect = /obj/machinery/power/turbine/proc/interaction_fingerprint

/obj/machinery/power/turbine/proc/interaction_fingerprint(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	return FALSE

/obj/machinery/power/turbine/wrench_act(mob/user, obj/item/W)
	if((. = ..()))
		compressor_handle = null
		if(anchored)
			outturf_handle = om_handle(get_step(src, dir))
			locate_machinery()
			if(compressor())
				to_chat(user, span_notice("Compressor connected."))
				stat &= ~BROKEN
			else
				to_chat(user, span_warning("Compressor not connected."))
				stat |= BROKEN

/obj/machinery/power/turbine/machine_step()
	if(!compressor())
		stat = BROKEN
	if(stat & BROKEN)
		return PROCESS_KILL
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

/obj/machinery/power/turbine/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui, custom_state)
	. = ..()
	if(!Adjacent(user) && !issilicon(user))
		return
	if(stat & (BROKEN|NOPOWER))
		return

	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Turbine", name)
		ui.open()

/obj/machinery/power/turbine/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	return list(
		"display_power" = lastgen,
		"turbine_rpm" = compressor()?.rpm,
		"starter" = compressor()?.starter
	)

/obj/machinery/power/turbine/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return

	switch(action)
		if("start_stop")
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
			compressor_handle = om_handle(C)
	LAZYINITLIST(doors)
	for(var/obj/machinery/door/blast/P in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(P.id == id) //This will never work because the ID on the blast doors is a number while the ID on the turbine (if set mid-round) is a string.
			doors += om_handle(P)

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
	effect = /obj/machinery/computer/turbine_computer/proc/interaction_swallow_item

/obj/machinery/computer/turbine_computer/proc/interaction_swallow_item(mob/user, obj/item/held, datum/interaction/interaction)
	return TRUE

/obj/machinery/computer/turbine_computer/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "TurbineControl", name)
		ui.open()

/obj/machinery/computer/turbine_computer/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

/obj/machinery/computer/turbine_computer/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	switch(action)
		if("power-on")
			if(compressor() && compressor().turbine())
				compressor().set_starter(TRUE)
				. = TRUE
		if("power-off")
			if(compressor() && compressor().turbine())
				compressor().set_starter(FALSE)
				. = TRUE
		if("reconnect")
			locate_machinery()
			. = TRUE
		if("doors")
			door_status = !door_status
			for(var/obj/machinery/door/blast/D in om_resolve_all(src.doors))
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

REF_OWNED(/obj/machinery/compressor, "gas_contained")

/// LC-refs: the compressor this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/computer/turbine_computer/proc/compressor() as /obj/machinery/compressor
	return om_resolve(compressor_handle)

/// LC-refs: the inturf this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/compressor/proc/inturf() as /turf/simulated
	return om_resolve(inturf_handle)

/// LC-refs: the outturf this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/power/turbine/proc/outturf() as /turf/simulated
	return om_resolve(outturf_handle)

/// LC-refs: the compressor this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/power/turbine/proc/compressor() as /obj/machinery/compressor
	return om_resolve(compressor_handle)

/// LC-refs: the turbine this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/machinery/compressor/proc/turbine() as /obj/machinery/power/turbine
	return om_resolve(turbine_handle)
