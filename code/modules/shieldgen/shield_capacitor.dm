
//---------- shield capacitor
//pulls energy out of a power net and charges an adjacent generator

/obj/machinery/shield_capacitor
	name = "shield capacitor"
	desc = "A machine that charges a shield generator."
	icon = 'icons/obj/machines/shielding.dmi'
	icon_state = "capacitor"
	active = 0
	density = TRUE
	var/stored_charge = 0	//not to be confused with power cell charge, this is in Joules
	var/last_stored_charge = 0
	var/time_since_fail = 100
	var/max_charge = 8e6	//8 MJ
	var/max_charge_rate = 400000	//400 kW
	locked = 0
	use_power = USE_POWER_OFF //doesn't use APC power
	var/charge_rate = 100000	//100 kW
	var/tmp/obj/machinery/shield_gen/owned_gen
	interact_offline = TRUE

/// Charges from the cable underneath while bolted down (it parks once full or with nothing to draw).
// The generator this capacitor feeds (two-sided with its capacitors list).
CAPABILITIES(/obj/machinery/shield_capacitor)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(anchored), wakes_on = list(nameof(anchored)))
	links(/obj/machinery/shield_capacitor::owned_gen, /obj/machinery/shield_gen::capacitors, b_many = TRUE)
	climb()
	interface("ShieldCapacitor")
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)
	without("ui_open")
	op("toggle", ui_act("toggle"), then(PROC_REF(ui_act_toggle)))
	op("charge_rate", ui_act("charge_rate", arg("rate", num())), then(PROC_REF(ui_act_charge_rate)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wrench_used)))
	op("id_swipe", item(/obj/item/card/id), priority(OP_PRIORITY_DEFAULT - 1), label("Swipe ID"), then(PROC_REF(interaction_id_swipe)))
	op("use", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_use)))
	rotatable()

/obj/machinery/shield_capacitor/advanced
	name = "advanced shield capacitor"
	desc = "A machine that charges a shield generator.  This version can store, input, and output more electricity."
	max_charge = 12e6
	max_charge_rate = 600000

/obj/machinery/shield_capacitor/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	. = OP_DECLINE
	if(prob(75))
		set_locked(!src.locked)
		to_chat(user, "Controls are now [src.locked ? "locked." : "unlocked."]")
		. = OP_OK
	fx_sparks(src, 5)

/obj/machinery/shield_capacitor/proc/interaction_id_swipe(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/card/id/W = A.held
	if((ACCESS_CAPTAIN in W.GetAccess()) || (ACCESS_SECURITY in W.GetAccess()) || (ACCESS_ENGINE in W.GetAccess()))
		set_locked(!src.locked)
		to_chat(user, "Controls are now [src.locked ? "locked." : "unlocked."]")
	else
		to_chat(user, span_red("Access denied."))
	return TRUE

/obj/machinery/shield_capacitor/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	set_anchored(!anchored)
	playsound(src, W.usesound, 75, 1)
	act_message(user, src, others = span_blue("[icon2html(src,viewers(src))] %T% has been [anchored ? "bolted to the floor" : "unbolted from the floor"] by %U%."))

	if(anchored)
		for(var/obj/machinery/shield_gen/gen in range(1, src))
			if(get_dir(src, gen) == src.dir)
				rel_set(src, nameof(owned_gen), gen)
	else
		set_active(0)
		rel_clear(src, nameof(owned_gen))
	return OP_OK

/obj/machinery/shield_capacitor/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	if(has_stat(BROKEN))
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/machinery/shield_capacitor/tgui_status(mob/user)
	if(has_stat(BROKEN))
		return STATUS_CLOSE
	return ..()

/obj/machinery/shield_capacitor/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["time_since_fail"] = time_since_fail
	data["stored_charge"] = stored_charge
	data["max_charge"] = max_charge
	data["charge_rate"] = charge_rate
	data["max_charge_rate"] = max_charge_rate
	var/list/merged_1 = ui_data_obj_machinery_shield_capacitor(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/machinery/shield_capacitor's window data.
/obj/machinery/shield_capacitor/proc/ui_data_obj_machinery_shield_capacitor(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["active"] = active

	return data

/obj/machinery/shield_capacitor/proc/work_step(datum/act/timer/A)
	//see if we can connect to a power net.
	var/PN = 0
	var/turf/T = get_turf(src)
	var/obj/structure/cable/C = T.get_cable_node()
	if (C && anchored) //Make sure its anchored too.
		PN = C.get_power_region()

	if (PN)
		var/power_draw = between(0, max_charge - stored_charge, charge_rate) //what we are trying to draw
		power_draw = power_draw(PN, power_draw) //what we actually get
		stored_charge += power_draw
		if(power_draw <= 0 && stored_charge < max_charge)
			return // the grid has nothing spare: it asks again next step
	else
		return PROCESS_KILL

	time_since_fail++
	if(stored_charge < last_stored_charge)
		time_since_fail = 0 //losing charge faster than we can draw from PN
	last_stored_charge = stored_charge
	if(stored_charge >= max_charge)
		stored_charge = max_charge
		return PROCESS_KILL

/obj/machinery/shield_capacitor/proc/ui_act_toggle(datum/act/op/A)
	var/mob/user = A.actor
	if(!active && !anchored)
		to_chat(user, span_red("The [src] needs to be firmly secured to the floor first."))
		return
	set_active(!active)
	. = TRUE

/obj/machinery/shield_capacitor/proc/ui_act_charge_rate(datum/act/op/A, rate)
	charge_rate = clamp(rate, 10000, max_charge_rate)
	if(stored_charge < max_charge)
		work_start(src)
	. = TRUE

/obj/machinery/shield_capacitor/power_change()
	if(has_stat(BROKEN))
		icon_state = "broke"
	else
		..()


// === merged from shield_capacitor_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/machinery/shield_capacitor
	icon = 'icons/obj/machines/shielding.dmi'

/// The generator this capacitor feeds (a relation view).
/obj/machinery/shield_capacitor/proc/owned_gen() as /obj/machinery/shield_gen
	return owned_gen
