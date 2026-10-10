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

	/// The compressor overlay's stage (0 none, 1..4 by rpm).
	var/rpm_stage = 0

TRACKED(/obj/machinery/compressor, starter)
TRACKED(/obj/machinery/compressor, rpm_stage)

// The gas turbine (doc/rewrite/final_api.html section 16): a compressor draws a tenth of the gas in front of it every machine service interval
// while it is started (compressor_step(); a starter motor brings it to 1000 rpm), and its turbine turns the compressor's rpm into power
// (turbine_step(): ((rpm / TURBGENQ) ^ TURBGENG) * TURBGENQ * productivity W for the next power step) and vents the gas behind it.
CAPABILITIES(/obj/machinery/compressor)
	default_parts()
	owns_one(nameof(gas_contained), /datum/gas_mixture, starts = /datum/gas_mixture, starts_args = NO_LOC)
	ref_one(nameof(turbine), /obj/machinery/power/turbine)
	ref_one(nameof(inturf), /turf/simulated)
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(compressor_step)), when = PROC_REF(running))
	part_replacement()
	op("set_ident", tool(TOOL_MULTITOOL), label("Set ident tag"), wait(0),
		asks(/datum/prompt/text, fields = list("title" = "Compressor", "question" = "Enter a new ident tag.", "default" = nameof(comp_id), "max_len" = MAX_NAME_LEN)),
		then(PROC_REF(ident_entered)))
	extend("machine_anchor", then(PROC_REF(rewrenched)))
	extend("machine_unanchor", then(PROC_REF(rewrenched)))

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
	/// It makes power (its "running" overlay shows).
	var/generating_shown = FALSE

TRACKED(/obj/machinery/power/turbine, generating_shown)

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
	rel_set(src, nameof(inturf), get_step(src, dir))
	locate_machinery()
	if(!turbine())
		atom_break()

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

/obj/machinery/compressor/proc/ident_entered(datum/act/op/A)
	var/datum/prompt/text/answer = A.answer
	if(answer?.value && A.actor?.Adjacent(src))
		comp_id = answer.value
	return OP_OK

/// Started and whole (BROKEN also marks "no partner connected"; see locate_machinery()).
/obj/machinery/compressor/proc/running(datum/act/A)
	return starter && !broken_now()

/// One step while started: it spins toward its target and draws in gas.
/obj/machinery/compressor/proc/compressor_step(datum/act/timer/A)
	if(!turbine())
		atom_break()
		return
	if(panel_open)
		return

	rpm = 0.9* rpm + 0.1 * rpmtarget
	var/datum/gas_mixture/environment = inturf().return_air()

	// It's a simplified version taking only 1/10 of the moles from the turf nearby. It should be later changed into a better version
	var/transfer_moles = environment.total_moles() / 10
	var/datum/gas_mixture/removed = inturf().remove_air(transfer_moles)
	gas_contained.merge(removed)

	// RPM function to include compression friction - be advised that too low/high of a compfriction value can make things screwy
	rpm = max(0, rpm - (rpm*rpm)/(COMPFRICTION*efficiency))

	if(starter && !power_lost())
		use_power(2800)
		if(rpm<1000)
			rpmtarget = 1000
	else
		if(rpm<1000)
			rpmtarget = 0

	if(rpm>50000)
		set_rpm_stage(4)
	else if(rpm>10000)
		set_rpm_stage(3)
	else if(rpm>2000)
		set_rpm_stage(2)
	else if(rpm>500)
		set_rpm_stage(1)
	else
		set_rpm_stage(0)

/obj/machinery/compressor/draw(datum/look/look)
	..()
	if(rpm_stage)
		look.overlay(image('icons/obj/pipes.dmi', "comp-o[rpm_stage]", FLY_LAYER))

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
	// The outlet is pointed at the direction of the turbine component
	rel_set(src, nameof(outturf), get_step(src, dir))
	locate_machinery()
	if(!compressor())
		atom_break()

/obj/machinery/power/turbine/RefreshParts()
	var/P = get_part_rating(/obj/item/stock_parts/capacitor)
	productivity = P / 6

/obj/machinery/power/turbine/proc/locate_machinery()
	if(compressor())
		return
	rel_set(src, nameof(compressor), locate_within(get_step(src, get_dir(outturf(), src)), /obj/machinery/compressor))
	if(compressor())
		compressor().locate_machinery()

/// Its compressor is started and it is whole.
/obj/machinery/power/turbine/proc/running(datum/act/A)
	return compressor?.starter && !broken_now()

/// One step while its compressor runs: power from the rpm, the rpm from the gas, and the gas vented behind it.
/obj/machinery/power/turbine/proc/turbine_step(datum/act/timer/A)
	if(!compressor())
		atom_break()
		return
	if(panel_open)
		return

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
		spent(removed)

	// If it works, put an overlay that it works!
	set_generating_shown(lastgen > 100)

/obj/machinery/power/turbine/draw(datum/look/look)
	..()
	if(generating_shown)
		look.overlay(image('icons/obj/pipes.dmi', "turb-o", FLY_LAYER))

CAPABILITIES(/obj/machinery/power/turbine)
	default_parts()
	ref_one(nameof(compressor), /obj/machinery/compressor)
	ref_one(nameof(outturf), /turf/simulated)
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(turbine_step)), when = PROC_REF(running))
	part_replacement()
	interface("Turbine")
	extend("ui_open", when(req_empty_hand()), needs(req_operable()))
	op("start_stop", ui_act("start_stop"), then(PROC_REF(ui_act_start_stop)))
	extend("machine_anchor", then(PROC_REF(rewrenched)))
	extend("machine_unanchor", then(PROC_REF(rewrenched)))

/// /obj/machinery/power/turbine's window data.
/obj/machinery/power/turbine/ui_data(datum/act/eval/A)
	return list(
		"display_power" = lastgen,
		"turbine_rpm" = compressor()?.rpm,
		"starter" = compressor()?.starter
	)

/obj/machinery/power/turbine/proc/ui_act_start_stop(datum/act/op/A)
	if(!compressor())
		return FALSE
	compressor().set_starter(!compressor().starter)
	return TRUE

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Turbine Computer
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/// Finds its compressor and doors, once they exist.
/obj/machinery/computer/turbine_computer/proc/find_machinery(datum/act/timer/A)
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

/obj/machinery/computer/turbine_computer/proc/ident_entered(datum/act/op/A)
	var/datum/prompt/text/answer = A.answer
	if(answer?.value && A.actor?.Adjacent(src))
		id = answer.value
	return OP_OK

CAPABILITIES(/obj/machinery/computer/turbine_computer)
	after_init(0, then(PROC_REF(find_machinery)))
	ref_one(nameof(compressor), /obj/machinery/compressor)
	ref_many(nameof(doors), /obj/machinery/door/blast)
	op("set_ident", tool(TOOL_MULTITOOL), label("Set ident tag"), wait(0),
		asks(/datum/prompt/text, fields = list("title" = "Turbine control", "question" = "Enter a new ident tag.", "default" = nameof(id), "max_len" = MAX_NAME_LEN)),
		then(PROC_REF(ident_entered)))
	interface("TurbineControl")
	op("power-on", ui_act("power-on"), then(PROC_REF(ui_act_power_on)))
	op("power-off", ui_act("power-off"), then(PROC_REF(ui_act_power_off)))
	op("reconnect", ui_act("reconnect"), then(PROC_REF(ui_act_reconnect)))
	op("doors", ui_act("doors"), then(PROC_REF(ui_act_doors)))

/// /obj/machinery/computer/turbine_computer's window data.
/obj/machinery/computer/turbine_computer/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["connected"] = (compressor() && compressor().turbine()) ? TRUE : FALSE
	data["compressor_broke"] = (!compressor() || compressor().broken_now()) ? TRUE : FALSE
	data["turbine_broke"] = (!compressor() || !compressor().turbine() || compressor().turbine().broken_now()) ? TRUE : FALSE
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

/obj/machinery/computer/turbine_computer/proc/ui_act_power_on(datum/act/op/A)
	if(compressor() && compressor().turbine())
		compressor().set_starter(TRUE)
		. = TRUE

/obj/machinery/computer/turbine_computer/proc/ui_act_power_off(datum/act/op/A)
	if(compressor() && compressor().turbine())
		compressor().set_starter(FALSE)
		. = TRUE

/obj/machinery/computer/turbine_computer/proc/ui_act_reconnect(datum/act/op/A)
	locate_machinery()
	. = TRUE

/obj/machinery/computer/turbine_computer/proc/ui_act_doors(datum/act/op/A)
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

/// After the base wrench: a secured compressor finds its turbine (and works only with one).
/obj/machinery/compressor/proc/rewrenched(datum/act/op/A)
	rel_clear(src, nameof(turbine))
	if(anchored)
		rel_set(src, nameof(inturf), get_step(src, dir))
		locate_machinery()
		if(turbine())
			to_chat(A.actor, span_notice("Turbine connected."))
			atom_fix()
		else
			to_chat(A.actor, span_warning("Turbine not connected."))
			atom_break()

/// After the base wrench: a secured turbine finds its compressor (and works only with one).
/obj/machinery/power/turbine/proc/rewrenched(datum/act/op/A)
	rel_clear(src, nameof(compressor))
	if(anchored)
		rel_set(src, nameof(outturf), get_step(src, dir))
		locate_machinery()
		if(compressor())
			to_chat(A.actor, span_notice("Compressor connected."))
			atom_fix()
		else
			to_chat(A.actor, span_warning("Compressor not connected."))
			atom_break()
