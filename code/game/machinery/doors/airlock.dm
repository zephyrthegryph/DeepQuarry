//
/*
- Specific department maintenance doors
- Named doors properly according to type
- Gave them default access levels with the access constants
- Improper'd all of the names in the new()
*/

/obj/machinery/door/airlock
	name = "Airlock"
	icon = 'icons/obj/doors/doorint.dmi'
	icon_state = "door_closed"
	power_channel = ENVIRON

	explosion_resistance = 10

	// Doors do their own stuff

	blocks_emissive = EMISSIVE_BLOCK_GENERIC // Not quite as nice as /tg/'s custom masks. We should make those sometime

	var/aiControlDisabled = 0 //If 1, AI control is disabled until the AI hacks back in and disables the lock. If 2, the AI has bypassed the lock. If -1, the control is enabled but the AI had bypassed it earlier, so if it is disabled again the AI would have no trouble getting back in.
	var/hackProof = 0 // if 1, this door can't be hacked by the AI
	/// 0: not electrified. 1: electrified for a while (the keyed "electrified" timer reverts it). -1: until someone fixes it.
	var/electrified_until = 0
	/// 0: main power on. 1: lost for a while (the keyed "main_power" timer restores it). -1: lost until the cables are mended.
	var/main_power_lost_until = 0
	/// 0: backup power carrying the door. 1: out for a while (the keyed "backup_power" timer). -1: standing by, or cut.
	var/backup_power_lost_until = -1
	var/has_beeped = 0					//If 1, will not beep on failed closing attempt. Resets when door closes.
	var/lights = 1 // bolt lights show by default
	var/aiDisabledIdScanner = 0
	var/aiHacking = FALSE
	var/obj/machinery/door/airlock/closeOther
	var/closeOtherId = null
	var/lockdownbyai = 0
	autoclose = 1
	var/assembly_type = /obj/structure/door_assembly
	var/mineral = null
	/// A second between shocks from bumping it.
	COOLDOWN_DECLARE(bump_zap_cooldown)
	var/safe = 1
	normalspeed = 1
	silicon_use = SILICON_USE_UI
	var/obj/item/airlock_electronics/electronics = null
	COOLDOWN_DECLARE(hasShocked) //Prevents multiple shocks from happening
	var/secured_wires = 0
	var/security_level = 1 //Acts as a multiplier on the time required to hack an airlock with a hacktool

	var/open_sound_powered = 'sound/machines/door/covert1o.ogg'
	var/open_sound_unpowered = 'sound/machines/door/airlockforced.ogg'
	var/close_sound_powered = 'sound/machines/door/covert1c.ogg'
	var/legacy_open_powered = 'sound/machines/door/old_airlock.ogg'
	var/legacy_close_powered = 'sound/machines/door/old_airlockclose.ogg'
	var/department_open_powered = null
	var/department_close_powered = null
	var/denied_sound = SFX_MACHINES_DENIEDBEEP
	var/bolt_up_sound = SFX_MACHINES_DOOR_BOLTSUP
	var/bolt_down_sound = SFX_MACHINES_DOOR_BOLTSDOWN
	var/knock_sound = SFX_MACHINES_2BEEPLOW
	var/knock_hammer_sound = SFX_WEAPONS_SONIC_JACKHAMMER
	var/knock_unpowered_sound = SFX_MACHINES_DOOR_KNOCK_GLASS
	var/mob/hold_open
	/// A map says an airlock starts bolted or welded shut with these.
	var/bolted_at_start = FALSE
	var/welded_at_start = FALSE
	rad_insulation = RAD_MEDIUM_INSULATION
	rad_shield_material = MAT_STEEL
	rad_shield_thickness_mm = RAD_AIRLOCK_THICKNESS_MM

	// Frozen airlocks and how to deice them
	var/frozen = FALSE
	var/next_weather_check = 0
	var/static/list/deicing_tools = list(
		/obj/item/ice_pick = 3,
		/obj/item/tool/crowbar = 5,
		/obj/item/pen = 30,
		/obj/item/card = 35,
		/obj/item/tool = 10,
		/obj/item = 12,
	)

/// A simple mob that smashes an airlock which has lost its power: through bolts or a weld it breaks into the internals (an op, so it takes its time),
/// otherwise it forces the door open or shut at once. A door that works takes the smash as damage.
/obj/machinery/door/airlock/attack_generic(mob/living/user, damage)
	if(!operable())
		if(damage >= STRUCTURE_MIN_DAMAGE_THRESHOLD)
			if(bolts_bolted(src) || weld_shut_welded(src))
				act_message(user, src, others = span_danger("%U% begins breaking into %T% internals!"))
				perform_op(user, src, "break_in", origin = ORIGIN_SYSTEM)
			else if(density)
				act_message(user, src, others = span_danger("%U% forces %T% open!"))
				open(TRUE)
			else
				act_message(user, src, others = span_danger("%U% forces %T% closed!"))
				close(1)
		else
			act_message(user, src, others = span_notice("%U% strains fruitlessly to force %T% [density ? "open" : "closed"]."))
		return
	..()

/obj/machinery/door/airlock/proc/break_in_done(datum/act/op/A)
	unbolt_unweld()
	open(TRUE)
	if(prob(25))
		shock(A.actor, 100)
	return OP_OK

/// The bolts come up and the weld lets go, with no mechanism and no noise (a spirit, a claw, a break-in).
/obj/machinery/door/airlock/proc/unbolt_unweld()
	cap_key_set(src, BOLTS_BOLTED, FALSE, null)
	set_welded(src, FALSE)

/obj/machinery/door/airlock/proc/attack_alien_timed_done(mob/user)
	act_message(user, src, others = span_danger("%U% tears %T% open, sparks flying from its electronics!"))
	do_animate("spark")
	play_sfx(src, SFX_MACHINES_DOOR_AIRLOCK_TEAR_APART, volume_channel = VOLUME_CHANNEL_DOORS)
	unbolt_unweld()
	open(TRUE)
	atom_break() //These aren't emags, these be CLAWS

/obj/machinery/door/airlock/proc/attack_alien_timed_done2(mob/user)
	play_sfx(src, SFX_MACHINES_DOOR_AIRLOCK_CREAKING, volume_channel = VOLUME_CHANNEL_DOORS)
	act_message(user, src, others = span_danger("%U% forces %T% open!"))
	open(TRUE)

/obj/machinery/door/airlock/get_material()
	if(mineral)
		return get_material_by_name(mineral)
	return get_material_by_name(MAT_STEEL)

// Power loss and electrification restore themselves on their own keyed timers; the autoclose timer only keeps autoclose. An open door that
// cannot close drops it.
/obj/machinery/door/airlock/autoclose_due()
	if(!density && !operating && (bolts_bolted(src) || weld_shut_welded(src) || !arePowerSystemsOn() || wire_cut(WIRE_OPEN_DOOR)))
		return
	return ..()

/// Raises CHANGE_MACHINE_MODE for whatever watches this door (bolts, power, electrification).
/obj/machinery/door/airlock/proc/publish_door_mode()
	changed(src, CHANGE_MACHINE_MODE)

// Runs on its own every(), because making every airlock process every tick just to check for unfreezing is a bad idea. Only the airlocks that can
// freeze (can_freeze()) declare it (airlock_subtypes.dm).

/obj/machinery/door/airlock/proc/check_for_freeze(datum/act/A)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	// We don't freeze so none of this matters
	if(!can_freeze())
		return

	// If we are not on a planet don't bother checking again. We physically cannot be outdoors. Except shuttles...
	var/area/our_area = get_area(src)
	var/turf/our_turf = get_turf(src)
	if(!our_turf || (!istype(our_area, /area/shuttle) && (our_turf.z > length(SSplanets.z_to_planet) || !SSplanets.z_to_planet[our_turf.z])))
		return

	// Don't do anything if we are changing states
	if(!operating)
		// Door must be facing the outdoors and the temp of the air must be low enough
		var/planet_temp = T20C
		for(var/check_dir in GLOB.cardinal)
			var/turf/ground = get_step(our_turf, check_dir)
			if(ground.density || !ground.is_outdoors() || isspace(ground))
				continue
			var/datum/gas_mixture/gas_mix = ground.return_air()
			if(gas_mix.return_temperature() < planet_temp)
				planet_temp = gas_mix.return_temperature()

		// Check if we're in freezing weather, if above 0 start melting instead
		if(planet_temp < (T0C - 15))
			if(!frozen && density && prob(planet_temp < (T0C - 25) ? 20 : 5)) // Higher chance of freezing if temp is super low
				freeze()
		// Above 0 to have any chance at unfreezing
		else if(planet_temp > T0C)
			if(frozen && prob(20))
				unFreeze()

/*
About the new airlock wires panel:
*	An airlock wire dialog can be accessed by the normal way or by using wirecutters or a multitool on the door while the wire-panel is open. This would show the following wires, which you can either wirecut/mend or send a multitool pulse through. There are 9 wires.
*		one wire from the ID scanner. Sending a pulse through this flashes the red light on the door (if the door has power). If you cut this wire, the door will stop recognizing valid IDs. (If the door has 0000 access, it still opens and closes, though)
*		two wires for power. Sending a pulse through either one causes a breaker to trip, disabling the door for 10 seconds if backup power is connected, or 1 minute if not (or until backup power comes back on, whichever is shorter). Cutting either one disables the main door power, but unless backup power is also cut, the backup power re-powers the door in 10 seconds. While unpowered, the door may be open, but bolts-raising will not work. Cutting these wires may electrocute the user.
*		one wire for door bolts. Sending a pulse through this drops door bolts (whether the door is powered or not) or raises them (if it is). Cutting this wire also drops the door bolts, and mending it does not raise them. If the wire is cut, trying to raise the door bolts will not work.
*		two wires for backup power. Sending a pulse through either one causes a breaker to trip, but this does not disable it unless main power is down too (in which case it is disabled for 1 minute or however long it takes main power to come back, whichever is shorter). Cutting either one disables the backup door power (allowing it to be crowbarred open, but disabling bolts-raising), but may electocute the user.
*		one wire for opening the door. Sending a pulse through this while the door has power makes it open the door if no access is required.
*		one wire for AI control. Sending a pulse through this blocks AI control for a second or so (which is enough to see the AI control light on the panel dialog go off and back on again). Cutting this prevents the AI from controlling the door unless it has hacked the door through the power connection (which takes about a minute). If both main and backup power are cut, as well as this wire, then the AI cannot operate or hack the door at all.
*		one wire for electrifying the door. Sending a pulse through this electrifies the door for 30 seconds. Cutting this wire electrifies the door, so that the next person to touch the door without insulated gloves gets electrocuted. (Currently it is also STAYING electrified until someone mends the wire)
*		one wire for controling door safetys.  When active, door does not close on someone.  When cut, door will ruin someone's shit.  When pulsed, door will immedately ruin someone's shit.
*		one wire for controlling door speed.  When active, dor closes at normal rate.  When cut, door does not close manually.  When pulsed, door attempts to close every tick.
*/

/obj/machinery/door/airlock/bumpopen(mob/living/user) //Airlocks now zap you when you 'bump' them open when they're electrified. --NeoFite
	if(!issilicon(user))
		if(isElectrified())
			if(COOLDOWN_FINISHED(src, bump_zap_cooldown))
				if(shock(user, 100))
					COOLDOWN_START(src, bump_zap_cooldown, 1 SECOND)
					return
			else
				return
		else if(user.status_units(EFFECT_HALLUCINATING) > 50 && prob(10) && operating == 0)
			to_chat(user, span_danger("You feel a powerful shock course through your body!"))
			user.playsound_local(get_turf(user), get_sfx(SFX_SPARKS), vol = 75)
			user.injure(INJURY_PAIN, 10, null, src)
			user.status_adjust(EFFECT_STUNNED, 10)
			return
	..(user)

/obj/machinery/door/airlock/proc/isElectrified()
	if(electrified_until != 0)
		return TRUE
	return FALSE

/obj/machinery/door/airlock/proc/canAIControl()
	return ((aiControlDisabled!=1) && (!isAllPowerLoss()));

/obj/machinery/door/airlock/proc/canAIHack()
	return ((aiControlDisabled==1) && (!hackProof) && (!isAllPowerLoss()));

/obj/machinery/door/airlock/proc/arePowerSystemsOn()
	if (!operable())
		return FALSE
	return (main_power_lost_until==0 || backup_power_lost_until==0)

/obj/machinery/door/airlock/requiresID()
	return !(wire_cut(WIRE_IDSCAN) || aiDisabledIdScanner)

/obj/machinery/door/airlock/proc/isAllPowerLoss()
	if(!operable())
		return TRUE
	if(mainPowerCablesCut() && backupPowerCablesCut())
		return TRUE
	return FALSE

/// Whether `wire` is cut. A door whose wires were never touched has none cut.
/// The wire set an airlock is built with: secure electronics make it a randomized one.
/obj/machinery/door/airlock/proc/wires_type()
	return secured_wires ? /datum/wire_set/airlock/secure : /datum/wire_set/airlock

/obj/machinery/door/airlock/proc/wire_cut(wire)
	return wire_is_cut(src, wire)

/obj/machinery/door/airlock/proc/mainPowerCablesCut()
	return wire_cut(WIRE_MAIN_POWER1) || wire_cut(WIRE_MAIN_POWER2)

/obj/machinery/door/airlock/proc/backupPowerCablesCut()
	return wire_cut(WIRE_BACKUP_POWER1) || wire_cut(WIRE_BACKUP_POWER2)

/// The main power state (0 on, 1 lost for a while, -1 lost until the cables are mended): restoring with a cut cable stays lost, and backup power
/// stands down once main power is back.
/obj/machinery/door/airlock/proc/main_power_to(value)
	if(!value && mainPowerCablesCut())
		value = -1
	if(main_power_lost_until == value)
		return FALSE
	set_main_power_lost_until(value)
	if(!value && !backup_power_lost_until)
		backup_power_to(-1)
	resume_autoclose_if_possible()
	publish_door_mode()
	return TRUE

/// The backup power state: restoring it carries the door only while main power is out; with a cut cable, or main power back, it stands by (-1).
/obj/machinery/door/airlock/proc/backup_power_to(value)
	if(!value && (backupPowerCablesCut() || !main_power_lost_until))
		value = -1
	if(backup_power_lost_until == value)
		return FALSE
	set_backup_power_lost_until(value)
	resume_autoclose_if_possible()
	publish_door_mode()
	return TRUE

/// The electrification state: a timed electrification that runs out on a door whose electrify wire is cut stays electrified.
/obj/machinery/door/airlock/proc/electrified_to(value)
	if(!value && wire_cut(WIRE_ELECTRIFY) && arePowerSystemsOn())
		value = -1
	if(electrified_until == value)
		return FALSE
	set_electrified_until(value)
	publish_door_mode()
	return TRUE

/// The three timers (world clock, keyed so a new one replaces the old): each gives its state back when it runs out.
/obj/machinery/door/airlock/proc/main_power_timer()
	main_power_to(0)

/obj/machinery/door/airlock/proc/backup_power_timer()
	backup_power_to(0)

/obj/machinery/door/airlock/proc/electrified_timer()
	electrified_to(0)

/obj/machinery/door/airlock/proc/loseMainPower()
	if(mainPowerCablesCut())
		cancel_after(src, "main_power")
		main_power_to(-1)
	else
		main_power_to(1)
		after(src, 1 MINUTE, PROC_REF(main_power_timer), key = "main_power", clock = CLOCK_WORLD)

	// If backup power is permanently disabled then activate in 10 seconds if possible, otherwise it's already enabled or a timer is already running
	if(backup_power_lost_until == -1 && !backupPowerCablesCut())
		backup_power_to(1)
		after(src, 10 SECONDS, PROC_REF(backup_power_timer), key = "backup_power", clock = CLOCK_WORLD)

	// Disable electricity if required
	if(electrified_until && isAllPowerLoss())
		electrify(0)

/obj/machinery/door/airlock/proc/loseBackupPower()
	if(backupPowerCablesCut())
		cancel_after(src, "backup_power")
		backup_power_to(-1)
	else
		backup_power_to(1)
		after(src, 1 MINUTE, PROC_REF(backup_power_timer), key = "backup_power", clock = CLOCK_WORLD)

	// Disable electricity if required
	if(electrified_until && isAllPowerLoss())
		electrify(0)

/obj/machinery/door/airlock/proc/regainMainPower()
	cancel_after(src, "main_power")
	main_power_to(0)

/obj/machinery/door/airlock/proc/regainBackupPower()
	cancel_after(src, "backup_power")
	backup_power_to(0)

/obj/machinery/door/airlock/proc/resume_autoclose_if_possible()
	if(autoclose && !density && !operating && !bolts_bolted(src) && !weld_shut_welded(src) && arePowerSystemsOn() && !wire_cut(WIRE_OPEN_DOOR))
		autoclose_in(next_close_wait())

/// Electrifies the door for `duration` seconds (-1: until fixed, 0: stops). feedback tells `user`.
/obj/machinery/door/airlock/proc/electrify(duration, feedback = FALSE, mob/user)
	var/message = ""
	var/mob/actor = user
	if(wire_cut(WIRE_ELECTRIFY) && arePowerSystemsOn())
		message = "The electrification wire is cut - Door permanently electrified."
		cancel_after(src, "electrified")
		electrified_to(-1)
	else if(duration && !arePowerSystemsOn())
		message = "The door is unpowered - Cannot electrify the door."
		cancel_after(src, "electrified")
		electrified_to(0)
	else if(!duration && electrified_until != 0)
		message = "The door is now un-electrified."
		cancel_after(src, "electrified")
		electrified_to(0)
	else if(duration)	//electrify door for the given duration seconds
		if(actor)
			LAZYADD(shockedby, "\[[time_stamp()]\] - [actor](ckey:[actor.ckey])")
			add_attack_logs(actor, src, "Electrified a door")
		else
			LAZYADD(shockedby, "\[[time_stamp()]\] - EMP)")
		message = "The door is now electrified [duration == -1 ? "permanently" : "for [duration] second\s"]."
		if(duration == -1)
			cancel_after(src, "electrified")
			electrified_to(-1)
		else
			electrified_to(1)
			after(src, duration SECONDS, PROC_REF(electrified_timer), key = "electrified", clock = CLOCK_WORLD)

	if(feedback && message && actor)
		to_chat(actor, message)

/obj/machinery/door/airlock/proc/set_idscan(activate, feedback = FALSE, mob/user)
	var/message = ""
	if(wire_cut(WIRE_IDSCAN))
		message = "The IdScan wire is cut - IdScan feature permanently disabled."
	else if(activate && aiDisabledIdScanner)
		set_aiDisabledIdScanner(0)
		message = "IdScan feature has been enabled."
	else if(!activate && !aiDisabledIdScanner)
		set_aiDisabledIdScanner(1)
		message = "IdScan feature has been disabled."

	if(feedback && message && user)
		to_chat(user, message)

/obj/machinery/door/airlock/proc/set_safeties(activate, feedback = FALSE, mob/user)
	var/message = ""
	// Safeties!  We don't need no stinking safeties!
	if (wire_cut(WIRE_SAFETY))
		message = "The safety wire is cut - Cannot enable safeties."
	else if (!activate && safe)
		set_safe(0)
	else if (activate && !safe)
		set_safe(1)

	if(feedback && message && user)
		to_chat(user, message)

// shock user with probability prb (if all connections & power are working)
// returns 1 if shocked, 0 otherwise
// The preceding comment was borrowed from the grille's shock script
/obj/machinery/door/airlock/shock(mob/user, prb)
	if(!arePowerSystemsOn())
		return FALSE
	if(!COOLDOWN_FINISHED(src, hasShocked))
		return FALSE	//Already shocked someone recently?
	if(..())
		COOLDOWN_START(src, hasShocked, 1 SECOND)
		return TRUE
	else
		return FALSE

// The door template the base door declares (door.dm) doesn't apply: draw() below is the look.
APPEARANCE_NONE(/obj/machinery/door/airlock)

/// Bridge while door.dm's other doors still draw through update_icon(): its shared procs (and the
/// declared appearance watch on stat and density) call update_icon(), which marks the airlock changed
/// so draw() runs.
// ALLOW(sys_update_icon): bridge only; it draws nothing, it marks the airlock so draw() runs
/obj/machinery/door/airlock/update_icon()
	changed(src)


// ---- state the declarations below read ----

TRACKED(/obj/machinery/door/airlock, main_power_lost_until)
TRACKED(/obj/machinery/door/airlock, backup_power_lost_until)
TRACKED(/obj/machinery/door/airlock, electrified_until)
TRACKED(/obj/machinery/door/airlock, aiControlDisabled)
TRACKED(/obj/machinery/door/airlock, aiDisabledIdScanner)
TRACKED(/obj/machinery/door/airlock, lights)
TRACKED(/obj/machinery/door/airlock, safe)
TRACKED(/obj/machinery/door/airlock, frozen)

MSG_DEF_SELF(airlock/panel_broken, "The panel is broken and cannot be closed.")
MSG_DEF_SELF(airlock/pry_welded, "It is welded shut.")
MSG_DEF_SELF(airlock/pry_bolted, "The airlock's bolts prevent it from being forced.")
MSG_DEF_SELF(airlock/pry_motors, "The airlock's motors resist your efforts to force it.")
MSG_DEF_SELF(airlock/not_for_you, "You cannot control this airlock.")
MSG_DEF(airlock/hammered, "You hammer on %T%!", "%U% hammers on %T%!")
MSG_DEF(airlock/holds_open, "You begin holding %T% open.", "%U% begins holding %T% open.")

// ---- what an airlock is, declared ----
//
// The door base (door.dm) brings machine_basics, doors() (touch opens and closes it by the door's own access), the emag and the plasteel and repair
// ops; the library brings the panel, the wires, the bolts, the weld, the emergency access. What is the airlock's own: a crowbar's pry and the removal
// of its electronics, a claw's tear, what a taped, signalling or cabled touch does, the ice, the hammer and the held-open door, the remote control
// window and a cyborg's use, and the shock an electrified door gives whoever touches it (an early effect of every touch).

CAPABILITIES(/obj/machinery/door/airlock)
	panel()
	wires(PROC_REF(wires_type), emp = FALSE, status_lines = PROC_REF(wire_lights))
	extend(/datum/act/touch_wires, instead(then(PROC_REF(wire_touch_shocks))))
	on_notice(/datum/notice/wire_cut, then(PROC_REF(wire_changed_look)))
	on_notice(/datum/notice/wire_pulsed, then(PROC_REF(wire_changed_look)))
	on_wire(WIRE_IDSCAN, cut = PROC_REF(idscan_wire_cut), pulse = PROC_REF(idscan_wire_pulsed))
	on_wire(WIRE_MAIN_POWER1, cut = PROC_REF(main_power_wire_cut), pulse = PROC_REF(main_power_wire_pulsed))
	on_wire(WIRE_MAIN_POWER2, cut = PROC_REF(main_power_wire_cut), pulse = PROC_REF(main_power_wire_pulsed))
	on_wire(WIRE_BACKUP_POWER1, cut = PROC_REF(backup_power_wire_cut), pulse = PROC_REF(backup_power_wire_pulsed))
	on_wire(WIRE_BACKUP_POWER2, cut = PROC_REF(backup_power_wire_cut), pulse = PROC_REF(backup_power_wire_pulsed))
	on_wire(WIRE_DOOR_BOLTS, cut = PROC_REF(bolt_wire_cut), pulse = PROC_REF(bolt_wire_pulsed))
	on_wire(WIRE_AI_CONTROL, cut = PROC_REF(ai_wire_cut), pulse = PROC_REF(ai_wire_pulsed))
	on_wire(WIRE_ELECTRIFY, cut = PROC_REF(shock_wire_cut), pulse = PROC_REF(shock_wire_pulsed))
	on_wire(WIRE_OPEN_DOOR, pulse = PROC_REF(open_wire_pulsed))
	on_wire(WIRE_SAFETY, cut = PROC_REF(safety_wire_cut), pulse = PROC_REF(safety_wire_pulsed))
	on_wire(WIRE_SPEED, cut = PROC_REF(speed_wire_cut), pulse = PROC_REF(speed_wire_pulsed))
	on_wire(WIRE_BOLT_LIGHT, cut = PROC_REF(bolt_light_wire_cut), pulse = PROC_REF(bolt_light_wire_pulsed))
	bolts(starts = nameof(bolted_at_start))
	weld_shut(offered = PROC_REF(weld_offered), starts = nameof(welded_at_start))
	door_emergency()
	owns_one(nameof(electronics), /obj/item/airlock_electronics)
	interface("AiAirlock")
	op("pry", tool(TOOL_CROWBAR), stance(I_HELP, I_DISARM, I_GRAB), wait(0),
		needs(req(PROC_REF(pry_free), because = PROC_REF(pry_reason))), then(PROC_REF(pry_forced)))
	op("remove_electronics", tool(TOOL_CROWBAR), label("Remove electronics"), when(PROC_REF(can_remove_electronics)), priority(above("pry")),
		wait(4 SECONDS), then(PROC_REF(crowbar_act_tool_done)))
	op("wires_window", hand(), at(SPACE_PANEL), priority(OP_PRIORITY_PART), wait(0),
		needs(req(PROC_REF(hand_ok), because = PROC_REF(hand_refusal))), then(PROC_REF(show_wires)))
	op("tear", hand(), label("Tear"), when(req(PROC_REF(claws_tear))), priority(OP_PRIORITY_TAKE_OUT), wait(PROC_REF(tear_wait)),
		needs(req(PROC_REF(hand_ok), because = PROC_REF(hand_refusal))), then(PROC_REF(tear_done)))
	op("tape", item(/obj/item/taperoll), priority(OP_PRIORITY_PART), wait(0), then(PROC_REF(touched_by_held)))
	op("signaler", item(/obj/item/assembly/signaler), priority(OP_PRIORITY_PART), wait(0), then(PROC_REF(signaler_touch)))
	op("pai_cable", item(/obj/item/pai_cable), priority(OP_PRIORITY_PART), wait(0), then(PROC_REF(pai_cable_plugin)))
	op("pry_weapon", item(/obj/item), when(req(PROC_REF(prying_weapon))), priority(OP_PRIORITY_PART), wait(0), then(PROC_REF(pry_weapon_forced)))
	op("hammer", menu(), stance(I_HURT), label("Hammer on the door"), wait(0), then(PROC_REF(hammer_on_door)))
	op("hold_open", menu(), stance(I_GRAB), label("Hold the door open"), wait(0), then(PROC_REF(hold_door_open)))
	op("break_in", ai(), wait(10 SECONDS), then(PROC_REF(break_in_done)))
	op("deice", item(/obj/item), label("Clear the ice"), when(frozen), priority(OP_PRIORITY_SUBVERT), wait(PROC_REF(deice_wait)), then(PROC_REF(deice_done)))
	op("deice_tool", any_of_tools(TOOL_CROWBAR, TOOL_SCREWDRIVER, TOOL_WIRECUTTER, TOOL_MULTITOOL, TOOL_WELDER), label("Clear the ice"), when(frozen),
		priority(OP_PRIORITY_SUBVERT + 1), wait(PROC_REF(deice_wait)), then(PROC_REF(deice_done)))
	extend("panel.open", wait(0), needs(req(PROC_REF(panel_closable), because = MSG(airlock/panel_broken))), then(PROC_REF(panel_toggled)), then(PROC_REF(shock_toucher), early = TRUE))
	extend("weld_shut.toggle", priority(above("repair")), when(cond_any(cond_not(PROC_REF(damaged)), cond_not(req_stance(I_HELP)))), then(PROC_REF(shock_toucher), early = TRUE))
	extend(list("doors.open", "doors.close"), then(PROC_REF(shock_toucher), early = TRUE), then(PROC_REF(hold_release_touch), early = TRUE), then(PROC_REF(touched_early), early = TRUE))
	extend(list("wires.pulse", "wires.cut", "pry", "remove_electronics", "wires_window", "tear", "tape", "signaler", "pai_cable", "pry_weapon",
		"strike", "reinforce", "weld_plasteel", "unreinforce", "repair", "emag.use", "hold_open"), then(PROC_REF(shock_toucher), early = TRUE))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(airlock_emp)))
	every(1 SECOND, then(PROC_REF(command_step)), when = nameof(cur_command))

	section(controls, "The buttons of the remote control window (an AI's, a cyborg's, a ghost's): each answers a silicon or a ghost the door lets in")
	op("disrupt_main", ui_act("disrupt-main"), then(PROC_REF(ui_disrupt_main)))
	op("disrupt_backup", ui_act("disrupt-backup"), then(PROC_REF(ui_disrupt_backup)))
	op("shock_restore", ui_act("shock-restore"), then(PROC_REF(ui_shock_restore)))
	op("shock_temp", ui_act("shock-temp"), then(PROC_REF(ui_shock_temp)), logs(LOG_GAME))
	op("shock_perm", ui_act("shock-perm"), then(PROC_REF(ui_shock_perm)), logs(LOG_GAME))
	op("idscan_toggle", ui_act("idscan-toggle"), then(PROC_REF(ui_idscan_toggle)))
	op("emergency_toggle", ui_act("emergency-toggle"), then(PROC_REF(ui_emergency_toggle)), logs(LOG_GAME))
	op("bolt_toggle", ui_act("bolt-toggle"), then(PROC_REF(ui_bolt_toggle)), logs(LOG_GAME))
	op("light_toggle", ui_act("light-toggle"), then(PROC_REF(ui_light_toggle)))
	op("safe_toggle", ui_act("safe-toggle"), then(PROC_REF(ui_safe_toggle)))
	op("speed_toggle", ui_act("speed-toggle"), then(PROC_REF(ui_speed_toggle)))
	op("open_close", ui_act("open-close"), then(PROC_REF(ui_open_close)))
	extend(TAG_UI, needs(req(PROC_REF(ui_user_allowed), because = MSG(airlock/not_for_you))))
	extend("ui_open", inputs(remote())) // silicons only: remote() replaces the hand binding

	section(remote_gestures, "A silicon's gestures on the door, over its link: shift opens or closes it, ctrl bolts it, alt electrifies it, middle switches the bolt lights")
	op("remote_open", remote(), gesture(GESTURE_SHIFT), label("Open or close"), then(PROC_REF(ui_open_close)))
	op("remote_bolts", remote(), gesture(GESTURE_CTRL), label("Toggle the bolts"), then(PROC_REF(ui_bolt_toggle)), logs(LOG_GAME))
	op("remote_shock", remote(), gesture(GESTURE_ALT), label("Toggle electrification"), then(PROC_REF(remote_shock_toggle)), logs(LOG_GAME))
	// a cyborg's middle-click cycles its modules: the lights are the AI's
	op("remote_lights", remote(), gesture(GESTURE_MIDDLE), when(req(/mob/living/silicon/ai, of = ON_ACTOR)), label("Toggle the bolt lights"), then(PROC_REF(ui_light_toggle)))
	extend(list("remote_open", "remote_bolts", "remote_shock", "remote_lights"), needs(req(PROC_REF(ui_user_allowed), because = MSG(airlock/not_for_you))))

/obj/machinery/door/airlock/draw(datum/look/look)
	..()
	// doorint.dmi and its kin have no wires, broken or dark states: the sparks below show damage. The bolts show as
	// door_locked (below) and emergency access has no sprite of its own.
	look.hide(LOOK_WIRES)
	look.hide(LOOK_BROKEN)
	look.hide(LOOK_DARK)
	look.hide(LOOK_BOLTS)
	look.hide(LOOK_EMERGENCY)
	var/powered = !has_stat(NOPOWER)
	var/damaged = get_integrity() < max_integrity * 3/4
	if(density)
		look.state((bolts_bolted(src) && lights && arePowerSystemsOn()) ? "door_locked" : "door_closed")
		if(panel_open(src) || weld_shut_welded(src))
			if(powered)
				if(has_stat(BROKEN))
					look.overlay("sparks_broken")
				else if(damaged)
					look.overlay("sparks_damaged")
		else if(damaged && powered)
			look.overlay("sparks_damaged")
	else
		look.hide(LOOK_PANEL_OPEN)
		look.hide("welded")
		look.state(open_state())
		look.overlay("sparks_open", when = has_stat(BROKEN) && powered)
	look.overlay("snowairlock", when = frozen, icon = 'icons/turf/overlays.dmi')

/// The icon_state of the open door (a subtype shows its bolts on an open door).
/obj/machinery/door/airlock/proc/open_state()
	return "door_open"

/obj/machinery/door/airlock/do_animate(animation)
	switch(animation)
		if("opening")
			flick(panel_open(src) ? "o_door_opening" : "door_opening", src)
		if("closing")
			flick(panel_open(src) ? "o_door_closing" : "door_closing", src)
		if("spark")
			if(density)
				flick("door_spark", src)
		if("deny")
			if(density && arePowerSystemsOn())
				flick("door_deny", src)
				playsound(src, denied_sound, 50, 0, 3)
	return

/obj/machinery/door/airlock/CanPass(atom/movable/mover, turf/target)
	if (isElectrified())
		if (istype(mover, /obj/item))
			var/obj/item/i = mover
			var/list/item_matter = i.material_totals()
			if (item_matter && (MAT_STEEL in item_matter) && item_matter[MAT_STEEL] > 0)
				fx_sparks(src, 5)
	. = ..()


// ---- the touch ----


/// An electrified door shocks whoever touches it before the touch does anything: silicons are spared, a bare hand takes the full shock and a held
/// thing a smaller one. The shock ends the touch.
/obj/machinery/door/airlock/proc/shock_toucher(datum/act/op/A)
	var/mob/user = A.actor
	if(!user || issilicon(user) || !isElectrified())
		return OP_OK
	if(shock(user, A.held ? 75 : 100))
		return OP_REFUSED
	return OP_OK

/// A door someone holds open lets go when they move away from it or touch it again (a bare hand only).
/obj/machinery/door/airlock/proc/hold_release_touch(datum/act/op/A)
	if(A.held || !A.actor)
		return OP_OK
	hold_release(A.actor)
	return OP_OK

/obj/machinery/door/airlock/proc/hold_release(mob/user)
	if(!Adjacent(hold_open()))
		rel_clear(src, nameof(hold_open))
	if(hold_open() && !density)
		if(hold_open() == user)
			rel_clear(src, nameof(hold_open))
		else
			to_chat(user, span_warning("[hold_open()] is holding \the [src] open!"))

/// Anything held against the airlock touches it first (a phoron door ignites at a hot one).
/obj/machinery/door/airlock/proc/touched_early(datum/act/op/A)
	if(A.held && A.actor)
		touched_with(A.actor, A.held)
	return OP_OK

/obj/machinery/door/airlock/proc/show_wires(datum/act/op/A)
	wires_open(src, A.actor)
	return OP_OK

/// A xeno's claws are on the hand.
/obj/machinery/door/airlock/proc/claws_tear(datum/act/op/A)
	var/mob/living/carbon/human/X = A.actor
	return !A.held && istype(X) && istype(X.species, /datum/species/xenos) // ALLOW(reads): a body's species is fixed for the touch's life; the click re-evaluates it

/// How long the tear takes: internals behind bolts or a weld, forcing a shut door, nothing for an open one (it is pushed shut).
/obj/machinery/door/airlock/proc/tear_wait(datum/act/A)
	if(bolts_bolted(src) || weld_shut_welded(src))
		return 15 SECONDS
	if(density)
		return 5 SECONDS
	return 0

/obj/machinery/door/airlock/proc/tear_done(datum/act/op/A)
	var/mob/user = A.actor
	if(bolts_bolted(src) || weld_shut_welded(src))
		act_message(user, src, others = span_alium("%U% begins tearing into %T% internals!"))
		do_animate("deny")
		attack_alien_timed_done(user)
	else if(density)
		act_message(user, src, others = span_alium("%U% begins forcing %T% open!"))
		attack_alien_timed_done2(user)
	else
		act_message(user, src, others = span_danger("%U% forces %T% closed!"))
		close(1)
	return OP_OK

/obj/machinery/door/airlock/proc/touched_by_held(datum/act/op/A)
	touched_early(A)
	return OP_OK

/// A signaler touching the door touches it like a hand.
/obj/machinery/door/airlock/proc/signaler_touch(datum/act/op/A)
	touched_early(A)
	toggle_by(A.actor)
	return OP_OK

/// A hand's use of the door: it opens for whoever may, and shuts again.
/obj/machinery/door/airlock/proc/toggle_by(mob/user)
	add_fingerprint(user)
	if(operating || isrobot(user))
		return FALSE
	if(allowed(user) && operable())
		if(density)
			open()
		else
			close()
		return TRUE
	if(density)
		do_animate("deny")
	return FALSE

/obj/machinery/door/airlock/proc/pai_cable_plugin(datum/act/op/A)
	touched_early(A)
	var/obj/item/pai_cable/cable = A.held
	cable.plugin(src, A.actor)
	return OP_OK

/// A prying weapon that is no crowbar: it forces an unpowered door.
/obj/machinery/door/airlock/proc/prying_weapon(datum/act/op/A)
	var/obj/item/held = A.held
	return istype(held) && held.pry && !held.has_tool_quality(TOOL_CROWBAR) && !arePowerSystemsOn() // ALLOW(reads): an item's pry is fixed for its life

/obj/machinery/door/airlock/proc/pry_weapon_forced(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	touched_early(A)
	if(bolts_bolted(src))
		to_chat(user, span_notice("The airlock's bolts prevent it from being forced."))
		return OP_OK
	if(!weld_shut_welded(src) && !operating)
		if(istype(held, /obj/item/material/twohanded/fireaxe))
			var/obj/item/material/twohanded/fireaxe/F = held
			if(!F.wielded)
				to_chat(user, span_warning("You need to be wielding \the [F] to do that."))
				return OP_OK
		if(density)
			open(TRUE)
		else
			close(1)
	return OP_OK

/// A crowbar's force on a door that has lost its power and its bolts.
/obj/machinery/door/airlock/proc/pry_free(datum/act/A)
	return isnull(pry_blocked())

/obj/machinery/door/airlock/proc/pry_reason(datum/act/A)
	return pry_blocked()

/// Why a crowbar cannot force the door now (a message), or null.
/obj/machinery/door/airlock/proc/pry_blocked()
	if(arePowerSystemsOn())
		return /datum/msg/airlock/pry_motors
	if(bolts_bolted(src))
		return /datum/msg/airlock/pry_bolted
	return null

/obj/machinery/door/airlock/proc/pry_forced(datum/act/op/A)
	if(density)
		open(TRUE)
	else
		close(TRUE)
	return OP_OK

/obj/machinery/door/airlock/proc/panel_closable(datum/act/A)
	return !(panel_open(src) && has_stat(BROKEN))

/// The panel was moved: an open one shows its wires.
/obj/machinery/door/airlock/proc/panel_toggled(datum/act/op/A)
	if(panel_open(src))
		wires_open(src, A.actor)
	return OP_OK

/// Welding it shut is on offer for a closed, still door with no plasteel being fitted.
/obj/machinery/door/airlock/proc/weld_offered(datum/act/A)
	return density && operating <= 0 && !reinforcing

/obj/machinery/door/airlock/proc/damaged(datum/act/A)
	return get_integrity() < max_integrity // ALLOW(reads): a door's max_integrity is its type's constant


// ---- hammer and hold (ctrl-click) ----

/obj/machinery/door/airlock/proc/hammer_on_door(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, others = span_warning("%U% hammers on %T%!"), blind = span_warning("Someone hammers loudly on %T%!"))
	if(icon_state == "door_closed" && arePowerSystemsOn())
		flick("door_deny", src)
	playsound(src, knock_hammer_sound, 50, 0, 3)
	return OP_OK

/obj/machinery/door/airlock/proc/hold_door_open(datum/act/op/A)
	var/mob/user = A.actor
	rel_set(src, nameof(hold_open), user)
	act_message(user, src, others = span_info("%U% begins holding %T% open."), blind = span_info("Someone has started holding %T% open."))
	hold_release(user)
	toggle_by(user)
	return OP_OK

// ---- ice ----

/obj/machinery/door/airlock/proc/is_frozen()
	return frozen

/// How long clearing the ice takes with what is held: a lit welder or a hot thing melts it, a tool chips it, anything else is no use (a moment).
/obj/machinery/door/airlock/proc/deice_wait(datum/act/op/A)
	var/obj/item/held = A.held
	if(!held)
		return 0
	var/obj/item/weldingtool/welder = held.get_welder()
	if(welder)
		return welder.isOn() ? 5 SECONDS : 0
	if(held.is_hot())
		return 9 SECONDS
	if(istype(held, /obj/item/pen/crayon))
		return 0
	for(var/IT in deicing_tools)
		if(istype(held, IT))
			return deicing_tools[IT] SECONDS
	return 0

/obj/machinery/door/airlock/proc/deice_done(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	// A lit welder melts it.
	var/obj/item/weldingtool/welder = held.get_welder()
	if(welder)
		if(welder.remove_fuel(0, user) && welder.isOn())
			playsound(src, welder.usesound, 50, 1)
			to_chat(user, span_notice("You finish melting the ice off \the [src]"))
			unFreeze()
		return OP_OK
	// Melting with hot objects that don't take fuel
	if(held.is_hot())
		to_chat(user, span_notice("You finish melting the ice off \the [src]"))
		unFreeze()
		return OP_OK
	// This is just funny
	if(istype(held, /obj/item/pen/crayon))
		to_chat(user, span_notice("You try to use \the [held] to clear the ice, but it crumbles away!"))
		consume(held, user)
		return OP_OK
	// Check if we have something that can deice properly, and then use it's deice speed
	for(var/IT in deicing_tools)
		if(istype(held, IT))
			to_chat(user, span_notice("You finish chipping the ice off \the [src]"))
			unFreeze()
			return OP_OK
	//if we can't de-ice the door tell them what's wrong.
	to_chat(user, span_notice("\the [src] is frozen shut!"))
	return OP_OK

// ---- the remote control window ----

/// Who may work the door's remote controls: a link the door lets in (remote_link_allowed(), library/mob/silicon.dm) while its AI control works, or an
/// admin's ghost.
/obj/machinery/door/airlock/proc/ui_user_allowed(datum/act/op/A)
	if(remote_link_allowed(A))
		return canAIControl()
	var/mob/observer/dead/ghost = A.actor
	return istype(ghost) && ghost.can_admin_interact()

/// A silicon's alt-click: an electrified door goes dead, a dead one is electrified until released. The one who did it sees a mark on the door.
/obj/machinery/door/airlock/proc/remote_shock_toggle(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	electrify(electrified_until ? 0 : -1, TRUE, user)
	if(user?.client)
		var/turf/root_turf = get_turf(src)
		var/image/client_only/electrify_notice/zap = new('icons/hud/screen_gen.dmi', root_turf, electrified_until ? "stamina_crit" : "stamina_dead", OBFUSCATION_LAYER, SOUTH)
		zap.place_from_root(root_turf)
		zap.append_client(user.client)
	return OP_OK

/obj/machinery/door/airlock/proc/ui_disrupt_main(datum/act/op/A)
	if(main_power_lost_until)
		to_chat(A.actor, span_warning("Main power is already offline."))
		return OP_REFUSED
	loseMainPower()
	return OP_OK

/obj/machinery/door/airlock/proc/ui_disrupt_backup(datum/act/op/A)
	if(backup_power_lost_until)
		to_chat(A.actor, span_warning("Backup power is already offline."))
		return OP_REFUSED
	loseBackupPower()
	return OP_OK

/obj/machinery/door/airlock/proc/ui_shock_restore(datum/act/op/A)
	electrify(0, TRUE, A.actor)
	return OP_OK

/obj/machinery/door/airlock/proc/ui_shock_temp(datum/act/op/A)
	electrify(30, TRUE, A.actor)
	return OP_OK

/obj/machinery/door/airlock/proc/ui_shock_perm(datum/act/op/A)
	electrify(-1, TRUE, A.actor)
	return OP_OK

/obj/machinery/door/airlock/proc/ui_idscan_toggle(datum/act/op/A)
	set_idscan(aiDisabledIdScanner, TRUE, A.actor)
	return OP_OK

/obj/machinery/door/airlock/proc/ui_emergency_toggle(datum/act/op/A)
	set_emergency_access(src, !door_emergency_engaged(src))
	to_chat(A.actor, span_notice("Emergency access is now [door_emergency_engaged(src) ? "engaged" : "disengaged"]."))
	return OP_OK

/obj/machinery/door/airlock/proc/ui_bolt_toggle(datum/act/op/A)
	toggle_bolt(A.actor)
	return OP_OK

/obj/machinery/door/airlock/proc/ui_light_toggle(datum/act/op/A)
	if(wire_cut(WIRE_BOLT_LIGHT))
		to_chat(A.actor, span_warning("The bolt lights wire is cut - The door bolt lights are permanently disabled."))
		return OP_REFUSED
	set_lights(!lights)
	return OP_OK

/obj/machinery/door/airlock/proc/ui_safe_toggle(datum/act/op/A)
	set_safeties(!safe, TRUE, A.actor)
	return OP_OK

/obj/machinery/door/airlock/proc/ui_speed_toggle(datum/act/op/A)
	if(wire_cut(WIRE_SPEED))
		to_chat(A.actor, span_warning("The timing wire is cut - Cannot alter timing."))
		return OP_REFUSED
	normalspeed = !normalspeed
	return OP_OK

/obj/machinery/door/airlock/proc/ui_open_close(datum/act/op/A)
	user_toggle_open(A.actor)
	return OP_OK

/// The window's data: the power, the wires, and the state each part of the door keeps.
/obj/machinery/door/airlock/ui_data(datum/act/eval/A)
	var/list/data = list()
	var/list/power = list()
	power["main"] = main_power_lost_until > 0 ? 0 : 2
	power["main_timeleft"] = main_power_lost_until > 0 ? round(after_left(src, "main_power") / 10, 1) : main_power_lost_until
	power["backup"] = backup_power_lost_until > 0 ? 0 : 2
	power["backup_timeleft"] = backup_power_lost_until > 0 ? round(after_left(src, "backup_power") / 10, 1) : backup_power_lost_until
	data["power"] = power
	data["id_scanner"] = !aiDisabledIdScanner
	data["lights"] = lights
	data["opened"] = !density
	var/list/wire = list()
	wire["main_1"] = !wire_cut(WIRE_MAIN_POWER1)
	wire["main_2"] = !wire_cut(WIRE_MAIN_POWER2)
	wire["backup_1"] = !wire_cut(WIRE_BACKUP_POWER1)
	wire["backup_2"] = !wire_cut(WIRE_BACKUP_POWER2)
	wire["shock"] = !wire_cut(WIRE_ELECTRIFY)
	wire["id_scanner"] = !wire_cut(WIRE_IDSCAN)
	wire["bolts"] = !wire_cut(WIRE_DOOR_BOLTS)
	wire["lights"] = !wire_cut(WIRE_BOLT_LIGHT)
	wire["safe"] = !wire_cut(WIRE_SAFETY)
	wire["timing"] = !wire_cut(WIRE_SPEED)
	data["wires"] = wire
	data["bolted"] = bolts_bolted(src)
	data["electrified"] = isElectrified()
	data["electrified_left"] = electrified_until > 0 ? round(after_left(src, "electrified") / 10, 1) : electrified_until
	data["welded"] = weld_shut_welded(src)
	data["emergency"] = door_emergency_engaged(src)
	data["safe"] = !!safe
	data["speed"] = normalspeed
	return data

// ---- a cyborg's click, a simple mob's smash ----

/obj/machinery/door/airlock/proc/airlock_emp(datum/act/A)
	var/datum/notice/hit/emp/N = A
	var/severity = max(N.packet?.severity, 1)
	if(prob(40 / severity))
		var/seconds = 30 / severity
		if(electrified_until != -1 && after_left(src, "electrified") < seconds SECONDS)
			electrify(seconds)

/// What a closing door crushes: everything standing in its tiles that takes the crush (airlock_crush()), for `amount` (the stock crush when null); the
/// door takes the same damage once per crushed thing.
/obj/machinery/door/airlock/proc/crush_contents(amount)
	var/dealt = isnull(amount) ? DOOR_CRUSH_DAMAGE : amount
	for(var/turf/T in locs)
		for(var/atom/movable/AM in contents_of(T))
			if(AM.airlock_crush(dealt))
				take_damage(dealt, BRUTE, MELEE)

/// An item touched the airlock (before anything else it does). Subtypes react (phoron ignites).
/obj/machinery/door/airlock/proc/touched_with(mob/user, obj/item/held)
	return

/obj/machinery/door/airlock/click_ctrl(mob/user) //Hold door open
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(user.is_incorporeal())
		return CLICK_ACTION_BLOCKING

	if(!Adjacent(user))
		return CLICK_ACTION_BLOCKING

	// Combat mode hammers on the door; Grab holds it open.
	// The ops say which stance they mean: hammering is the combat stance's, holding the door open the grab stance's.
	for(var/key in list("hammer", "hold_open"))
		var/datum/op_result/result = perform_op(user, src, key, origin = ORIGIN_MENU)
		if(result?.outcome == ACT_COMMITTED)
			return CLICK_ACTION_SUCCESS

	if(arePowerSystemsOn())
		if(isElectrified())
			act_message(user, src, others = span_warning("%U% presses the door bell on %T%, making it violently spark!"), blind = span_warning("%T% sparks!"))
			add_fingerprint(user)
			fx_sparks(src, 5)
		else
			act_message(user, src, others = span_info("%U% presses the door bell on %T%."), blind = span_info("%T%'s bell rings."))
			add_fingerprint(user)
		if(icon_state == "door_closed")
			flick("door_deny", src)
		playsound(src, knock_sound, 50, 0, 3)
		return CLICK_ACTION_SUCCESS

	act_message(user, src, others = span_info("%U% knocks on %T%."), blind = span_info("Someone knocks on %T%."))
	add_fingerprint(user)
	playsound(src, knock_unpowered_sound, 50, 0, 3)
	return CLICK_ACTION_SUCCESS

/obj/machinery/door/airlock/proc/crowbar_act_tool_done(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You removed the airlock electronics!"))

	var/obj/structure/door_assembly/da = new assembly_type(get_turf(src))
	if (istype(da, /obj/structure/door_assembly/multi_tile))
		da.set_dir(dir)
	da.set_anchored(TRUE)
	if(mineral)
		da.set_glass(mineral)
	else if(glass && !da.glass)
		da.set_glass(1)
	graph_place(da, STAGE_DOOR_ASSEMBLY_WIRED)
	da.created_name = name
	da.update_state()

	if(operating == -1 || (has_stat(BROKEN)))
		new /obj/item/circuitboard/broken(get_turf(src))
		set_operating(0)
	else
		if (!electronics) create_electronics()

		electronics.forceMove(get_turf(src))
		own_take(src, nameof(electronics))
	replace_with(src, da)

/obj/machinery/door/airlock/proc/can_remove_electronics(datum/act/A)
	return !frozen && panel_open(src) && (operating < 0 || (!operating && weld_shut_welded(src) && !arePowerSystemsOn() && density && (!bolts_bolted(src) || (has_stat(BROKEN)))))

// ---- the remote control window (interface(), the ops with a ui_act() binding above) ----

/// The bolts, raised or dropped from the remote controls (the op that calls it has asked ui_user_allowed()).
/obj/machinery/door/airlock/proc/toggle_bolt(mob/user)
	add_fingerprint(user)
	if(wire_cut(WIRE_DOOR_BOLTS))
		to_chat(user, span_warning("The door bolt drop wire is cut - you can't toggle the door bolts."))
		return
	if(bolts_bolted(src))
		if(!arePowerSystemsOn())
			to_chat(user, span_warning("The door has no power - you can't raise the door bolts."))
		else
			unlock()
			to_chat(user, span_notice("The door bolts have been raised."))
	else
		lock()
		to_chat(user, span_warning("The door bolts have been dropped."))

/// The door opened or closed from the remote controls (the op that calls it has asked ui_user_allowed()).
/obj/machinery/door/airlock/proc/user_toggle_open(mob/user)
	add_fingerprint(user)
	if(frozen)
		to_chat(user, span_warning("The airlock is frozen shut!"))
	else if(weld_shut_welded(src))
		to_chat(user, span_warning("The airlock has been welded shut!"))
	else if(bolts_bolted(src))
		to_chat(user, span_warning("The door bolts are down!"))
	else if(!density)
		if(hold_open())
			if(hold_open() == user)
				rel_clear(src, nameof(hold_open))
				close()
			else
				to_chat(user, span_warning("[hold_open()] is holding \the [src] open!"))
				return
		close()
	else
		open()

/obj/machinery/door/airlock/on_broken()
	cap_key_set(src, PANEL_OPEN, TRUE, null)
	if (secured_wires)
		lock()
	for (var/mob/O in viewers(src, null))
		if ((O.client && !( O.blinded )))
			O.show_message("[name]'s control panel bursts open, sparks spewing out!")

	fx_sparks(src, 5)
	return

/obj/machinery/door/airlock/open(forced=0)
	if(!can_open(forced))
		return FALSE
	if(frozen && !forced) //Frozen airlocks can't open.
		return FALSE
	if(frozen && forced)
		unFreeze()

	use_power(360)	//360 W seems much more appropriate for an actuator moving an industrial door capable of crushing people

	if(hold_open())
		visible_message("[hold_open()] holds \the [src] open.")

	//if the door is unpowered then it doesn't make sense to hear the woosh of a pneumatic actuator
	for(var/mob/M as anything in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(!M || !M.client)
			continue
		var/old_sounds = M.read_preference(/datum/preference/toggle/old_door_sounds)
		var/department_door_sounds = M.read_preference(/datum/preference/toggle/department_door_sounds)
		var/sound
		var/volume
		if(old_sounds) // Do we have old sounds enabled? Play these even if we have department door sounds enabled.
			if(arePowerSystemsOn())
				sound = legacy_open_powered
				volume = 50
			else
				sound = open_sound_unpowered
				volume = 75
		else if(!old_sounds && department_door_sounds && department_open_powered) // Else, we have old sounds disabled, the door has per-department door sounds, and we have chosen to play department door sounds, use these.
			if(arePowerSystemsOn())
				sound = department_open_powered
				volume = 50
			else
				sound = open_sound_unpowered
				volume = 75
		else // Else, play these.
			if(arePowerSystemsOn())
				sound = open_sound_powered
				volume = 50
			else
				sound = open_sound_unpowered
				volume = 75

		var/turf/T = get_turf(M)
		if(isAI(M)) // AI holograms can listen too
			var/mob/living/silicon/ai/A = M
			if(A.holo && istype(LAZYACCESS(A.holo.masters, A),/obj/effect/overlay/aiholo))
				T = get_turf(A.holo)
		var/distance = get_dist(T, get_turf(src))
		if(distance <= world.view * 2)
			if(T && T.z == get_z(src))
				M.playsound_local(get_turf(src), sound, volume, 1, null, 0, TRUE, sound(sound), volume_channel = VOLUME_CHANNEL_DOORS)

	SSmotiontracker.ping(src,100)

	if(closeOther() != null && istype(closeOther(), /obj/machinery/door/airlock/) && !closeOther().density)
		closeOther().close()
	. = ..()

/obj/machinery/door/airlock/can_open(forced=0)
	if(!forced)
		if(!arePowerSystemsOn() || wire_cut(WIRE_OPEN_DOOR))
			return FALSE

	if(bolts_bolted(src) || weld_shut_welded(src))
		return FALSE
	. = ..()

/obj/machinery/door/airlock/can_close(forced=0)
	if(bolts_bolted(src) || weld_shut_welded(src))
		return FALSE
	if(!forced)
		//despite the name, this wire is for general door control.
		if(hold_open())
			if(Adjacent(hold_open()) && !hold_open().incapacitated())
				return FALSE
			else
				rel_clear(src, nameof(hold_open))
		if(!arePowerSystemsOn() || wire_cut(WIRE_OPEN_DOOR))
			return	0
	. = ..()

/atom/movable/proc/blocks_airlock()
	return density

/obj/machinery/door/blocks_airlock()
	return FALSE

/obj/machinery/mech_sensor/blocks_airlock()
	return FALSE

/mob/living/blocks_airlock()
	return !is_incorporeal()

/atom/movable/proc/airlock_crush(crush_damage)
	return FALSE

/obj/machinery/portable_atmospherics/canister/airlock_crush(crush_damage)
	. = ..()
	take_damage(crush_damage, BRUTE)

/obj/effect/energy_field/airlock_crush(crush_damage)
	adjust_strength(crush_damage)

/obj/structure/closet/airlock_crush(crush_damage)
	..()
	take_damage(crush_damage, BRUTE)
	latent_materialize_all() // crushing reaches the contents (C5)
	for(var/atom/movable/AM in contents_of(src)) // ALLOW(latent): walk reviewed: reads what is materialized on purpose
		AM.airlock_crush()
	return TRUE

/mob/living/airlock_crush(crush_damage)
	if(is_incorporeal())
		return FALSE
	. = ..()
	var/turf/T = get_turf(src)
	injure(INJURY_BLUNT, crush_damage)
	status_set(EFFECT_STUNNED, 5)
	status_set(EFFECT_WEAKENED, 5)
	if(T)
		T.add_blood(src)
	return TRUE

/mob/living/carbon/airlock_crush(crush_damage)
	. = ..()
	if(. && can_feel_pain()) // Only scream if actually crushed!
		emote("scream")

/mob/living/silicon/robot/airlock_crush(crush_damage)
	injure(INJURY_BLUNT, crush_damage)
	return FALSE

/obj/machinery/door/airlock/close(forced= FALSE, ignore_safties = FALSE, crush_damage)
	if(!can_close(forced))
		return FALSE
	clear_autoclose_blockers()
	if(frozen && !forced)
		return FALSE
	if(frozen && forced) // Unfreeze on forced open
		unFreeze()

	rel_clear(src, nameof(hold_open)) //if it passes the can close check, always make sure to clear hold open

	if(safe && !ignore_safties)
		for(var/turf/turf in locs)
			for(var/atom/movable/AM in turf)
				if(AM.blocks_airlock())
					if(!has_beeped)
						play_sfx(src, SFX_MACHINES_BUZZ_TWO)
						has_beeped = 1
					sleep_until_autoclose_blocker_moves(AM)
					return

	crush_contents(crush_damage)

	use_power(360)	//360 W seems much more appropriate for an actuator moving an industrial door capable of crushing people
	has_beeped = 0
	for(var/mob/M as anything in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(!M || !M.client)
			continue
		var/old_sounds = M.read_preference(/datum/preference/toggle/old_door_sounds)
		var/department_door_sounds = M.read_preference(/datum/preference/toggle/department_door_sounds)
		var/sound
		var/volume
		if(old_sounds)
			if(arePowerSystemsOn())
				sound = legacy_close_powered
				volume = 50
			else
				sound = open_sound_unpowered
				volume = 75
		else if(!old_sounds && department_door_sounds && department_close_powered) // Else, we have old sounds disabled, the door has per-department door sounds, and we have chosen to play department door sounds, use these.
			if(arePowerSystemsOn())
				sound = department_close_powered
				volume = 50
			else
				sound = open_sound_unpowered
				volume = 75
		else
			if(arePowerSystemsOn())
				sound = close_sound_powered
				volume = 50
			else
				sound = open_sound_unpowered
				volume = 75

		var/turf/T = get_turf(M)
		if(isAI(M)) // AI holograms can listen too
			var/mob/living/silicon/ai/A = M
			if(A.holo && istype(LAZYACCESS(A.holo.masters, A),/obj/effect/overlay/aiholo))
				T = get_turf(A.holo)

		var/distance = get_dist(T, get_turf(src))
		if(distance <= world.view * 2)
			if(T && T.z == get_z(src))
				M.playsound_local(get_turf(src), sound, volume, 1, null, 0, TRUE, sound(sound), volume_channel = VOLUME_CHANNEL_DOORS)

	SSmotiontracker.ping(src,100)

	for(var/turf/turf in locs)
		var/obj/structure/window/killthis = (locate_within(turf, /obj/structure/window))
		if(killthis)
			killthis.ex_act(2)//Smashin windows
	. = ..()

/// Drops the bolts (the key BOLTS_BOLTED). forced drops them mid-swing.
/obj/machinery/door/airlock/proc/lock(forced=0)
	if(bolts_bolted(src))
		return FALSE

	if (operating && !forced) return FALSE

	cap_key_set(src, BOLTS_BOLTED, TRUE, null)
	playsound(src, bolt_down_sound, 30, 0, 3, volume_channel = VOLUME_CHANNEL_DOORS)
	for(var/mob/M in range(1,src))
		M.show_message("You hear a click from the bottom of the door.", 2)
	// A bolted open door cannot autoclose: drop the deadline instead of waking to find that out.
	if(!density)
		autoclose_cancel()
	publish_door_mode()
	return TRUE

/// Raises the bolts. Unless forced, needs power, a still door and an uncut bolt wire.
/obj/machinery/door/airlock/proc/unlock(forced=0)
	if(!bolts_bolted(src))
		return

	if (!forced)
		if(operating || !arePowerSystemsOn() || wire_cut(WIRE_DOOR_BOLTS)) return

	cap_key_set(src, BOLTS_BOLTED, FALSE, null)
	playsound(src, bolt_up_sound, 30, 0, 3, volume_channel = VOLUME_CHANNEL_DOORS)
	for(var/mob/M in range(1,src))
		M.show_message("You hear a click from the bottom of the door.", 2)
	resume_autoclose_if_possible()
	publish_door_mode()
	return TRUE

/obj/machinery/door/airlock/allowed(mob/M)
	if(bolts_bolted(src))
		return FALSE
	. = ..()

/// The door's own req_access and req_one_access (a map varies them per door); emergency access lets anyone through.
/obj/machinery/door/airlock/check_access_list(list/L)
	if(door_emergency_engaged(src))
		return TRUE
	return ..()

/obj/machinery/door/airlock/Initialize(mapload, obj/structure/door_assembly/assembly=null)
	//if assembly is given, create the new door from the assembly
	if (assembly && istype(assembly))
		assembly_type = assembly.type

		var/obj/item/airlock_electronics/assembly_electronics = assembly.electronics
		assembly_electronics.forceMove(src)
		own_move(assembly_electronics, src, nameof(electronics)) // from the assembly to the door

		//update the door's access to match the electronics'
		secured_wires = electronics.secure
		if(electronics.one_access)
			req_access = null
			req_one_access = electronics.conf_access
		else
			req_one_access = null
			req_access = electronics.conf_access

		//get the name from the assembly
		if(assembly.created_name)
			name = assembly.created_name
		else
			name = "[istext(assembly.glass) ? "[assembly.glass] airlock" : assembly.base_name]"

		//get the dir from the assembly
		set_dir(assembly.dir)

	// Wires: the wires capability makes them on first use, secure ones for secured_wires (wires_type_for()).
	var/turf/T = get_turf(src)
	if(T && (T.z in using_map.admin_levels))
		secured_wires = 1

	. = ..()

	if(closeOtherId != null)
		for (var/obj/machinery/door/airlock/A in REGISTRY_MEMBERS(REGISTRY_MACHINES))
			if(A.closeOtherId == closeOtherId && A != src)
				rel_set(src, nameof(closeOther), A)
				break
	name = "\improper [name]"
	if(frequency)
		set_frequency(frequency)

// Most doors will never be deconstructed over the course of a round,
// so as an optimization defer the creation of electronics until
// the airlock is deconstructed
/obj/machinery/door/airlock/proc/create_electronics()
	//create new electronics
	if (secured_wires)
		rel_set(src, nameof(electronics), new/obj/item/airlock_electronics/secure(src))
	else
		rel_set(src, nameof(electronics), new/obj/item/airlock_electronics(src))

	//update the electronics to match the door's access
	if(LAZYLEN(req_access))
		electronics.conf_access = req_access
	else if (LAZYLEN(req_one_access))
		electronics.conf_access = req_one_access
		electronics.set_one_access(1)

/obj/machinery/door/airlock/power_change() //putting this is obj/machinery/door itself makes non-airlock doors turn invisible for some reason
	. = ..()
	if(has_stat(NOPOWER))
		// If we lost power, disable electrification
		// Keeping door lights on, runs on internal battery or something.
		cancel_after(src, "electrified")
		electrified_to(0)
	resume_autoclose_if_possible()

/obj/machinery/door/airlock/proc/prison_open()
	if(arePowerSystemsOn())
		unlock()
		open()
		lock()
	return

/* moved this block to code\game\objects\items\weapons\rcd.dm
/obj/machinery/door/airlock/rcd_values(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			// Old RCD code made it cost 10 units to decon an airlock.
			// Now the new one costs ten "sheets".
			return rcd_value_entry(RCD_DECONSTRUCT, 5 SECONDS, RCD_SHEETS_PER_MATTER_UNIT * 10)
	return FALSE

/obj/machinery/door/airlock/rcd_act(mob/living/user, obj/item/rcd/the_rcd, passed_mode)
	switch(passed_mode)
		if(RCD_DECONSTRUCT)
			to_chat(user, span_notice("You deconstruct \the [src]."))
			qdel(src)
			return TRUE
	return FALSE
*/

/// Most airlocks don't freeze, subtypes set this
/obj/machinery/door/airlock/proc/can_freeze(datum/act/A)
	SHOULD_BE_PURE(TRUE) // Don't put logic here, just return if the airlock can freeze or not.
	PROTECTED_PROC(TRUE)
	return FALSE

/obj/machinery/door/airlock/proc/unFreeze()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)

	set_frozen(FALSE)

/obj/machinery/door/airlock/proc/freeze()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)

	set_frozen(TRUE)

// === merged from airlock_ch.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/machinery/door/airlock/scp
	name = "SCP Access"
	icon = 'icons/obj/doors/SCPdoor.dmi'
	open_sound_powered = 'sound/machines/scp1o.ogg'
	close_sound_powered = 'sound/machines/scp1c.ogg'

/obj/machinery/door/airlock/can_pathfinding_enter(atom/movable/actor, dir, datum/pathfinding/search)
	return ..() || (has_access(req_access, req_one_access, search.ss13_with_access) && !bolts_bolted(src) && operable())

// === merged from robot_chomp.dm during hard-fork de-suffix. Placed in this file because it
// is the highest-positioned definer in the override chain for the members it
// sets, so every override stays after its base definition (resolution preserved). ===
/mob/living/silicon/robot
	var/sleeper_resting = FALSE //Enable resting belly sprites for dogborgs that have the sprites
	var/datum/matter_synth/water_res //Enable water for lick clean
	//Multibelly support. We do not want to apply it to any module not supporting it in it's sprites

/mob/living/silicon/robot/proc/ex_reserve_refill()
	set name = "Refill Extinguisher"
	set category = VERB_CAT_OBJECT
	var/datum/matter_synth/water = water_res()
	for(var/obj/item/extinguisher/E in module.modules)
		if(E.reagents.total_volume < E.max_water)
			if(water && water.energy > 0)
				var/amount = E.max_water - E.reagents.total_volume
				if(water.energy < amount)
					amount = water.energy
				water.use_charge(amount)
				E.reagents.add_reagent(REAGENT_ID_WATER, amount)
				to_chat(src, span_filter_notice("You refill the extinguisher using your water reserves."))
			else
				to_chat(src, span_filter_notice("Insufficient water reserves."))

// Old attack_robot overrides: a cyborg with access interfaces remotely as the AI does
// (FALSE: the robot adapter's default); without it, only by hand from next to it.
// atmos_control.dm, robot.dm and turret_control.dm declare these types' other interactions;
// portable_turret.dm lists porta_turret_robot_use in the turret's own declare_interactions().
EXTEND_INTERACTIONS(/obj/machinery/computer/atmoscontrol, INTERACT_ROBOT("Use", PROC_REF(atmoscontrol_robot_use)))
EXTEND_INTERACTIONS(/obj/machinery/computer/robotics, INTERACT_ROBOT("Use", PROC_REF(robotics_console_robot_use)))
EXTEND_INTERACTIONS(/obj/machinery/turretid, INTERACT_ROBOT("Use", PROC_REF(turretid_robot_use)))

/obj/machinery/computer/atmoscontrol/proc/atmoscontrol_robot_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(allowed(user))
		return FALSE
	if(Adjacent(user))
		attack_hand(user)
	return TRUE

/obj/machinery/computer/robotics/proc/robotics_console_robot_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(allowed(user))
		return FALSE
	if(Adjacent(user))
		attack_hand(user)
	return TRUE

/obj/machinery/turretid/proc/turretid_robot_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(allowed(user))
		return FALSE
	if(Adjacent(user))
		attack_hand(user)
	return TRUE

/obj/machinery/porta_turret/proc/porta_turret_robot_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(allowed(user))
		return FALSE
	if(Adjacent(user))
		attack_hand(user)
	return TRUE

/obj/machinery/porta_turret/isLocked(mob/user)
	var/mob/living/silicon/robot/R = user
	if(!istype(R))
		return ..()
	if(!locked)
		return FALSE
	if(!check_access(R.idcard))
		return TRUE
	return FALSE

/// closeOther (a relation view: it reads null once the target is deleted).
/obj/machinery/door/airlock/proc/closeOther() as /obj/machinery/door/airlock
	return closeOther

/// hold open (a relation view: it reads null once the target is deleted).
/obj/machinery/door/airlock/proc/hold_open() as /mob
	return hold_open

/// water res (a relation view: it reads null once the target is deleted).
/mob/living/silicon/robot/proc/water_res() as /datum/matter_synth
	return water_res


// ---- the wires ----

/// An airlock's twelve wires. Every airlock shares the round's layout; one built with secure electronics has fourteen, its own colours.
/datum/wire_set/airlock
	name = "Airlock"
	count = 12
	window = "WiresAirlock"
	record = /datum/cap_data/wires/airlock
	wires = list(
		WIRE_IDSCAN, WIRE_MAIN_POWER1, WIRE_MAIN_POWER2, WIRE_DOOR_BOLTS,
		WIRE_BACKUP_POWER1, WIRE_BACKUP_POWER2, WIRE_OPEN_DOOR, WIRE_AI_CONTROL,
		WIRE_ELECTRIFY, WIRE_SAFETY, WIRE_SPEED, WIRE_BOLT_LIGHT)

/datum/wire_set/airlock/secure
	count = 14
	randomize = TRUE

/// The airlock's wires window adds its radio: the ID tag and the frequency.
/datum/cap_data/wires/airlock

CAPABILITIES(/datum/cap_data/wires/airlock)
	op("set_id_tag", ui_act(), needs(req_wires_in_reach()),
		asks(/datum/prompt/text, fields = list("title" = "ID Tag", "question" = "Enter a new ID tag", "default" = computed(PROC_REF(id_tag_now)), "max_len" = 60)),
		then(PROC_REF(id_tag_answered)))
	op("set_frequency", ui_act(arg("freq", num())), needs(req_wires_in_reach()), then(PROC_REF(frequency_set)))
	op("clear_frequency", ui_act(), needs(req_wires_in_reach()), then(PROC_REF(frequency_cleared)))

/datum/cap_data/wires/airlock/proc/id_tag_now(datum/act/A)
	var/obj/machinery/door/airlock/door = owner
	return istype(door) ? door.id_tag : ""

/datum/cap_data/wires/airlock/proc/id_tag_answered(datum/act/op/A)
	var/obj/machinery/door/airlock/door = owner
	var/datum/prompt/R = A.answer
	if(istype(door) && R?.value)
		keyed_set_id(door, nameof(/datum/embedded_program::id_tag), R.value) // re-links the keyed relations matching on it
	return OP_OK

/datum/cap_data/wires/airlock/proc/frequency_set(datum/act/op/A, freq)
	var/obj/machinery/door/airlock/door = owner
	door?.set_frequency(sanitize_frequency(freq, RADIO_LOW_FREQ, RADIO_HIGH_FREQ))
	return OP_OK

/datum/cap_data/wires/airlock/proc/frequency_cleared(datum/act/op/A)
	var/obj/machinery/door/airlock/door = owner
	door?.set_frequency(null)
	return OP_OK

/datum/cap_data/wires/airlock/ui_data(datum/act/eval/A)
	. = ..()
	var/obj/machinery/door/airlock/door = owner
	if(!istype(door))
		return
	.["id_tag"] = door.id_tag
	.["frequency"] = door.radio_connection() ? door.frequency : null
	.["min_freq"] = RADIO_LOW_FREQ
	.["max_freq"] = RADIO_HIGH_FREQ

/// The lights under the wires: what each wire drives, while the door has power.
/obj/machinery/door/airlock/proc/wire_lights()
	var/haspower = arePowerSystemsOn() // no power, no lights
	return list(
		"The door bolts [is_bolted(src) ? "have fallen!" : "look up."]",
		"The door bolt lights are [(lights && haspower) ? "on." : "off!"]",
		"The test light is [haspower ? "on." : "off!"]",
		"The backup power light is [backup_power_lost_until ? "off!" : "on."]",
		"The 'AI control allowed' light is [(aiControlDisabled == 0 && !emagged && haspower) ? "on" : "off"].",
		"The 'Check Wiring' light is [(safe == 0 && haspower) ? "on" : "off"].",
		"The 'Check Timing Mechanism' light is [(normalspeed == 0 && haspower) ? "on" : "off"].",
		"The IDScan light is [(aiDisabledIdScanner == 0 && haspower) ? "on" : "off."]")

/// Reaching into a live door's wires shocks anyone but a silicon, instead.
/obj/machinery/door/airlock/proc/wire_touch_shocks(datum/act/A)
	var/datum/act/touch_wires/T = A
	if(!issilicon(T.user) && isElectrified() && shock(T.user, 100))
		return OP_REFUSED
	return HOOK_DECLINE

/// Any wire moved: the door's look and panel follow it.
/obj/machinery/door/airlock/proc/wire_changed_look(datum/act/A)
	changed(src)

/obj/machinery/door/airlock/proc/idscan_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	set_aiDisabledIdScanner(!N.mended)

/// The ID wire pulsed flashes the red light (with power, while shut).
/obj/machinery/door/airlock/proc/idscan_wire_pulsed(datum/act/A)
	if(arePowerSystemsOn() && density)
		do_animate("deny")

/// Cutting a main power wire drops the door's main power (the backup takes over in ten seconds unless it is cut too); mending restores it.
/// Either may shock the hand.
/obj/machinery/door/airlock/proc/main_power_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(N.mended)
		regainMainPower()
	else
		loseMainPower()
	shock(N.user, 50)

/// A main power pulse trips its breaker.
/obj/machinery/door/airlock/proc/main_power_wire_pulsed(datum/act/A)
	loseMainPower()

/obj/machinery/door/airlock/proc/backup_power_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(N.mended)
		regainBackupPower()
	else
		loseBackupPower()
	shock(N.user, 50)

/obj/machinery/door/airlock/proc/backup_power_wire_pulsed(datum/act/A)
	loseBackupPower()

/// The bolt wire cut drops the bolts; mending it does not raise them.
/obj/machinery/door/airlock/proc/bolt_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(!N.mended)
		lock(1)

/// The bolt wire pulsed drops raised bolts, or raises dropped ones (with power).
/obj/machinery/door/airlock/proc/bolt_wire_pulsed(datum/act/A)
	if(!is_bolted(src))
		lock()
	else
		unlock()

/// The AI control wire cut locks the AI out (an AI that bypassed the lock before stays able to bypass it); mended, it lets it back.
/obj/machinery/door/airlock/proc/ai_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(!N.mended)
		if(aiControlDisabled == 0)
			set_aiControlDisabled(1)
		else if(aiControlDisabled == -1)
			set_aiControlDisabled(2)
	else
		if(aiControlDisabled == 1)
			set_aiControlDisabled(0)
		else if(aiControlDisabled == 2)
			set_aiControlDisabled(-1)

/// The AI control wire pulsed locks the AI out for a second.
/obj/machinery/door/airlock/proc/ai_wire_pulsed(datum/act/A)
	if(aiControlDisabled == 0)
		set_aiControlDisabled(1)
	else if(aiControlDisabled == -1)
		set_aiControlDisabled(2)
	after(src, 1 SECOND, PROC_REF(ai_control_pulse_ends))

/obj/machinery/door/airlock/proc/ai_control_pulse_ends()
	if(aiControlDisabled == 1)
		set_aiControlDisabled(0)
	else if(aiControlDisabled == 2)
		set_aiControlDisabled(-1)

/// The shock wire cut electrifies the door until it is mended.
/obj/machinery/door/airlock/proc/shock_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	electrify(N.mended ? 0 : -1, user = N.user)

/// The shock wire pulsed electrifies the door for thirty seconds.
/obj/machinery/door/airlock/proc/shock_wire_pulsed(datum/act/A)
	var/datum/notice/wire_pulsed/N = A
	electrify(30, user = N.user)

/// The door-open wire pulsed opens or shuts a door that asks no ID (or whose ID wire is cut), unless it is emagged.
/obj/machinery/door/airlock/proc/open_wire_pulsed(datum/act/A)
	if(emagged)
		return
	if(!requiresID() || check_access(null))
		if(density)
			open()
		else
			close()

/obj/machinery/door/airlock/proc/safety_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	set_safe(N.mended)

/// The safety wire pulsed flips the safeties (and an open door shuts).
/obj/machinery/door/airlock/proc/safety_wire_pulsed(datum/act/A)
	set_safe(!safe)
	if(!density)
		close()

/// The timing wire cut stops the autoclose; mended, it autocloses again (an open door shuts).
/obj/machinery/door/airlock/proc/speed_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	autoclose = N.mended
	if(N.mended && !density)
		close()

/obj/machinery/door/airlock/proc/speed_wire_pulsed(datum/act/A)
	normalspeed = !normalspeed

/obj/machinery/door/airlock/proc/bolt_light_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	set_lights(N.mended)

/obj/machinery/door/airlock/proc/bolt_light_wire_pulsed(datum/act/A)
	set_lights(!lights)
