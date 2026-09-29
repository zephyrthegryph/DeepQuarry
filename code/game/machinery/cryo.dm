// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

/// Mend per tick at the base rate (oxygenation below freezing).
#define CRYO_BASE_RATE 1
/// Below this the cell repairs tissue, faster the colder it is.
#define CRYO_DEEP_COLD 225

/obj/machinery/atmospherics/unary/cryo_cell
	name = "cryo cell"
	desc = "Used to cool people down for medical reasons. Totally."
	icon = 'icons/obj/cryogenics.dmi' // map only
	icon_state = "pod_preview"
	density = TRUE
	anchored = TRUE
	flags = REMOTEVIEW_ON_ENTER
	layer = UNDER_JUNK_LAYER
	interact_offline = 1

	on = 0
	use_power = USE_POWER_IDLE
	idle_power_usage = 20
	active_power_usage = 200
	buckle_lying = FALSE
	buckle_dir = SOUTH
	clicksound = SFX_MACHINES_BUTTONBEEP
	clickvol = 30

	var/temperature_archived
	var/obj/item/reagent_containers/glass/beaker = null

	var/image/fluid

/obj/machinery/atmospherics/unary/cryo_cell/Initialize(mapload)
	. = ..()
	icon = 'icons/obj/cryogenics_split.dmi'
	icon_state = "base"
	initialize_directions = dir
	var/image/tank = image(icon,"tank")
	tank.alpha = 200
	tank.pixel_y = 18
	tank.plane = MOB_PLANE
	tank.layer = MOB_LAYER+0.2 //Above fluid
	fluid = image(icon, "tube_filler")
	fluid.pixel_y = 18
	fluid.alpha = 200
	fluid.plane = MOB_PLANE
	fluid.layer = MOB_LAYER+0.1 //Below glass, above mob
	add_overlay(tank)
	update_icon()

OWN(/obj/machinery/atmospherics/unary/cryo_cell, beaker, OWN_SPILL)
DECLARE_PERIODIC_WHILE_ALL(/obj/machinery/atmospherics/unary/cryo_cell, MACHINE_PIPELINE, list("on", "node"))

/// Sealed occupant slot (C8, containment.md §10, OM relations step 3).
/datum/om/relation/slot/occupant/cryo
	holder = /obj/machinery/atmospherics/unary/cryo_cell
	slot_id = OCCUPANT_SLOT_CRYO
	name = "cryo cell"
	// No view fields (OM relations step 3): `occupant` is still an ordinary
	// var every reader here uses, but this slot's own on_link()/on_unlink()
	// are its only writer now -- there is no generic field-link mechanism
	// left to do it for them.

/obj/machinery/atmospherics/unary/cryo_cell/machine_step()
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_CRYO)
	..()
	if(air_contents)
		temperature_archived = air_contents.return_temperature()

	if(occupant)
		if(occupant.stat != 2)
			process_occupant()

	if(air_contents)
		expel_gas()

	if(air_contents && abs(temperature_archived-air_contents.return_temperature()) > 1)
		network?.mark_dirty()

	return 1

/obj/machinery/atmospherics/unary/cryo_cell/relaymove(mob/user as mob)
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_CRYO)
	// note that relaymove will also be called for mobs outside the cell with UI open
	if(occupant == user && !user.stat)
		go_out()

EXTEND_INTERACTIONS(/obj/machinery/atmospherics/unary/cryo_cell, \
	INTERACT_HAND_UNGATED(null, PROC_REF(cryo_cell_interaction_hand), REQ_BECAUSE(REQ_PANEL(FALSE), "close the maintenance panel first")), \
	INTERACT_ITEM(null, PROC_REF(cryo_cell_interaction_item)), \
	INTERACT_DRAG("Put inside", PROC_REF(cryo_cell_interaction_drag)), \
	INTERACT_VERB("Eject occupant", PROC_REF(cryo_cell_move_eject)), \
	INTERACT_VERB("Move Inside", PROC_REF(cryo_cell_move_inside)), \
)

/// Old attack_hand (it never reached the machinery gate).
/obj/machinery/atmospherics/unary/cryo_cell/proc/cryo_cell_interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_CRYO)
	if(user == occupant)
		return TRUE

	tgui_interact(user)
	return TRUE

DECLARE_UI(/obj/machinery/atmospherics/unary/cryo_cell, "Cryo", UI_TITLE("Cryo Cell"))

UI_DATA_REPLACE(/obj/machinery/atmospherics/unary/cryo_cell, "merge:ui_data_obj_machinery_atmospherics_unary_cryo_cell{isOperating:num,hasOccupant:bool,occupant:unknown,cellTemperature:num,cellTemperatureStatus:text,isBeakerLoaded:bool,beakerLabel:text,beakerVolume:unknown}")

/// The computed part of /obj/machinery/atmospherics/unary/cryo_cell's window data (declared on its UI_DATA row).
/obj/machinery/atmospherics/unary/cryo_cell/proc/ui_data_obj_machinery_atmospherics_unary_cryo_cell(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/mob/living/carbon/occupant = slot_item_real(OCCUPANT_SLOT_CRYO)
	// this is the data which will be sent to the ui
	var/list/data = list()
	data["isOperating"] = on
	data["hasOccupant"] = occupant ? TRUE : FALSE

	var/list/occupantData = list()
	if(occupant)
		occupantData["name"] = occupant.name
		occupantData["stat"] = occupant.stat
		occupantData["vitality"] = round(occupant.vitality() * 100)
		occupantData["critical"] = occupant.is_critical()
		var/datum/diagnosis/D = occupant.diagnose(/datum/diagnostic_profile/automation)
		occupantData["diagnosis"] = D.report_data()
		qdel(D)
		occupantData["bodyTemperature"] = occupant.bodytemperature
	data["occupant"] = occupantData;

	var/air_temperature = air_contents.return_temperature()
	data["cellTemperature"] = round(air_temperature)
	data["cellTemperatureStatus"] = "good"
	if(air_temperature > T0C) // if greater than 273.15 kelvin (0 celcius)
		data["cellTemperatureStatus"] = "bad"
	else if(air_temperature > 225)
		data["cellTemperatureStatus"] = "average"

	data["isBeakerLoaded"] = beaker ? TRUE : FALSE
	data["beakerLabel"] = null
	data["beakerVolume"] = 0
	if(beaker)
		data["beakerLabel"] = beaker.label_text ? beaker.label_text : null
		if(beaker.reagents && beaker.reagents.reagent_list.len)
			for(var/datum/reagent/R in beaker.reagents.reagent_list)
				data["beakerVolume"] += R.volume

	return data

/obj/machinery/atmospherics/unary/cryo_cell/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_CRYO)
	if(ui.user == occupant)
		return FALSE
	return TRUE

UI_ACT(/obj/machinery/atmospherics/unary/cryo_cell, "switchOn", ui_act_switchon)
UI_ACT_PROC(/obj/machinery/atmospherics/unary/cryo_cell, ui_act_switchon)
	. = TRUE
	set_on(1)
	add_fingerprint(ui.user)

UI_ACT(/obj/machinery/atmospherics/unary/cryo_cell, "switchOff", ui_act_switchoff)
UI_ACT_PROC(/obj/machinery/atmospherics/unary/cryo_cell, ui_act_switchoff)
	. = TRUE
	set_on(0)
	add_fingerprint(ui.user)

UI_ACT(/obj/machinery/atmospherics/unary/cryo_cell, "ejectBeaker", ui_act_ejectbeaker)
UI_ACT_PROC(/obj/machinery/atmospherics/unary/cryo_cell, ui_act_ejectbeaker)
	. = TRUE
	if(beaker)
		beaker.forceMove(get_step(src.loc, SOUTH))
		own_take(src, "beaker")
		update_icon()
	add_fingerprint(ui.user)

UI_ACT(/obj/machinery/atmospherics/unary/cryo_cell, "ejectOccupant", ui_act_ejectoccupant)
UI_ACT_PROC(/obj/machinery/atmospherics/unary/cryo_cell, ui_act_ejectoccupant)
	. = TRUE
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_CRYO)
	if(!occupant || isslime(ui.user) || ispAI(ui.user))
		return 0 // don't update UIs attached to this object
	go_out()
	add_fingerprint(ui.user)

/// Old attackby. It never called ..(), so every item stops here.
/obj/machinery/atmospherics/unary/cryo_cell/proc/cryo_cell_interaction_item(mob/user, obj/item/G, datum/interaction/interaction)
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_CRYO)
	if(istype(G, /obj/item/reagent_containers/glass))
		if(beaker)
			to_chat(user, span_warning("A beaker is already loaded into the machine."))
			return TRUE

		user.drop_item()
		G.forceMove(src)
		own_set(src, "beaker", G)
		act_message(user, src, MSG_SELF("You add \a [G] to %T%!"), MSG_OTHERS("%U% adds \a [G] to %T%!"))
		SStgui.update_uis(src)
		update_icon()
	else if(istype(G, /obj/item/grab))
		var/obj/item/grab/grab = G
		var/mob/M = grab?.grab_target()
		if(!ismob(M))
			return TRUE
		if(occupant)
			to_chat(user,span_warning("\The [src] is already occupied by [occupant]."))
		if(M.has_buckled_mobs())
			to_chat(user, span_warning("\The [M] has other entities attached to it. Remove them first."))
			return TRUE
		consume(grab, user)
		put_mob(M)

	return TRUE

/// Old MouseDrop_T: allows borgs to put people into cryo without external assistance.
/obj/machinery/atmospherics/unary/cryo_cell/proc/cryo_cell_interaction_drag(mob/user, mob/target, datum/interaction/interaction)
	if(!ismob(target) || user.stat || user.lying || !Adjacent(user) || !target.Adjacent(user)|| !ishuman(target))
		return FALSE
	put_mob(target)
	return TRUE

DECLARE_APPEARANCE_PROC(/obj/machinery/atmospherics/unary/cryo_cell, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/atmospherics/unary/cryo_cell/appearance_overlays()
	. = list()
	fluid.color = null
	if(on)
		if(beaker)
			fluid.color = beaker.reagents.get_color()
		. += fluid

/obj/machinery/atmospherics/unary/cryo_cell/proc/process_occupant()
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_CRYO)
	if(air_contents.total_moles() < 10)
		return
	if(occupant)
		if(occupant.stat >= DEAD)
			return
		// The occupant and the cell's gas settle to a shared temperature; the
		// heat the body loses is what the gas gains.
		var/air_heat_capacity = air_contents.heat_capacity()
		var/equilibrium_temperature = (HUMAN_HEAT_CAPACITY * occupant.bodytemperature + air_heat_capacity * air_contents.return_temperature()) / (HUMAN_HEAT_CAPACITY + air_heat_capacity)
		occupant.set_bodytemperature(equilibrium_temperature)
		air_contents.set_temperature(equilibrium_temperature)
		occupant.set_stat(UNCONSCIOUS)
		occupant.dir = SOUTH
		if(occupant.bodytemperature < T0C)
			occupant.status_at_least(EFFECT_SLEEPING, max(5, (1/occupant.bodytemperature)*2000))
			occupant.status_at_least(EFFECT_PARALYZED, max(5, (1/occupant.bodytemperature)*3000))
			if(!treat_occupant())
				return
		var/has_cryo = occupant.reagents.get_reagent_amount(REAGENT_ID_CRYOXADONE) >= 1
		var/has_clonexa = occupant.reagents.get_reagent_amount(REAGENT_ID_CLONEXADONE) >= 1
		var/has_cryo_medicine = has_cryo || has_clonexa
		if(beaker && !has_cryo_medicine)
			beaker.reagents.trans_to_mob(occupant, 1, CHEM_BLOOD, 10, can_dialysis = FALSE)

/// One tick of cold treatment, decided by automated triage: mend the demanded
/// tags at the cell's rates, or release a patient triage finds healthy.
/// Returns FALSE when the occupant was released.
/obj/machinery/atmospherics/unary/cryo_cell/proc/treat_occupant()
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_CRYO)
	if(!occupant)
		return FALSE
	var/list/demand = occupant.treatment_demand(/datum/diagnostic_profile/automation)
	if(demand)
		var/list/rates = cryo_treatment_rates(occupant.bodytemperature)
		for(var/tag in rates)
			if(demand[tag])
				occupant.mend(tag, rates[tag])
	else
		var/datum/diagnosis/D = occupant.diagnose(/datum/diagnostic_profile/automation)
		var/healthy = D?.band == DIAG_BAND_NONE && D.status == DIAG_STATUS_ALIVE
		qdel(D)
		if(healthy)
			release_treated_occupant()
			return FALSE
	if(occupant.bodytemperature < CRYO_DEEP_COLD && (occupant.radiation || occupant.accumulated_rads))
		occupant.purge_radiation(25)
	return TRUE

/// What the cell's cold (and the beaker's chemistry) treats this tick at
/// `temperature`: TREAT_* -> amount. Below freezing the cell only oxygenates;
/// below CRYO_DEEP_COLD it repairs tissue, colder being faster, and each
/// beaker reagent's treatment tags multiply the matching rates.
/obj/machinery/atmospherics/unary/cryo_cell/proc/cryo_treatment_rates(temperature)
	var/list/rates = list(TREAT_OXYGENATION = CRYO_BASE_RATE)
	if(temperature >= CRYO_DEEP_COLD)
		return rates
	var/cold = CRYO_BASE_RATE * (1 + (CRYO_DEEP_COLD - temperature) / CRYO_DEEP_COLD)
	for(var/tag in list(TREAT_TISSUE_REPAIR, TREAT_HEMOSTATIC, TREAT_BURN_CARE, TREAT_ANTITOXIN, TREAT_GENETIC_REPAIR))
		rates[tag] = cold
	for(var/datum/reagent/R as anything in beaker?.reagents?.reagent_list)
		for(var/tag in R.treatment_tags)
			if(rates[tag])
				rates[tag] *= 1 + R.treatment_tags[tag]
	return rates

/// Triage finds nothing left to treat: stop the treatment and release the
/// occupant (once awake enough to leave).
/obj/machinery/atmospherics/unary/cryo_cell/proc/release_treated_occupant()
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_CRYO)
	if(!occupant)
		return
	log_game("CRYO: [src] released [key_name(occupant)]: automated triage reports no remaining treatment demand.")
	visible_message(span_notice("\The [src] pings: treatment complete."))
	play_sfx(src, SFX_MACHINES_PING)
	go_out()

/obj/machinery/atmospherics/unary/cryo_cell/proc/expel_gas()
	if(air_contents.total_moles() < 1)
		return

	// Just have the gas disappear to nowhere.
	//expel_gas.temperature = T20C // Lets expel hot gas and see if that helps people not die as they are removed
	//loc.assume_air(expel_gas)

/obj/machinery/atmospherics/unary/cryo_cell/proc/go_out()
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_CRYO)
	if(!(occupant))
		return
	vis_contents -= occupant
	occupant.pixel_x = occupant.default_pixel_x
	occupant.pixel_y = occupant.default_pixel_y
	if(occupant.bodytemperature < 261 && occupant.bodytemperature >= 70) //Patch by Aranclanos to stop people from taking burn damage after being ejected
		occupant.set_bodytemperature(261) // Changed to 70 from 140 by Zuhayr due to reoccurance of bug.
	unbuckle_mob(occupant, force = TRUE)
	occupant.cozyloop.stop() // Cozy Music
	//this doesn't account for walls or anything, but i don't forsee that being a problem.
	slot_remove(occupant, get_step(src.loc, SOUTH))
	set_use_power(USE_POWER_IDLE)
	SStgui.update_uis(src)
	return

/obj/machinery/atmospherics/unary/cryo_cell/proc/put_mob(mob/living/carbon/M as mob)
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_CRYO)
	if(!operable())
		to_chat(usr, span_warning("The cryo cell is not functioning."))
		return
	if(!istype(M))
		to_chat(usr, span_danger("The cryo cell cannot handle such a lifeform!"))
		return
	if(occupant)
		to_chat(usr, span_danger("The cryo cell is already occupied!"))
		return
	if(M.abiotic())
		to_chat(usr, span_warning("Subject may not have abiotic items on."))
		return
	if(!node)
		to_chat(usr, span_warning("The cell is not correctly connected to its pipe network!"))
		return
	M.stop_pulling()
	if(!M.move_into(src, OCCUPANT_SLOT_CRYO))
		return
	M.extinguish_mob()
	if(M.stat != DEAD && (M.is_critical() || M.has_status(EFFECT_SLEEPING)))
		to_chat(M, span_boldnotice("You feel a cold liquid surround you. Your skin starts to freeze up."))
	occupant.cozyloop.start() // Cozy Music
	buckle_mob(occupant, forced = TRUE, check_loc = FALSE)
	vis_contents |= occupant
	occupant.pixel_y += 19
	set_use_power(USE_POWER_ACTIVE)
	add_fingerprint(usr)
	SStgui.update_uis(src)
	return 1

/// The occupant's two-minute release sequence finished.
/obj/machinery/atmospherics/unary/cryo_cell/proc/release_sequence_done(mob/living/carbon/who)
	if(src?.slot_item(OCCUPANT_SLOT_CRYO) != who) //Check if someone's released/replaced/bombed him already
		return
	go_out()//and release him from the eternal prison.

/// Old verb "Eject occupant".
/obj/machinery/atmospherics/unary/cryo_cell/proc/cryo_cell_move_eject(mob/user, obj/item/held, datum/interaction/interaction)
	var/mob/living/carbon/occupant = src?.slot_item(OCCUPANT_SLOT_CRYO)
	if(user == occupant)//If the user is inside the tube...
		if(user.stat == 2)//and he's not dead....
			return
		to_chat(user, span_notice("Release sequence activated. This will take two minutes."))
		om_after(src, 2 MINUTES, PROC_REF(release_sequence_done), user)
	else
		if(user.stat != 0)
			return
		go_out()
	add_fingerprint(user)
	return

/// Old verb "Move Inside".
/obj/machinery/atmospherics/unary/cryo_cell/proc/cryo_cell_move_inside(mob/user, obj/item/held, datum/interaction/interaction)
	if(isliving(user))
		var/mob/living/L = user
		if(L.has_buckled_mobs())
			to_chat(L, span_warning("You have other entities attached to yourself. Remove them first."))
			return
		if(L.stat != CONSCIOUS)
			return
		put_mob(L)

/atom/proc/return_air_for_internal_lifeform(mob/living/lifeform)
	return return_air()

/obj/machinery/atmospherics/unary/cryo_cell/return_air_for_internal_lifeform()
	//assume that the cryo cell has some kind of breath mask or something that
	//draws from the cryo tube's environment, instead of the cold internal air.
	if(src.loc)
		return loc.return_air()
	else
		return null

/datum/data/function/proc/reset()
	return

/datum/data/function/proc/r_input(href, href_list, mob/user)
	return

/datum/data/function/proc/display()
	return

/obj/machinery/atmospherics/unary/cryo_cell/step_has_work()
	return on && node

#undef CRYO_BASE_RATE
#undef CRYO_DEEP_COLD

