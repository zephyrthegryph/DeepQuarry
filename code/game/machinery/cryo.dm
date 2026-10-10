// The cryo cell (doc/rewrite/final_api.html sections 14 and 16.4, doc/rewrite/conversion_guide.md).
//
// ONE CAPABILITIES list says what it is: a machine (machine_basics()) and an occupant pod (occupant_pod(): a person, or any carbon, is dragged or
// grabbed in at once, climbs in from the menu, is let out from the menu or by moving; the occupant's own eject is a two-minute release sequence; they
// leave to the south when that tile is open, else onto the cell's own; they are shown in the tube; tools wait for an empty cell). Entering needs a
// working cell joined to its pipe. While the cell is on and works, its occupant is held asleep (a while_slotted() status, gated on the cell: a cell
// switched off or out of power lets them wake, and nobody releases anything by hand), and every machine interval the cell trades heat with them
// through the gas domain, sends the frozen deeper under, treats what automated triage demands, and drips its beaker into them. The beaker sits in a
// bay (beaker_bay()), its eject button leaving it where the occupant leaves.
//
// Its on-state is its own tracked `cooling` (set_cooling()), and its pipe is the unary device's (piped(), as a vent's or a scrubber's). The gas
// domain wakes the pipe network when the occupant's heat moves the cell's gas (its heat_link() entry); nothing here marks it by hand.
// What the machine core still keeps until the machine track (phase 4): the stat bits read through machine_basics()'s bridge, set_use_power(), and
// maintenance_flags (the panel and the crowbar).

/// Mend per tick at the base rate (oxygenation below freezing).
#define CRYO_BASE_RATE 1
/// Below this the cell repairs tissue, faster the colder it is.
#define CRYO_DEEP_COLD 225
/// The cell does nothing with less gas than this in it (moles).
#define CRYO_MIN_MOLES 10
/// Below freezing the cold sends the occupant under: sleep for CRYO_SLEEP_SCALE / body temperature status units, paralysis for
/// CRYO_PARALYSIS_SCALE / body temperature, at least CRYO_MIN_STATUS of each.
#define CRYO_SLEEP_SCALE 2000
#define CRYO_PARALYSIS_SCALE 3000
#define CRYO_MIN_STATUS 5
/// The beaker drips this many units a tick into a patient carrying no cryo medicine, at this multiplier.
#define CRYO_DRIP_UNITS 1
#define CRYO_DRIP_MULTIPLIER 10
/// An occupant leaving colder than this, but not frozen solid below CRYO_THAW_FLOOR, is warmed to it on the way out (no burns from the thaw).
#define CRYO_THAW_TEMPERATURE 261
#define CRYO_THAW_FLOOR 70
/// The tube's glass and fluid: raised over the base and see-through.
#define CRYO_GLASS_RAISE 18
#define CRYO_GLASS_ALPHA 200

MSG_DEF_SELF(cryo_cell/not_connected, "The cell is not correctly connected to its pipe network!")
MSG_DEF_SELF(cryo_cell/cannot_release, "You can't work the release.")
MSG_DEF_SELF(cryo_cell/cold_liquid, "You feel a cold liquid surround you. Your skin starts to freeze up.")

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

	use_power = USE_POWER_IDLE
	idle_power_usage = 20
	active_power_usage = 200
	buckle_lying = FALSE
	buckle_dir = SOUTH
	clicksound = SFX_MACHINES_BUTTONBEEP
	clickvol = 30

	var/obj/item/reagent_containers/glass/beaker = null
	/// Switched on from its window: it holds its occupant under and trades heat with them while it works.
	var/cooling = FALSE

TRACKED(/obj/machinery/atmospherics/unary/cryo_cell, cooling)

/// The occupant's body against the cell's gas, W/K: the old full settle per service interval, as a conductance (the body's capacity over two
/// seconds), so the pair meets within an interval whatever the step length.
#define CRYO_OCCUPANT_CONDUCTANCE (HUMAN_HEAT_CAPACITY / 2)

/// The occupant is linked to the cell's gas by its heat entry, not coupled to the room.
/obj/machinery/atmospherics/unary/cryo_cell/interior_heat_reservoir()
	return HEAT_TARGET_NONE

CAPABILITIES(/obj/machinery/atmospherics/unary/cryo_cell)
	machine_basics(repair = NONE)
	occupant_pod(OCCUPANT_SLOT_CRYO, accepts = /mob/living/carbon, exit_to = SOUTH, controls_inside = FALSE, eject_wait_inside = CRYO_RELEASE_WAIT, shown_y = CRYO_OCCUPANT_RAISE, bare = TRUE)
	extend(TAG_POD_ENTER, needs(req_operable(), req_bool(PROC_REF(piped), because = MSG(cryo_cell/not_connected))))
	when(cond_all(nameof(cooling), STAT_OPERABLE), while_slotted(OCCUPANT_SLOT_CRYO, holds_status(STAT_SLEEPING), on = ON_CONTENTS))
	// While it works, the occupant's body and the cell's gas trade heat through one link (the heat domain conserves it and wakes the pipe network).
	when(cond_all(nameof(cooling), STAT_OPERABLE), while_slotted(OCCUPANT_SLOT_CRYO, heat_link(HEAT_HOLDER, HEAT_PORT(1), CRYO_OCCUPANT_CONDUCTANCE), on = ON_CONTENTS))
	owns_one(nameof(beaker), /obj/item/reagent_containers/glass, on_destroy = ON_DESTROY_SPILL)
	beaker_bay(nameof(beaker), eject_button = "ejectBeaker", exit_to = SOUTH)
	space(SPACE_PANEL, door = nameof(panel_open))
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(cooling_frame)), when = cond_all(nameof(cooling), STAT_OPERABLE, OCCUPANT_POD_OCCUPIED))
	on_notice(/datum/notice/pod_entered, then(PROC_REF(occupant_entered)))
	on_notice(/datum/notice/pod_left, then(PROC_REF(occupant_left)))
	section(window, "the cell's window: its occupant takes no part in it (occupant_pod(controls_inside = FALSE)), and it opens unpowered")
	interface("Cryo", title = "Cryo Cell")
	extend("ui_open", ungated(), needs(req_closed(SPACE_PANEL), req_bool(PROC_REF(actor_outside), silent = TRUE)))
	extend(TAG_UI, then(PROC_REF(control_touched), early = TRUE))
	op("switchOn", ui_act("switchOn"), then(PROC_REF(switch_on)))
	op("switchOff", ui_act("switchOff"), then(PROC_REF(switch_off)))
	op("ejectOccupant", ui_act("ejectOccupant"), needs(req_is(OCCUPANT_POD_OCCUPIED, because = MSG(occupant_pod/empty)), req_actor_kind(list(/mob/living/simple_mob/slime, /mob/living/silicon/pai), not = TRUE, because = MSG(cryo_cell/cannot_release))),
		then(PROC_REF(eject_from_window)), logs(LOG_GAME))

// ALLOW(init/INSTANCE_STATE): its pipe connection follows the direction it was placed in
/obj/machinery/atmospherics/unary/cryo_cell/Initialize(mapload)
	. = ..()
	initialize_directions = dir

// ---- conditions ----

/// The actor is not the one inside.
/obj/machinery/atmospherics/unary/cryo_cell/proc/actor_outside(datum/act/op/A)
	return A.actor != occupant_of(src)

// ---- the window's buttons ----

/obj/machinery/atmospherics/unary/cryo_cell/proc/control_touched(datum/act/op/A)
	add_fingerprint(A.actor)

/obj/machinery/atmospherics/unary/cryo_cell/proc/switch_on(datum/act/op/A)
	set_cooling(TRUE)
	return OP_OK

/obj/machinery/atmospherics/unary/cryo_cell/proc/switch_off(datum/act/op/A)
	set_cooling(FALSE)
	return OP_OK

/obj/machinery/atmospherics/unary/cryo_cell/proc/eject_from_window(datum/act/op/A)
	if(!length(occupant_eject(src)))
		return OP_FAILED
	return OP_OK

// ---- the occupant ----

/// Someone got in (by any path): the fire on them goes out, the cold reaches them, they are held upright in the tube, the cell draws full power.
/obj/machinery/atmospherics/unary/cryo_cell/proc/occupant_entered(datum/act/A)
	var/datum/notice/pod_entered/N = A
	var/mob/living/carbon/M = N.occupant
	if(!istype(M))
		return
	M.extinguish_mob()
	if(M.stat != DEAD && (M.is_critical() || M.has_status(STAT_SLEEPING)))
		act_message_t(M, src, /datum/msg/cryo_cell/cold_liquid)
	M.cozyloop?.start() // Cozy Music
	buckle_mob(M, forced = TRUE, check_loc = FALSE)
	set_use_power(USE_POWER_ACTIVE)

/// They left (by any path): unbuckled, thawed to CRYO_THAW_TEMPERATURE when chilled but not frozen solid, the music stops, the cell idles.
/obj/machinery/atmospherics/unary/cryo_cell/proc/occupant_left(datum/act/A)
	var/datum/notice/pod_left/N = A
	var/mob/living/carbon/M = N.occupant
	if(istype(M))
		if(M.buckled_to() == src)
			unbuckle_mob(M, force = TRUE)
		if(M.body_temperature() < CRYO_THAW_TEMPERATURE && M.body_temperature() >= CRYO_THAW_FLOOR) //Patch by Aranclanos to stop people from taking burn damage after being ejected
			M.set_bodytemperature(CRYO_THAW_TEMPERATURE)
		M.cozyloop?.stop() // Cozy Music
	set_use_power(USE_POWER_IDLE)

// ---- one machine interval, while the cell is on, works and is occupied ----

/obj/machinery/atmospherics/unary/cryo_cell/proc/cooling_frame(datum/act/timer/A)
	var/mob/living/carbon/occupant = occupant_of(src)
	if(!occupant || occupant.stat == DEAD || !piped() || !air_contents || air_contents.total_moles() < CRYO_MIN_MOLES)
		return
	if(occupant.body_temperature() < T0C)
		occupant.status_at_least(STAT_SLEEPING, max(CRYO_MIN_STATUS, CRYO_SLEEP_SCALE / occupant.body_temperature()))
		occupant.status_at_least(STAT_PARALYZED, max(CRYO_MIN_STATUS, CRYO_PARALYSIS_SCALE / occupant.body_temperature()))
		if(!treat_occupant())
			return
	var/has_cryo_medicine = occupant.reagents.get_reagent_amount(REAGENT_ID_CRYOXADONE) >= 1 || occupant.reagents.get_reagent_amount(REAGENT_ID_CLONEXADONE) >= 1
	if(beaker && !has_cryo_medicine)
		beaker.reagents.trans_to_mob(occupant, CRYO_DRIP_UNITS, CHEM_BLOOD, CRYO_DRIP_MULTIPLIER, can_dialysis = FALSE)

/// One tick of cold treatment, decided by automated triage: mend the demanded tags at the cell's rates, or release a patient triage finds healthy.
/// Returns FALSE when the occupant was released.
/obj/machinery/atmospherics/unary/cryo_cell/proc/treat_occupant()
	var/mob/living/carbon/occupant = occupant_of(src)
	if(!occupant)
		return FALSE
	var/list/demand = occupant.treatment_demand(/datum/diagnostic_profile/automation)
	if(demand)
		var/list/rates = cryo_treatment_rates(occupant.body_temperature())
		for(var/tag in rates)
			if(demand[tag])
				occupant.mend(tag, rates[tag])
	else
		var/datum/diagnosis/D = occupant.diagnose(/datum/diagnostic_profile/automation)
		var/healthy = D?.band == DIAG_BAND_NONE && D.status == DIAG_STATUS_ALIVE
		spent(D)
		if(healthy)
			release_treated_occupant(occupant)
			return FALSE
	if(occupant.body_temperature() < CRYO_DEEP_COLD && (occupant.radiation || occupant.accumulated_rads))
		occupant.purge_radiation(25)
	return TRUE

/// What the cell's cold (and the beaker's chemistry) treats this tick at `temperature`: TREAT_* -> amount. Below freezing the cell only oxygenates;
/// below CRYO_DEEP_COLD it repairs tissue, colder being faster, and each beaker reagent's treatment tags multiply the matching rates.
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

/// Triage finds nothing left to treat: stop the treatment and release the occupant.
/obj/machinery/atmospherics/unary/cryo_cell/proc/release_treated_occupant(mob/living/carbon/occupant)
	log_game("CRYO: [src] released [key_name(occupant)]: automated triage reports no remaining treatment demand.")
	visible_message(span_notice("\The [src] pings: treatment complete."))
	play_sfx(src, SFX_MACHINES_PING)
	occupant_eject(src)

// ---- what it shows ----

/// The split sprite: the cell's base, its occupant in the tube (occupant_pod(shown_y)), the fluid tinted by the beaker while it runs, and the glass.
/obj/machinery/atmospherics/unary/cryo_cell/draw(datum/look/look)
	..()
	look.set_icon('icons/obj/cryogenics_split.dmi')
	look.state("base")
	if(cooling)
		// ALLOW(sys_dx_untracked_read): the fluid takes the beaker's colour when the cell is switched on or its beaker changes, not as the mix drains
		look.overlay(look_overlay_image('icons/obj/cryogenics_split.dmi', "tube_filler", layer = MOB_LAYER + 0.1, plane = MOB_PLANE, alpha = CRYO_GLASS_ALPHA, pixel_y = CRYO_GLASS_RAISE, color = beaker?.reagents.get_color())) //Below glass, above mob
	look.overlay(look_overlay_image('icons/obj/cryogenics_split.dmi', "tank", layer = MOB_LAYER + 0.2, plane = MOB_PLANE, alpha = CRYO_GLASS_ALPHA, pixel_y = CRYO_GLASS_RAISE)) //Above fluid

/obj/machinery/atmospherics/unary/cryo_cell/ui_data(datum/act/eval/A)
	var/mob/living/carbon/occupant = occupant_of(src)
	var/list/data = list()
	data["isOperating"] = cooling
	data["hasOccupant"] = occupant ? TRUE : FALSE

	var/list/occupantData = list()
	if(occupant)
		occupantData["name"] = occupant.name
		occupantData["stat"] = occupant.stat
		occupantData["vitality"] = round(occupant.vitality() * 100)
		occupantData["critical"] = occupant.is_critical()
		var/datum/diagnosis/D = occupant.diagnose(/datum/diagnostic_profile/automation)
		occupantData["diagnosis"] = D.report_data()
		spent(D)
		occupantData["bodyTemperature"] = occupant.body_temperature()
	data["occupant"] = occupantData

	var/air_temperature = air_contents.return_temperature()
	data["cellTemperature"] = round(air_temperature)
	data["cellTemperatureStatus"] = "good"
	if(air_temperature > T0C)
		data["cellTemperatureStatus"] = "bad"
	else if(air_temperature > CRYO_DEEP_COLD)
		data["cellTemperatureStatus"] = "average"

	data["isBeakerLoaded"] = beaker ? TRUE : FALSE
	data["beakerLabel"] = null
	data["beakerVolume"] = 0
	if(beaker)
		data["beakerLabel"] = beaker.label_text ? beaker.label_text : null
		for(var/datum/reagent/R as anything in beaker.reagents?.reagent_list)
			data["beakerVolume"] += R.volume
	return data

/atom/proc/return_air_for_internal_lifeform(mob/living/lifeform)
	return return_air()

/obj/machinery/atmospherics/unary/cryo_cell/return_air_for_internal_lifeform()
	//assume that the cryo cell has some kind of breath mask or something that
	//draws from the cryo tube's environment, instead of the cold internal air.
	if(src.loc)
		return loc.return_air()
	else
		return null

#undef CRYO_BASE_RATE
#undef CRYO_DEEP_COLD
#undef CRYO_MIN_MOLES
#undef CRYO_SLEEP_SCALE
#undef CRYO_PARALYSIS_SCALE
#undef CRYO_MIN_STATUS
#undef CRYO_DRIP_UNITS
#undef CRYO_DRIP_MULTIPLIER
#undef CRYO_THAW_TEMPERATURE
#undef CRYO_THAW_FLOOR
#undef CRYO_GLASS_RAISE
#undef CRYO_GLASS_ALPHA
