// The emitter (doc/rewrite/final_api.html section 16): a heavy industrial laser that feeds the singularity engine's field generators and the
// supermatter. It is bolted and welded to the floor (floor_weld(); welded, it joins the cable network on its tile), switched on by hand or by a
// remote emitter button (activate()), and its controls are behind an ID lock (lock(); an emag shorts the lock open for good). While it is on
// and whole it charges from the grid (charge_emitter(), material_equipment.dm) and fires every machine service interval its shot is ready
// (emitter_step()): bursts of burst_shots shots burst_delay apart, then a random min_burst_delay..max_burst_delay pause. Steel sheets repair it,
// an anomaly scanner switches it to anomalous particles, and a multitool picks the particle.
//
// SAFETY: the shot energy and the burst pattern are pinned in code/modules/unit_tests/dq_power_plants_behaviour.dm (emitter_*).

MSG_DEF_SELF(emitter/unwelded, "It needs to be firmly secured to the floor first.")
MSG_DEF_SELF(emitter/controls_locked, "The controls are locked!")
MSG_DEF_SELF(emitter/whole, "It's already fully repaired.")
MSG_DEF_SELF(emitter/too_few_sheets, "You don't have enough sheets to repair it.")
MSG_DEF(emitter/repairing, "You begin repairing %T%...", "%U% begins repairing %T%.")
MSG_DEF(emitter/shorted, "You short out the lock.", "%U% emags %T%.")

/obj/machinery/power/emitter
	material_template = /datum/material_template/energy_device
	material_total = 10 * SHEET_MATERIAL_AMOUNT
	name = "emitter"
	desc = "It is a heavy duty industrial laser."
	icon = 'icons/obj/singularity_vr.dmi' // New emitter sprite
	icon_state = "emitter0"
	anchored = FALSE
	density = TRUE
	unacidable = TRUE
	req_access = list(ACCESS_ENGINE_EQUIP)
	var/id = null

	use_power = USE_POWER_OFF	//uses grid power, not APC power
	active_power_usage = 30000	//30 kW laser. I guess that means 30 kJ per shot.

	active = 0
	/// It had the energy for its last shot (the beam overlay shows while it has).
	var/powered = 0
	var/fire_delay = 100
	var/max_burst_delay = 100
	var/min_burst_delay = 20
	var/burst_shots = 3
	COOLDOWN_DECLARE(shot_cooldown)
	var/shot_number = 0
	var/state = 0

	// Anomaly harvesting stuff
	var/anomalous = FALSE
	var/particle = ANOMALY_PARTICLE_SIGMA

	var/burst_delay = 2
	var/initial_fire_delay = 100
	/// The rung the sprite last showed, for the flick between rungs.
	var/previous_state = 0

	max_integrity = 80

TRACKED(/obj/machinery/power/emitter, anomalous)

CAPABILITIES(/obj/machinery/power/emitter)
	climb()
	rotatable()
	floor_weld(busy = nameof(active), changed = PROC_REF(rung_moved))
	lock(powered = FALSE, alt = FALSE)
	emag(then(PROC_REF(on_emag)), say = MSG(emitter/shorted), powered = FALSE)
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(emitter_step)), when = PROC_REF(firing))
	op("toggle", hand(), when(req_empty_hand()), label("Use"), ungated(), wait(0), global.tag(TAG_CONTROL),
		needs(req_bool(PROC_REF(is_welded), because = MSG(emitter/unwelded))),
		then(PROC_REF(toggled)))
	op("repair", item(/obj/item/stack/material/steel), label("Repair with steel"),
		needs(req_bool(PROC_REF(damaged), because = MSG(emitter/whole)), req_bool(PROC_REF(enough_sheets), because = MSG(emitter/too_few_sheets))),
		says(MSG(emitter/repairing)), wait(3 SECONDS), then(PROC_REF(repaired)))
	op("anomalous", item(/obj/item/anomaly_scanner), label("Toggle anomalous mode"), wait(0), then(PROC_REF(anomalous_toggled)))
	op("particle", tool(TOOL_MULTITOOL), label("Select particle"), wait(0), when(nameof(anomalous)),
		asks(/datum/prompt/choice, fields = list("title" = "Particle Selection", "question" = "Select particle type", "choices" = ANOMALY_PARTICLE_ALL)),
		then(PROC_REF(particle_chosen)))

// ALLOW(init/INSTANCE_STATE): the rung a mapped emitter starts on is the one its sprite shows first
/obj/machinery/power/emitter/Initialize(mapload)
	. = ..()
	previous_state = state
	emp_protection_flags |= EMP_PROTECT_SELF

// admins are told an emitter was deleted.
/obj/machinery/power/emitter/on_destroy(force)
	message_admins("Emitter deleted at ([x],[y],[z] - <A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)")
	log_game("EMITTER([x],[y],[z]) Destroyed/deleted.")
	investigate_log(span_red("deleted") + " at ([x],[y],[z])","singulo")
	..()

// ---- conditions ----

/// On and whole: its step runs (it is on grid power, not APC power, so operable() does not fit).
/obj/machinery/power/emitter/proc/firing(datum/act/A)
	return active && !broken_now()

/obj/machinery/power/emitter/proc/is_welded(datum/act/A)
	return state == FLOOR_WELD_WELDED

/// The sheets a repair takes: one per 10 integrity missing.
/obj/machinery/power/emitter/proc/repair_sheets()
	return emitter_repair_sheets(src)

/// The sheets repairing `E` takes (integrity is the damage system's, read whole).
/proc/emitter_repair_sheets(obj/machinery/power/emitter/E)
	READS_FROM(E)
	return CEILING((E.max_integrity - E.get_integrity()) / 10, 1) // ALLOW(reads): an emitter's max_integrity is its type's constant

/// The stack in hand holds `n` (a stack's count is its own business, read whole).
/proc/emitter_stack_holds(obj/item/stack/S, n)
	READS_FROM(S)
	return istype(S) && S.get_amount() >= n

/obj/machinery/power/emitter/proc/damaged(datum/act/A)
	return emitter_repair_sheets(src) > 0

/obj/machinery/power/emitter/proc/enough_sheets(datum/act/op/A)
	return emitter_stack_holds(A.held, emitter_repair_sheets(src))

// ---- effects ----

/// The hand on the switch.
/obj/machinery/power/emitter/proc/toggled(datum/act/op/A)
	add_fingerprint(A.actor)
	activate(A.actor)
	return OP_OK

/// Switches it on or off (the hand, a remote emitter button). It must be welded and wired, and its controls unlocked.
/obj/machinery/power/emitter/proc/activate(mob/user as mob)
	if(state != FLOOR_WELD_WELDED)
		to_chat(user, span_warning("\The [src] needs to be firmly secured to the floor first."))
		return 1
	if(!power_region)
		to_chat(user, "\The [src] isn't connected to a wire.")
		return 1
	if(lock_locked(src))
		to_chat(user, span_warning("The controls are locked!"))
		return 1
	if(active == 1)
		set_active(0)
		balloon_alert_visible("turned off")
		message_admins("Emitter turned off by [key_name(user, user?.client)](<A href='byond://?_src_=holder;[HrefToken()];adminmoreinfo=\ref[user]'>?</A>) in ([x],[y],[z] - <A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)",0,1)
		log_game("EMITTER([x],[y],[z]) OFF by [key_name(user)]")
		investigate_log("turned " + span_red("off") + " by [user?.key]","singulo")
	else
		set_active(1)
		EXPIRY_STAMP(src, material_last_charge, CLOCK_WORLD)
		balloon_alert_visible("turned on")
		shot_number = 0
		fire_delay = get_initial_fire_delay()
		message_admins("Emitter turned on by [key_name(user, user?.client)](<A href='byond://?_src_=holder;[HrefToken()];adminmoreinfo=\ref[user]'>?</A>) in ([x],[y],[z] - <A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)")
		log_game("EMITTER([x],[y],[z]) ON by [key_name(user)]")
		investigate_log("turned " + span_green("on") + " by [user?.key]","singulo")
	changed(src)

/// The ladder moved: welded, it joins the cable network on its tile; loose or bolted, it leaves it. The sprite flicks between the rungs.
/obj/machinery/power/emitter/proc/rung_moved(datum/act/op/A)
	if(state == FLOOR_WELD_WELDED)
		connect_to_network()
	else
		disconnect_from_network()
	if(state != previous_state)
		flick("emitterflick-[previous_state][state]", src)
		previous_state = state

/// One step while it is on (every machine service interval): it must still be welded and wired; it charges, and fires when its shot is ready
/// and it holds the energy for it.
/obj/machinery/power/emitter/proc/emitter_step(datum/act/timer/A)
	if(state != FLOOR_WELD_WELDED || (!power_region && active_power_usage))
		set_active(0)
		return
	charge_emitter()
	if(!COOLDOWN_FINISHED(src, shot_cooldown) || active != 1)
		return
	var/burst_time = (min_burst_delay + max_burst_delay)/2 + 2*(burst_shots-1)
	var/desired_beam = active_power_usage * (burst_time / 10) / burst_shots * material_output_setting
	var/efficiency = emitter_efficiency()
	var/required_energy = desired_beam / efficiency
	if(material_stored_energy < required_energy)
		if(powered)
			powered = 0
			log_game("EMITTER([x],[y],[z]) Lost power and was ON.")
			investigate_log("lost power and turned" + span_red("off"),"singulo")
		return
	if(!powered)
		powered = 1
		log_game("EMITTER([x],[y],[z]) Regained power and is ON.")
		investigate_log("regained power and turned " + span_green("on"),"singulo")

	COOLDOWN_START(src, shot_cooldown, fire_delay)
	if(shot_number < burst_shots)
		fire_delay = get_burst_delay() //R-UST port
		shot_number++
	else
		fire_delay = get_rand_burst_delay() //R-UST port
		shot_number = 0

	fire_delay = max(1, round(fire_delay / material_cadence_setting))
	material_stored_energy -= required_energy
	material_beam_joules += desired_beam
	// An emitter with no material service (no functional construction to watch, as charge_emitter() allows) still fires; only the ledger waits.
	var/datum/material_service/service = material_service_of(src)
	if(service)
		service.output_joules += desired_beam
		service.loss_joules += required_energy - desired_beam
		service.last_output_watts = desired_beam / max(fire_delay / 10, 0.1)
		EXPIRY_STAMP(service, last_work_time, CLOCK_WORLD)
		service.add_heat(required_energy - desired_beam)

	play_sfx(src, SFX_WEAPONS_EMITTER)
	if(prob(35))
		fx_sparks(src, 5)

	var/obj/item/projectile/beam/emitter/beam = get_emitter_beam()
	beam.damage = round(desired_beam/EMITTER_DAMAGE_POWER_TRANSFER)
	rel_set(beam, nameof(beam.firer), src)
	beam.fire(dir2angle(dir))

/// Steel sheets repair it: one per 10 integrity missing.
/obj/machinery/power/emitter/proc/repaired(datum/act/op/A)
	var/obj/item/stack/material/sheets = A.held
	var/amount = repair_sheets()
	sheets.use(amount)
	to_chat(A.actor, span_notice("You have repaired \the [src]."))
	repair_damage(max_integrity)
	return OP_OK

/obj/machinery/power/emitter/proc/anomalous_toggled(datum/act/op/A)
	set_anomalous(!anomalous)
	burst_delay = anomalous ? 3 : 8
	to_chat(A.actor, span_notice("The beam is now set to [anomalous ? "anomalous." : "normal."]"))
	return OP_OK

/obj/machinery/power/emitter/proc/particle_chosen(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/chosen = R?.value
	if(!chosen || !(chosen in ANOMALY_PARTICLE_ALL))
		return OP_REFUSED
	particle = chosen
	balloon_alert_visible("changed to [chosen]")
	return OP_OK

/// The card shorts the lock open for good (the lock refuses an emagged holder).
/obj/machinery/power/emitter/proc/on_emag(datum/act/op/A)
	key_set(src, LOCK_LOCKED, FALSE)
	return OP_OK

/obj/machinery/power/emitter/atom_destruction(damage_flag)
	if(power_region && avail(active_power_usage))
		visible_message(src, span_danger("\The [src] explodes violently!"), span_danger("You hear an explosion!"))
		explosion(get_turf(src), 1, 2, 4)
	else
		visible_message(span_danger("\The [src] crumples apart!"), span_warning("You hear metal collapsing."))
	return ..()

/obj/machinery/power/emitter/examine(mob/user)
	. = ..()
	var/integrity_percentage = round((get_integrity() / max_integrity) * 100)
	switch(integrity_percentage)
		if(0 to 30)
			. += span_danger("It is close to falling apart!")
		if(31 to 70)
			. += span_danger("It is damaged.")
		if(77 to 99)
			. += span_warning("It is slightly damaged.")

//R-UST port
/obj/machinery/power/emitter/proc/get_initial_fire_delay()
	return initial_fire_delay

/obj/machinery/power/emitter/proc/get_rand_burst_delay()
	return rand(min_burst_delay, max_burst_delay)

/obj/machinery/power/emitter/proc/get_burst_delay()
	return burst_delay

/obj/machinery/power/emitter/proc/get_emitter_beam()
	if(anomalous)
		var/obj/item/projectile/energy/anomaly/projectile = new /obj/item/projectile/energy/anomaly(get_turf(src))
		projectile.particle_type = particle
		return projectile
	return new /obj/item/projectile/beam/emitter(get_turf(src))

/// Its beam shows while it is on, fed and on a live network.
/obj/machinery/power/emitter/proc/beam_shown()
	return powered && power_region && avail(active_power_usage) && active

/obj/machinery/power/emitter/draw(datum/look/look)
	..()
	emitter_look(look)

/// The emitter's own sprite: its rung, the beam while it fires, the lock while its controls are locked.
/obj/machinery/power/emitter/proc/emitter_look(datum/look/look)
	look.state("emitter[state]")
	if(beam_shown())
		var/image/emitterbeam = image(icon, "emitter-beam")
		emitterbeam.plane = PLANE_LIGHTING_ABOVE
		look.overlay(emitterbeam)
	if(lock_locked(src))
		var/image/emitterlock = image(icon, "emitter-lock")
		emitterlock.plane = PLANE_LIGHTING_ABOVE
		look.overlay(emitterlock)

/obj/machinery/power/emitter/pre_mapped
	anchored = TRUE
	state = FLOOR_WELD_WELDED

// The old emitter sprite
/obj/machinery/power/emitter/antique
	name = "antique emitter"
	desc = "An old fashioned heavy duty industrial laser."
	icon_state = "emitter"

/obj/machinery/power/emitter/antique/emitter_look(datum/look/look)
	look.state(beam_shown() ? "emitter_+a" : "emitter")

/obj/machinery/power/emitter/antique/pre_mapped
	anchored = TRUE
	state = FLOOR_WELD_WELDED

TRACKED_BRIDGED(/obj/machinery/power/emitter, state, CHANGE_MACHINE_SETTINGS)

/obj/machinery/power/emitter/floor_weld_state()
	return state

/obj/machinery/power/emitter/floor_weld_set_state(rung)
	return set_state(rung)
