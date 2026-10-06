// The radiation collector array (doc/rewrite/final_api.html section 16): a power producer for the singularity and supermatter engines. Loaded with
// a phoron tank, bolted down (anchor(); bolted, it joins the cable network on its tile) and switched on, every radiation pulse that reaches it
// (the in_range_of_irradiation notice) supplies phoron moles * pulse strength * RAD_COLLECTOR_POWER_PER_RAD W for the next power step and burns
// a little of the phoron; a singularity within 15 tiles pulses it directly (receive_pulse()). Its switch is behind an ID lock that only locks
// while it runs; a crowbar takes the tank out of an unlocked collector, and a blast knocks it out.
//
// SAFETY: the output curve is pinned in code/modules/unit_tests/dq_power_plants_behaviour.dm (collector_output, sing_pulse_feeds_collectors).

/// W supplied per mole of phoron per unit of pulse strength.
#define RAD_COLLECTOR_POWER_PER_RAD 20
/// Moles of phoron one pulse burns, times drainratio.
#define RAD_COLLECTOR_FUEL_PER_PULSE 0.0001

MSG_DEF_SELF(collector/unanchored, "It needs to be secured to the floor first.")
MSG_DEF_SELF(collector/tank_loaded, "There's already a phoron tank loaded.")
MSG_DEF_SELF(collector/controls_locked, "The controls are locked!")
MSG_DEF_SELF(collector/lock_needs_active, "The controls can only be locked while it is active.")
MSG_DEF(collector/tank_in, "You load %I% into %T%.", "%U% loads %I% into %T%.")

/obj/machinery/power/rad_collector
	name = "Radiation Collector Array"
	desc = "A device which uses Hawking Radiation and phoron to produce power."
	icon = 'icons/obj/singularity.dmi'
	icon_state = "ca"
	anchored = FALSE
	density = TRUE
	req_access = list(ACCESS_ENGINE_EQUIP)
	/// The loaded phoron tank (owned, in its contents; dropped when the collector is destroyed).
	var/tmp/obj/item/tank/phoron/P
	/// What the meter shows: the power of the pulse before the last.
	var/last_power = 0
	var/last_power_new = 0
	active = 0
	var/drainratio = 1
	rad_shield_material = MAT_LEAD
	rad_shield_thickness_mm = RAD_COLLECTOR_THICKNESS_MM
	rad_insulation = RAD_EXTREME_INSULATION //It sucks up the radiation. If you're standing behind it, you're pretty safe.

CAPABILITIES(/obj/machinery/power/rad_collector)
	climb()
	registry(REGISTRY_RAD_COLLECTORS)
	owns_one(nameof(P), /obj/item/tank/phoron, on_destroy = ON_DESTROY_SPILL)
	anchor(empty = nameof(P))
	lock(powered = FALSE, alt = FALSE)
	extend("lock.toggle", needs(req_is(nameof(active), TRUE, because = MSG(collector/lock_needs_active))))
	on_change(nameof(anchored), ANY, then(PROC_REF(anchoring_changed)))
	on_notice(/datum/notice/in_range_of_irradiation, then(PROC_REF(process_rads)))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(collector_blast_eject))))
	examine_line(PROC_REF(examine_meter))
	op("toggle", hand(), when(req_empty_hand()), label("Toggle"), ungated(), wait(0), when(nameof(anchored)), global.tag(TAG_CONTROL), then(PROC_REF(toggled)))
	op("load", item(/obj/item/tank/phoron), label("Load phoron tank"), wait(0),
		needs(req_is(nameof(anchored), TRUE, because = MSG(collector/unanchored)), req_empty(nameof(P), because = MSG(collector/tank_loaded))),
		says(MSG(collector/tank_in)), put_in(nameof(P)), then(PROC_REF(tank_changed)))
	op("eject", tool(TOOL_CROWBAR), label("Remove the tank"), wait(0), when(nameof(P)), global.tag(TAG_CONTROL), then(PROC_REF(pried)))

// ---- what reaches it ----

/// A radiation pulse reached it: it collects, and burns phoron (an empty tank comes out).
/obj/machinery/power/rad_collector/proc/process_rads(datum/act/A)
	var/datum/notice/in_range_of_irradiation/event = A
	var/datum/radiation_pulse_information/pulse_information = event.pulse_information
	//so that we don't zero out the meter if the SM is processed first.
	last_power = last_power_new
	last_power_new = 0
	if(!P || !active || !pulse_information)
		return
	receive_pulse(pulse_information.strength)
	if(LINDA_GAS_AMT(P.air_contents, GAS_PHORON) == 0)
		investigate_log(span_red("out of fuel") + ".","singulo")
		eject()
	else
		P.air_contents.adjust_gas(GAS_PHORON, -RAD_COLLECTOR_FUEL_PER_PULSE * drainratio)

// Continuing here, SM giving us ~170 rads per pulse, a phoron canister full of 30 mols, and * 20 we get:
// 102000W per collector...So 10 collectors will give us ~1MW.
/obj/machinery/power/rad_collector/proc/receive_pulse(pulse_strength)
	if(!P || !active)
		return
	var/power_produced = LINDA_GAS_AMT(P.air_contents, GAS_PHORON) * pulse_strength * RAD_COLLECTOR_POWER_PER_RAD
	if(power_produced)
		add_avail(power_produced)
		last_power_new = power_produced

/// A lesser blast knocks the tank out; the blast itself goes on.
/obj/machinery/power/rad_collector/proc/collector_blast_eject(datum/act/hit/explosion/A)
	switch(A.packet.severity)
		if(2, 3)
			eject()
	return HOOK_DECLINE

// ---- the controls ----

/obj/machinery/power/rad_collector/proc/toggled(datum/act/op/A)
	var/mob/user = A.actor
	toggle_power()
	act_message(user, null, MSG_SELF("You turn the [src.name] [active? "on":"off"]."), MSG_OTHERS("[user.name] turns the [src.name] [active? "on":"off"]."))
	investigate_log("turned [active?span_green("on"): span_red("off")] by [user.key]. [P?"Fuel: [round(LINDA_GAS_AMT(P.air_contents, GAS_PHORON)/0.29)]%":span_red("It is empty")].","singulo")
	return OP_OK

/obj/machinery/power/rad_collector/proc/pried(datum/act/op/A)
	eject()
	return OP_OK

/obj/machinery/power/rad_collector/proc/tank_changed(datum/act/A)
	update_icon()
	return OP_OK

/// Bolted down it joins the cable network on its tile; loose it leaves it.
/obj/machinery/power/rad_collector/proc/anchoring_changed(datum/act/A)
	if(anchored)
		connect_to_network()
	else
		disconnect_from_network()

/obj/machinery/power/rad_collector/proc/examine_meter(datum/act/eval/A)
	if(A.actor && get_dist(A.actor, src) <= 3)
		return "The meter indicates that it is collecting [last_power] W."
	return null

/// The tank comes out onto the floor, the lock opens and it switches off.
/obj/machinery/power/rad_collector/proc/eject()
	key_set(src, LOCK_LOCKED, FALSE)
	var/obj/item/tank/phoron/Z = P
	if (!Z)
		return
	rel_take(src, nameof(P)) // dropped on the floor
	Z.forceMove(get_turf(src))
	Z.layer = initial(Z.layer)
	if(active)
		toggle_power()
	else
		update_icon()

/obj/machinery/power/rad_collector/proc/toggle_power()
	set_active(!active)
	if(!active)
		key_set(src, LOCK_LOCKED, FALSE)
	flick(active ? "ca_active" : "ca_deactive", src)
	update_icon()

/obj/machinery/power/rad_collector/draw(datum/look/look)
	..()
	look.state(active ? "ca_on" : "ca")
	look.overlay("ptank", when = P)
	look.overlay("on", when = active && operable())

#undef RAD_COLLECTOR_POWER_PER_RAD
#undef RAD_COLLECTOR_FUEL_PER_PULSE
