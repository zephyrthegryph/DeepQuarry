
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
DECLARE_PERIODIC_WHILE(/obj/machinery/shield_capacitor, MACHINE_PIPELINE, "anchored")

// The generator this capacitor feeds (two-sided with its capacitors list).
CAPABILITIES(/obj/machinery/shield_capacitor)
	links(/obj/machinery/shield_capacitor::owned_gen, /obj/machinery/shield_gen::capacitors, b_many = TRUE)
	climb()

/obj/machinery/shield_capacitor/Initialize(mapload)
	. = ..()
	make_rotatable()

/obj/machinery/shield_capacitor/advanced
	name = "advanced shield capacitor"
	desc = "A machine that charges a shield generator.  This version can store, input, and output more electricity."
	max_charge = 12e6
	max_charge_rate = 600000

DECLARE_EMAG_REPEATABLE(/obj/machinery/shield_capacitor, PROC_REF(on_emag), null)
/obj/machinery/shield_capacitor/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	if(prob(75))
		set_locked(!src.locked)
		to_chat(user, "Controls are now [src.locked ? "locked." : "unlocked."]")
		. = 1
	fx_sparks(src, 5)

/datum/interaction/machine_item/shield_capacitor_id_swipe
	id = "shield_capacitor_id_swipe"
	name = "Swipe ID"
	held_type = /obj/item/card/id
	effect = /obj/machinery/shield_capacitor/proc/interaction_id_swipe

/obj/machinery/shield_capacitor/proc/interaction_id_swipe(mob/user, obj/item/card/id/W, datum/interaction/interaction)
	if((ACCESS_CAPTAIN in W.GetAccess()) || (ACCESS_SECURITY in W.GetAccess()) || (ACCESS_ENGINE in W.GetAccess()))
		set_locked(!src.locked)
		to_chat(user, "Controls are now [src.locked ? "locked." : "unlocked."]")
	else
		to_chat(user, span_red("Access denied."))
	return TRUE

/obj/machinery/shield_capacitor/wrench_act(mob/user, obj/item/W)
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
	return ITEM_INTERACT_SUCCESS

/obj/machinery/shield_capacitor/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/shield_capacitor_id_swipe,
		/datum/interaction/machine_hand/ungated/shield_capacitor_use,
	)
	..()

/// Old attack_hand: never called ..(), so ungated.
/datum/interaction/machine_hand/ungated/shield_capacitor_use
	id = "shield_capacitor_use"
	name = "Use"
	effect = /obj/machinery/shield_capacitor/proc/interaction_use

/obj/machinery/shield_capacitor/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(has_stat(BROKEN))
		return TRUE
	tgui_interact(user)
	return TRUE

DECLARE_UI(/obj/machinery/shield_capacitor, "ShieldCapacitor")

/obj/machinery/shield_capacitor/tgui_status(mob/user)
	if(has_stat(BROKEN))
		return STATUS_CLOSE
	return ..()

UI_DATA_REPLACE(/obj/machinery/shield_capacitor, "time_since_fail:num", "stored_charge:num", "max_charge:num", "charge_rate:num", "max_charge_rate:num", "merge:ui_data_obj_machinery_shield_capacitor{active:num}")

/// The computed part of /obj/machinery/shield_capacitor's window data (declared on its UI_DATA row).
/obj/machinery/shield_capacitor/proc/ui_data_obj_machinery_shield_capacitor(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["active"] = active

	return data

/obj/machinery/shield_capacitor/machine_step()
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
			// Wait on a machine of the grid; with none, nothing can supply it.
			var/obj/machinery/power/node = power_grid_any_node(PN)
			sleep_until_keys(node ? list(node, CHANGE_POWER_GRID_RATE|CHANGE_POWER_GRID_STATE|CHANGE_POWER_GRID_TOPOLOGY) : list())
			return PROCESS_KILL
	else
		return PROCESS_KILL

	time_since_fail++
	if(stored_charge < last_stored_charge)
		time_since_fail = 0 //losing charge faster than we can draw from PN
	last_stored_charge = stored_charge
	if(stored_charge >= max_charge)
		stored_charge = max_charge
		return PROCESS_KILL

UI_ACT(/obj/machinery/shield_capacitor, "toggle", ui_act_toggle)
UI_ACT_PROC(/obj/machinery/shield_capacitor, ui_act_toggle)
	if(!active && !anchored)
		to_chat(ui.user, span_red("The [src] needs to be firmly secured to the floor first."))
		return
	set_active(!active)
	. = TRUE

UI_ACT(/obj/machinery/shield_capacitor, "charge_rate", ui_act_charge_rate, UI_ARG_NUM("rate"))
UI_ACT_PROC(/obj/machinery/shield_capacitor, ui_act_charge_rate)
	charge_rate = clamp(params["rate"], 10000, max_charge_rate)
	if(stored_charge < max_charge)
		MACHINE_WAKE(src)
	. = TRUE

/obj/machinery/shield_capacitor/power_change()
	if(has_stat(BROKEN))
		icon_state = "broke"
	else
		..()


// === merged from shield_capacitor_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/machinery/shield_capacitor
	icon = 'icons/obj/machines/shielding.dmi'

/// Audit: a sleeping capacitor must be full or have nothing to draw from.
/obj/machinery/shield_capacitor/om_sleep_violation()
	if(!asleep_on_keys() || !anchored || stored_charge >= max_charge)
		return null
	var/turf/T = get_turf(src)
	var/obj/structure/cable/C = T?.get_cable_node()
	var/PN = C?.get_power_region()
	if(PN && power_surplus(PN) > 0)
		return "asleep below full charge on a grid with [power_surplus(PN)] W spare"
	return null


/// The generator this capacitor feeds (a relation view).
/obj/machinery/shield_capacitor/proc/owned_gen() as /obj/machinery/shield_gen
	return owned_gen
