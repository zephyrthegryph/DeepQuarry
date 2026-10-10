// The airlock (doc/rewrite/final_api.html, section 16.2; doc/rewrite/conversion_guide.md section 9).
//
// What an airlock is, declared below in one CAPABILITIES block: the door base (door.dm) brings the machine, the doors() touch, the emag, the plasteel
// and repair ops; the library brings the panel, the wires, the bolts (STAT_BOLTED, door_parts.dm), the weld and the emergency access. The airlock's
// own state is four stats composed from sourced holds, so every hand that changes them is a source and a timer is a hold that runs out:
//
//   STAT_ELECTRIFIED     the shock wire (shock_wire(): cut until mended, pulsed for 30 s), each AI (its own source), an EMP (SRC_EMP), a button
//                        or an event (SRC_LOCKDOWN)
//   STAT_MAIN_POWER_OUT  a cut main cable (SRC_POWER_WIRE), a tripped breaker for a minute (SRC_BREAKER)
//   STAT_BACKUP_POWER_OUT  the same for the backup, plus the ten seconds it takes to switch over when main power goes (SRC_BACKUP_SWITCHOVER)
//   STAT_AICONTROLDISABLED  the AI-control wire (ai_control(): cut until mended, pulsed for a second), a round event (SRC_ROUND_EVENT)
//   STAT_AIDISABLEDIDSCANNER, STAT_SAFE  the ID scan and safety wires (id_scan(), safety_wire()) and the AI's buttons (SRC_AI_CONTROL)
//
// The door has power while it is operable and main power, or the backup, carries it (power_systems_on()). Touching a live door shocks the toucher
// instead of doing what they meant: one takeover of every click op (extend(/datum/act/op, ...)), not a line per op.

/obj/machinery/door/airlock
	name = "Airlock"
	icon = 'icons/obj/doors/doorint.dmi'
	icon_state = "door_closed"
	power_channel = ENVIRON

	explosion_resistance = 10

	blocks_emissive = EMISSIVE_BLOCK_GENERIC // Not quite as nice as /tg/'s custom masks. We should make those sometime

	/// If 1, will not beep on a failed closing attempt. Resets when the door closes.
	var/has_beeped = 0
	/// The bolt lights show (the bolt-light wire and the AI's button).
	var/lights = 1
	/// The airlocks this one shuts when it opens: every airlock with the same closeOtherId (a symmetric link, joined at init).
	var/list/close_others
	var/closeOtherId = null
	autoclose = 1
	var/assembly_type = /obj/structure/door_assembly
	var/mineral = null
	/// A second between shocks from bumping it.
	COOLDOWN_DECLARE(bump_zap_cooldown)
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
	var/static/list/deicing_tools = list(
		/obj/item/ice_pick = 3,
		/obj/item/tool/crowbar = 5,
		/obj/item/pen = 30,
		/obj/item/card = 35,
		/obj/item/tool = 10,
		/obj/item = 12,
	)

/// Watts the actuator draws to move the door once (an industrial door that can crush people).
#define AIRLOCK_ACTUATOR_POWER 360

// ---- state ----

TRACKED(/obj/machinery/door/airlock, lights)
TRACKED(/obj/machinery/door/airlock, frozen)

/// Touching the door shocks (a held thing takes a smaller shock): who electrified it is the hold's source. TOP with base 0, the rule of the suit
/// cycler's stat of the same name: every hold is TRUE, so the door is live while anyone holds it.
STAT(/obj/machinery/door/airlock, electrified, TOP, base = 0)
/// The AI is locked out of the door: the AI control wire cut, for a second after a pulse, or a round event (ai_control()).
STAT(/obj/machinery/door/airlock, aiControlDisabled, ANY)
/// The door lets anyone through without an ID: the ID scan wire cut, or the AI's word (id_scan()).
STAT(/obj/machinery/door/airlock, aiDisabledIdScanner, ANY)
/// The door will not close on someone: off while the safety wire is cut or after a pulse, or by the AI, a lift's fire mode, an event (safety_wire()).
STAT(/obj/machinery/door/airlock, safe, ALL)
/// Main power is out: a cut main cable, a tripped breaker.
STAT(/obj/machinery/door/airlock, main_power_out, ANY)
/// The backup cannot carry the door: a cut backup cable, a tripped breaker, the switchover after main power went.
STAT(/obj/machinery/door/airlock, backup_power_out, ANY)

/// A button, an event or a scripted lockdown electrifying the door: hold(door, STAT_ELECTRIFIED, TRUE, SRC_LOCKDOWN).
SOURCE_DEF(lockdown)
/// A cut power cable (main or backup) of the airlock.
SOURCE_DEF(power_wire)
/// A tripped breaker of the airlock's main or backup power (a pulse, the AI's disrupt button): a minute.
SOURCE_DEF(breaker)
/// The ten seconds the backup takes to carry the door once main power goes.
SOURCE_DEF(backup_switchover)

MSG_DEF_SELF(airlock/panel_broken, "The panel is broken and cannot be closed.")
MSG_DEF_SELF(airlock/pry_bolted, "The airlock's bolts prevent it from being forced.")
MSG_DEF_SELF(airlock/pry_motors, "The airlock's motors resist your efforts to force it.")
MSG_DEF_SELF(airlock/not_for_you, "You cannot control this airlock.")
MSG_DEF_SELF(airlock/main_offline, "Main power is already offline.")
MSG_DEF_SELF(airlock/backup_offline, "Backup power is already offline.")
MSG_DEF_SELF(airlock/unpowered, "The door is unpowered - Cannot electrify the door.")
MSG_DEF_SELF(airlock/bolt_wire_cut, "The door bolt drop wire is cut - you can't toggle the door bolts.")
MSG_DEF_SELF(airlock/no_power_to_raise, "The door has no power - you can't raise the door bolts.")
MSG_DEF_SELF(airlock/swinging, "The door is moving.")
MSG_DEF_SELF(airlock/light_wire_cut, "The bolt lights wire is cut - The door bolt lights are permanently disabled.")
MSG_DEF_SELF(airlock/timing_wire_cut, "The timing wire is cut - Cannot alter timing.")
MSG_DEF_SELF(airlock/safety_wire_cut, "The safety wire is cut - Cannot enable safeties.")
MSG_DEF_SELF(airlock/idscan_wire_cut, "The IdScan wire is cut - IdScan feature permanently disabled.")
MSG_DEF_SELF(airlock/frozen, "The airlock is frozen shut!")
MSG_DEF_SELF(airlock/welded, "The airlock has been welded shut!")
MSG_DEF_SELF(airlock/bolted, "The door bolts are down!")
MSG_DEF_SELF(airlock/held_open, "Someone is holding it open!")
MSG_DEF_SELF(airlock/bolts_raised, "The door bolts have been raised.")
MSG_DEF_SELF(airlock/bolts_dropped, "The door bolts have been dropped.")
MSG_DEF_SELF(airlock/electrified, "The door is now electrified.")
MSG_DEF_SELF(airlock/unelectrified, "You stop electrifying the door.")
MSG_DEF_SELF(airlock/emergency_on, "Emergency access is now engaged.")
MSG_DEF_SELF(airlock/emergency_off, "Emergency access is now disengaged.")
MSG_DEF(airlock/hammered, "You hammer on %T%!", "%U% hammers on %T%!")
MSG_DEF(airlock/holds_open, "You begin holding %T% open.", "%U% begins holding %T% open.")

// ---- what an airlock is, declared ----

CAPABILITIES(/obj/machinery/door/airlock)
	panel()
	// twelve wires (fourteen and their own colours with secure electronics), in the airlock's window with its radio; the AI control, ID scan,
	// safety, shock and bolt wires come with the capabilities that own their state
	wires(name = "Airlock", count = PROC_REF(wire_count), randomize = PROC_REF(wires_randomized), window = "WiresAirlock", record = /datum/cap_data/wires/airlock, emp = FALSE, status_lines = PROC_REF(wire_lights))
	ai_control(stat = STAT_AICONTROLDISABLED, pulse_lasts = 1 SECOND)
	id_scan(stat = STAT_AIDISABLEDIDSCANNER, pulse_lasts = 0)
	safety_wire(stat = STAT_SAFE)
	shock_wire(stat = STAT_ELECTRIFIED)
	on_wire(WIRE_ELECTRIFY, cut = PROC_REF(electrify_wire_cut), pulse = PROC_REF(electrify_wire_pulsed))
	extend(/datum/act/touch_wires, instead(then(PROC_REF(wire_touch_shocks))))
	on_notice(/datum/notice/wire_cut, then(PROC_REF(wire_changed_look)))
	on_notice(/datum/notice/wire_pulsed, then(PROC_REF(wire_changed_look)))
	on_wire(WIRE_IDSCAN, pulse = PROC_REF(idscan_wire_pulsed)) // and the deny light flashes
	on_wire(WIRE_MAIN_POWER1, cut = PROC_REF(main_power_wire_cut), pulse = PROC_REF(main_power_wire_pulsed))
	on_wire(WIRE_MAIN_POWER2, cut = PROC_REF(main_power_wire_cut), pulse = PROC_REF(main_power_wire_pulsed))
	on_wire(WIRE_BACKUP_POWER1, cut = PROC_REF(backup_power_wire_cut), pulse = PROC_REF(backup_power_wire_pulsed))
	on_wire(WIRE_BACKUP_POWER2, cut = PROC_REF(backup_power_wire_cut), pulse = PROC_REF(backup_power_wire_pulsed))
	on_wire(WIRE_OPEN_DOOR, pulse = PROC_REF(open_wire_pulsed))
	on_wire(WIRE_SAFETY, pulse = PROC_REF(safety_wire_pulsed)) // and an open door shuts
	on_wire(WIRE_SPEED, cut = PROC_REF(speed_wire_cut), pulse = PROC_REF(speed_wire_pulsed))
	on_wire(WIRE_BOLT_LIGHT, cut = PROC_REF(bolt_light_wire_cut), pulse = PROC_REF(bolt_light_wire_pulsed))
	bolts(drop = "drop_bolts", raise = "raise_bolts", starts = nameof(bolted_at_start), wire = WIRE_DOOR_BOLTS)
	weld_shut(offered = PROC_REF(weld_offered), starts = nameof(welded_at_start))
	door_emergency()
	owns_one(nameof(electronics), /obj/item/airlock_electronics)
	ref_many(nameof(close_others), /obj/machinery/door/airlock)
	ref_one(nameof(hold_open), /mob)   // who holds the door open (the ctrl-click's grab)   // the paired doors: each end names the other (join_close_group())
	on_change(nameof(bolted), ANY, then(PROC_REF(bolts_moved)))
	on_change(nameof(main_power_out), ANY, then(PROC_REF(main_power_changed)))
	on_change(nameof(backup_power_out), ANY, then(PROC_REF(power_changed)))
	on_change(nameof(electrified), ANY, then(PROC_REF(publish_door_mode)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(airlock_emp)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(door_emp)))
	every(1 SECOND, then(PROC_REF(command_step)), when = nameof(cur_command))

	section(touch, "What a hand or a held thing does to the door")
	op("pry", tool(TOOL_CROWBAR), stance(I_HELP, I_DISARM, I_GRAB), wait(0),
		needs(req(PROC_REF(pry_blocked))), then(PROC_REF(pry_forced)))
	op("remove_electronics", tool(TOOL_CROWBAR), label("Remove electronics"), when(PROC_REF(can_remove_electronics)), priority(above("pry")),
		wait(4 SECONDS), then(PROC_REF(crowbar_act_tool_done)))
	op("wires_window", hand(), at(SPACE_PANEL), priority(OP_PRIORITY_PART), wait(0),
		needs(req(PROC_REF(hand_refusal))), then(PROC_REF(show_wires)))
	op("tear", hand(), label("Tear"), when(PROC_REF(claws_tear)), priority(OP_PRIORITY_TAKE_OUT), wait(PROC_REF(tear_wait)),
		needs(req(PROC_REF(hand_refusal))), then(PROC_REF(tear_done)))
	op("tape", item(/obj/item/taperoll), priority(OP_PRIORITY_PART), wait(0), then(PROC_REF(touched_by_held)))
	op("signaler", item(/obj/item/assembly/signaler), priority(OP_PRIORITY_PART), wait(0), then(PROC_REF(signaler_touch)))
	op("pai_cable", item(/obj/item/pai_cable), priority(OP_PRIORITY_PART), wait(0), then(PROC_REF(pai_cable_plugin)))
	op("pry_weapon", item(/obj/item), when(PROC_REF(prying_weapon)), priority(OP_PRIORITY_PART), wait(0), then(PROC_REF(pry_weapon_forced)))
	op("break_in", ai(), wait(10 SECONDS), then(PROC_REF(break_in_done)))
	op("deice", item(/obj/item), label("Clear the ice"), when(frozen), priority(OP_PRIORITY_SUBVERT), wait(PROC_REF(deice_wait)), then(PROC_REF(deice_done)))
	op("deice_tool", any_of_tools(TOOL_CROWBAR, TOOL_SCREWDRIVER, TOOL_WIRECUTTER, TOOL_MULTITOOL, TOOL_WELDER), label("Clear the ice"), when(frozen),
		priority(OP_PRIORITY_SUBVERT), wait(PROC_REF(deice_wait)), then(PROC_REF(deice_done)))
	extend("panel.open", wait(0), needs(req(PROC_REF(panel_closable))), then(PROC_REF(panel_toggled)))
	extend("weld_shut.toggle", priority(above("repair")), when(cond_any(cond_not(PROC_REF(damaged)), cond_not(req_stance(I_HELP)))))
	extend("doors.open", then(PROC_REF(hold_release_touch), early = TRUE), then(PROC_REF(touched_early), early = TRUE))
	extend("doors.close", then(PROC_REF(hold_release_touch), early = TRUE), then(PROC_REF(touched_early), early = TRUE))
	// Touching a live door shocks you instead of doing what you meant. Window buttons and a silicon's link are not touches.
	extend(/datum/act/op, instead(when(STAT_ELECTRIFIED, req_on_origin(ORIGIN_CLICK)), then(PROC_REF(shock_toucher)), order = ORDER_EARLY))
	// Walking into a live door shocks you instead of opening it; a mech reports to the cycling controller.
	extend(/datum/act/bump, instead(then(PROC_REF(bump_shocks)), order = ORDER_EARLY))
	on_notice(/datum/notice/bumped, then(PROC_REF(mech_bumped_status)))

	section(ctrl_click, "The ctrl-click on the door: hammer on it (combat), hold it open (grab), ring the bell (anything else)")
	// A silicon's ctrl-click is its bolt button over the link (below), never a hand on the door.
	op("hammer", inputs(hand(), item(/obj/item)), gesture(GESTURE_CTRL), stance(I_HURT), label("Hammer on the door"), priority(OP_PRIORITY_ATTACK),
		when(req_actor_kind(/mob/living/silicon, not = TRUE)), needs(req_adjacent()), wait(0), then(PROC_REF(hammer_on_door)))
	op("hold_open", inputs(hand(), item(/obj/item)), gesture(GESTURE_CTRL), stance(I_GRAB), label("Hold the door open"), priority(OP_PRIORITY_PART),
		when(req_actor_kind(/mob/living/silicon, not = TRUE)), needs(req_adjacent()), wait(0), then(PROC_REF(hold_door_open)))
	op("doorbell", inputs(hand(), item(/obj/item)), gesture(GESTURE_CTRL), label("Ring the bell"), priority(OP_PRIORITY_NORMAL),
		when(req_actor_kind(/mob/living/silicon, not = TRUE)), needs(req_adjacent()), wait(0), then(PROC_REF(ring_doorbell)))

	section(controls, "The remote control window (an AI's, a cyborg's, an admin ghost's) and a silicon's gestures over its link")
	interface("AiAirlock")
	extend("ui_open", inputs(remote())) // silicons only: remote() replaces the hand binding
	extend(TAG_UI, needs(req_silicon_or_admin(because = MSG(airlock/not_for_you)), req_window_usable(remote = PROC_REF(ai_control_allowed), remote_because = MSG(airlock/not_for_you))))
	op("disrupt_main", ui_act("disrupt-main"), needs(req_is(STAT_MAIN_POWER_OUT, FALSE, because = MSG(airlock/main_offline))), then(PROC_REF(lose_main_power)))
	op("disrupt_backup", ui_act("disrupt-backup"), needs(req(PROC_REF(backup_available), because = MSG(airlock/backup_offline))), then(PROC_REF(lose_backup_power)))
	op("shock_restore", ui_act("shock-restore"), releases(STAT_ELECTRIFIED, source = ON_ACTOR), says(MSG(airlock/unelectrified)))
	op("shock_temp", ui_act("shock-temp"), needs(req(PROC_REF(power_available), because = MSG(airlock/unpowered))),
		holds(STAT_ELECTRIFIED, TRUE, lasts = 30 SECONDS, source = ON_ACTOR), then(PROC_REF(electrified_by)), says(MSG(airlock/electrified)), logs(LOG_GAME))
	op("shock_perm", ui_act("shock-perm"), needs(req(PROC_REF(power_available), because = MSG(airlock/unpowered))),
		holds(STAT_ELECTRIFIED, TRUE, source = ON_ACTOR), then(PROC_REF(electrified_by)), says(MSG(airlock/electrified)), logs(LOG_GAME))
	op("idscan_toggle", ui_act("idscan-toggle"), needs(req_wire(WIRE_IDSCAN, because = MSG(airlock/idscan_wire_cut))),
		toggles_hold(STAT_AIDISABLEDIDSCANNER, source = SRC_AI_CONTROL))
	op("emergency_toggle", ui_act("emergency-toggle"), toggles(DOOR_EMERGENCY_ENGAGED), says(PROC_REF(emergency_message)), logs(LOG_GAME))
	op("bolt_toggle", ui_act("bolt-toggle"), needs(req_wire(WIRE_DOOR_BOLTS, because = MSG(airlock/bolt_wire_cut)),
		req_is(nameof(operating), FALSE, because = MSG(airlock/swinging)), req(PROC_REF(actor_may_move_bolts))),
		toggles_hold(STAT_BOLTED, source = ON_ACTOR), says(PROC_REF(bolts_message)), logs(LOG_GAME))
	op("light_toggle", ui_act("light-toggle"), needs(req_wire(WIRE_BOLT_LIGHT, because = MSG(airlock/light_wire_cut))), toggles(nameof(lights)))
	op("safe_toggle", ui_act("safe-toggle"), needs(req_wire(WIRE_SAFETY, because = MSG(airlock/safety_wire_cut))), then(PROC_REF(safeties_toggled)))
	op("speed_toggle", ui_act("speed-toggle"), needs(req_wire(WIRE_SPEED, because = MSG(airlock/timing_wire_cut))), toggles(nameof(normalspeed)))
	op("open_close", ui_act("open-close"), needs(req_is(nameof(frozen), FALSE, because = MSG(airlock/frozen)),
		req_is(WELD_SHUT_WELDED, FALSE, because = MSG(airlock/welded)), req_is(STAT_BOLTED, FALSE, because = MSG(airlock/bolted)),
		req(PROC_REF(not_held_by_another))), then(PROC_REF(ui_open_close)))
	// a silicon's gestures over its link: shift opens or closes it, ctrl bolts it, alt electrifies it, middle switches the bolt lights (the AI's: a
	// cyborg's middle-click cycles its modules)
	extend("open_close", binds(remote()), gesture(GESTURE_SHIFT))
	extend("bolt_toggle", binds(remote()), gesture(GESTURE_CTRL))
	op("remote_shock", remote(), gesture(GESTURE_ALT), label("Toggle electrification"), toggles_hold(STAT_ELECTRIFIED, TRUE, source = ON_ACTOR),
		then(PROC_REF(remote_shock_marked)), logs(LOG_GAME))
	extend("remote_shock", needs(req_silicon_or_admin(because = MSG(airlock/not_for_you)), req_window_usable(remote = PROC_REF(ai_control_allowed), remote_because = MSG(airlock/not_for_you))))
	op("remote_lights", remote(), gesture(GESTURE_MIDDLE), when(req_actor_kind(/mob/living/silicon/ai)), label("Toggle the bolt lights"),
		needs(req_wire(WIRE_BOLT_LIGHT, because = MSG(airlock/light_wire_cut))), toggles(nameof(lights)))
	extend("remote_lights", needs(req_silicon_or_admin(because = MSG(airlock/not_for_you)), req_window_usable(remote = PROC_REF(ai_control_allowed), remote_because = MSG(airlock/not_for_you))))
	param(nameof(assembly_at_make), pos = 1, apply = PROC_REF(build_from_assembly), keep = FALSE)


// ---- power ----

/// The door can move on its own power: it works, and main power or the backup carries it.
/obj/machinery/door/airlock/proc/power_systems_on(datum/act/A)
	return operable() && (!main_power_out || !backup_power_out)

/// Both main and backup cables are cut (or the door does not work at all): nothing can power it, and a silicon cannot reach it.
/obj/machinery/door/airlock/proc/all_power_lost()
	return !operable() || (main_cables_cut() && backup_cables_cut())

/obj/machinery/door/airlock/proc/main_cables_cut()
	return wire_is_cut(src, WIRE_MAIN_POWER1) || wire_is_cut(src, WIRE_MAIN_POWER2)

/obj/machinery/door/airlock/proc/backup_cables_cut()
	return wire_is_cut(src, WIRE_BACKUP_POWER1) || wire_is_cut(src, WIRE_BACKUP_POWER2)

/// The backup is carrying the door now (main power out, the backup up): what the disrupt-backup button can trip, and the backup light.
/obj/machinery/door/airlock/proc/backup_carries(datum/act/A)
	return main_power_out && !backup_power_out

/// A main power breaker trips for a minute (a pulse, the AI's button).
/obj/machinery/door/airlock/proc/lose_main_power(datum/act/A)
	main_power_goes(SRC_BREAKER, 1 MINUTE)
	return OP_OK

/// Main power goes out for `source` (for `lasts`, or until released): the backup takes ten seconds to switch over when main power was on.
/obj/machinery/door/airlock/proc/main_power_goes(source, lasts)
	if(!main_power_out)
		hold(src, STAT_BACKUP_POWER_OUT, TRUE, SRC_BACKUP_SWITCHOVER, 10 SECONDS)
	hold(src, STAT_MAIN_POWER_OUT, TRUE, source, lasts)

/// A backup power breaker trips for a minute.
/obj/machinery/door/airlock/proc/lose_backup_power(datum/act/A)
	hold(src, STAT_BACKUP_POWER_OUT, TRUE, SRC_BREAKER, 1 MINUTE)
	return OP_OK

/// Main power went or came back (the switchover started with it, main_power_goes()): back, the backup stands by again.
/obj/machinery/door/airlock/proc/main_power_changed(datum/act/A)
	if(!main_power_out)
		release(src, STAT_BACKUP_POWER_OUT, SRC_BACKUP_SWITCHOVER)
	power_changed(A)

/// Main or backup power changed: a door that lost every power line drops its current, and a door that can move again takes up its autoclose.
/obj/machinery/door/airlock/proc/power_changed(datum/act/A)
	if(electrified && all_power_lost())
		release(src, STAT_ELECTRIFIED, SRC_ALL)
	resume_autoclose_if_possible()
	publish_door_mode()

/obj/machinery/door/airlock/power_change() //putting this is obj/machinery/door itself makes non-airlock doors turn invisible for some reason
	. = ..()
	if(power_lost())
		release(src, STAT_ELECTRIFIED, SRC_ALL) // the door lights run on an internal battery; the current does not
	resume_autoclose_if_possible()

/// Raises CHANGE_MACHINE_MODE for whatever watches this door (bolts, power, electrification).
/obj/machinery/door/airlock/proc/publish_door_mode(datum/act/A)
	changed(src, CHANGE_MACHINE_MODE)

// ---- electrification ----

/// Electrifies the door: `duration` seconds, -1 until released, 0 releases `source`'s hold (a button, an event or a script is SRC_LOCKDOWN). Refused
/// without power. `user`, when someone did it, goes in the admins' history; no one is the ambient "EMP" entry.
/obj/machinery/door/airlock/proc/electrify(duration, source = SRC_LOCKDOWN, mob/user)
	if(!duration)
		return release(src, STAT_ELECTRIFIED, source)
	if(!power_systems_on())
		return FALSE
	if(user)
		LAZYADD(shockedby, "\[[time_stamp()]\] - [user](ckey:[user.ckey])")
		add_attack_logs(user, src, "Electrified a door")
	else
		LAZYADD(shockedby, "\[[time_stamp()]\] - EMP)")
	return hold(src, STAT_ELECTRIFIED, TRUE, source, duration > 0 ? duration SECONDS : null)

/// Wire holds keep their own sources; the supplied operator still belongs in the admin history.
/obj/machinery/door/airlock/proc/electrify_wire_cut(datum/notice/wire_cut/N)
	if(!N.mended)
		record_electrifier(N.user)

/obj/machinery/door/airlock/proc/electrify_wire_pulsed(datum/notice/wire_pulsed/N)
	record_electrifier(N.user)

/obj/machinery/door/airlock/proc/record_electrifier(mob/actor)
	if(actor)
		LAZYADD(shockedby, "\[[time_stamp()]\] - [actor](ckey:[actor.ckey])")
		add_attack_logs(actor, src, "Electrified a door")

/// Who electrified the door, for the admins.
/obj/machinery/door/airlock/proc/electrified_by(datum/act/op/A)
	record_electrifier(A.actor)
	return OP_OK

/// A silicon's alt-click toggled its own current: the one who did it sees a mark on the door.
/obj/machinery/door/airlock/proc/remote_shock_marked(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(electrified)
		electrified_by(A)
	if(user?.client)
		var/turf/root_turf = get_turf(src)
		var/image/client_only/electrify_notice/zap = new('icons/hud/screen_gen.dmi', root_turf, held_by_source(src, STAT_ELECTRIFIED, user) ? "stamina_crit" : "stamina_dead", OBFUSCATION_LAYER, SOUTH)
		zap.place_from_root(root_turf)
		zap.append_client(user.client)
	return OP_OK

/// An EMP may electrify the door for a while (thirty seconds over the severity).
/obj/machinery/door/airlock/proc/airlock_emp(datum/act/A)
	var/datum/notice/hit/emp/N = A
	var/severity = max(N.packet?.severity, 1)
	if(prob(40 / severity))
		electrify(30 / severity, SRC_EMP)

// shock user with probability prb (if all connections & power are working)
// returns 1 if shocked, 0 otherwise
/obj/machinery/door/airlock/shock(mob/user, prb)
	if(!power_systems_on())
		return FALSE
	if(!COOLDOWN_FINISHED(src, hasShocked))
		return FALSE	//Already shocked someone recently?
	if(..())
		COOLDOWN_START(src, hasShocked, 1 SECOND)
		return TRUE
	return FALSE

/// An electrified door shocks whoever touches it, instead of what the touch meant: silicons are spared, a bare hand takes the full shock and a held
/// thing a smaller one. A shock that does not land (no power source, insulated gloves) lets the touch go on.
/obj/machinery/door/airlock/proc/shock_toucher(datum/act/op/A)
	var/mob/user = A.actor
	if(!user || (A.authority & AUTH_REMOTE_ACCESS)) // a silicon's link touches nothing
		return HOOK_DECLINE
	if(shock(user, A.held ? 75 : 100))
		return OP_OK
	return HOOK_DECLINE

// ---- AI control ----

/// A silicon can work the door over its link: its AI control is not locked out and a power line reaches it.
/obj/machinery/door/airlock/proc/ai_control_allowed(datum/act/op/A)
	return !aiControlDisabled && !all_power_lost()

// ---- bolts (the bolts() library's drop and raise, door_parts.dm) ----

/// Drops the bolts: the door's own motor holds them (SRC_DOOR_BOLTS). Refused mid-swing unless forced. TRUE when they dropped now.
/obj/machinery/door/airlock/proc/drop_bolts(forced = FALSE)
	if(operating && !forced)
		return FALSE
	var/was = bolted
	hold(src, STAT_BOLTED, TRUE, SRC_DOOR_BOLTS)
	return !was

/// Raises the bolts, whoever dropped them. Unless forced, needs power, a still door and an uncut bolt wire. TRUE when they rose.
/obj/machinery/door/airlock/proc/raise_bolts(forced = FALSE)
	if(!bolted)
		return FALSE
	if(!forced && (operating || !power_systems_on() || wire_is_cut(src, WIRE_DOOR_BOLTS)))
		return FALSE
	release(src, STAT_BOLTED, SRC_ALL)
	resume_autoclose_if_possible()
	return !bolted

/// The bolts moved: the clunk, and a bolted open door stops waiting to close.
/obj/machinery/door/airlock/proc/bolts_moved(datum/act/A)
	playsound(src, bolted ? bolt_down_sound : bolt_up_sound, 30, 0, 3, volume_channel = VOLUME_CHANNEL_DOORS)
	audible_message("You hear a click from the bottom of the door.", hearing_distance = 1)
	if(bolted)
		if(!density)
			autoclose_cancel()
	else
		resume_autoclose_if_possible()
	publish_door_mode()

/// The bolt button: raising this actor's own hold needs power (dropping one never does).
/obj/machinery/door/airlock/proc/actor_may_move_bolts(datum/act/op/A)
	return (!held_by_source(src, STAT_BOLTED, A.actor) || power_systems_on()) ? null : MSG(airlock/no_power_to_raise)

/obj/machinery/door/airlock/proc/bolts_message(datum/act/op/A)
	return bolted ? /datum/msg/airlock/bolts_dropped : /datum/msg/airlock/bolts_raised

/// The bolts come up and the weld lets go, with no mechanism and no noise check (a spirit, a claw, a break-in).
/obj/machinery/door/airlock/proc/unbolt_unweld()
	set_bolted(src, FALSE, TRUE)
	set_welded(src, FALSE)

/// The prison break: a powered cell door opens and its bolts drop again behind it.
/obj/machinery/door/airlock/proc/prison_open()
	if(!power_systems_on())
		return
	set_bolted(src, FALSE)
	open()
	set_bolted(src, TRUE, TRUE)

// ---- the window ----

/obj/machinery/door/airlock/proc/emergency_message(datum/act/op/A)
	return door_emergency_engaged(src) ? /datum/msg/airlock/emergency_on : /datum/msg/airlock/emergency_off

/// Nobody but the actor holds the door open.
/obj/machinery/door/airlock/proc/not_held_by_another(datum/act/op/A)
	return (density || isnull(hold_open()) || hold_open() == A.actor) ? null : MSG(airlock/held_open)

/// The window's open-close button: the door swings, a holder's own press lets go of it first.
/obj/machinery/door/airlock/proc/ui_open_close(datum/act/op/A)
	add_fingerprint(A.actor)
	if(density)
		open()
		return OP_OK
	if(hold_open() == A.actor)
		rel_clear(src, nameof(hold_open))
	close()
	return OP_OK

/// The ID scanner switched by a button or the AI: on, or off (a cut ID wire keeps it off whatever it says).
/obj/machinery/door/airlock/proc/set_idscan(activate)
	if(wire_is_cut(src, WIRE_IDSCAN))
		return
	if(activate)
		release(src, STAT_AIDISABLEDIDSCANNER, SRC_AI_CONTROL)
	else
		hold(src, STAT_AIDISABLEDIDSCANNER, null, SRC_AI_CONTROL)

/// The safeties switched by a button or the AI (a cut safety wire keeps them off): back on, they also undo a pulse that turned them off.
/obj/machinery/door/airlock/proc/set_safeties(activate)
	if(wire_is_cut(src, WIRE_SAFETY))
		return
	if(activate)
		release(src, STAT_SAFE, SRC_AI_CONTROL)
		release(src, STAT_SAFE, wire_def(WIRE_SAFETY).pulse_source)
	else
		hold(src, STAT_SAFE, null, SRC_AI_CONTROL)

/// The window's safeties button.
/obj/machinery/door/airlock/proc/safeties_toggled(datum/act/op/A)
	set_safeties(!safe)
	return OP_OK

/// The window's data: the power, the wires, and the state each part of the door keeps.
/obj/machinery/door/airlock/ui_data(datum/act/eval/A)
	var/list/data = list()
	var/list/power = list()
	var/main_left = hold_left(src, STAT_MAIN_POWER_OUT, SRC_BREAKER)
	var/backup_left = max(hold_left(src, STAT_BACKUP_POWER_OUT, SRC_BREAKER), hold_left(src, STAT_BACKUP_POWER_OUT, SRC_BACKUP_SWITCHOVER))
	power["main"] = (main_power_out && !main_cables_cut()) ? 0 : 2
	power["main_timeleft"] = main_cables_cut() ? -1 : (main_power_out ? round(main_left / 10, 1) : 0)
	power["backup"] = (backup_power_out && !backup_cables_cut()) ? 0 : 2
	power["backup_timeleft"] = backup_carries(A) ? 0 : ((backup_power_out && !backup_cables_cut()) ? round(backup_left / 10, 1) : -1)
	data["power"] = power
	data["id_scanner"] = !aiDisabledIdScanner
	data["lights"] = lights
	data["opened"] = !density
	var/list/wire = list()
	wire["main_1"] = !wire_is_cut(src, WIRE_MAIN_POWER1)
	wire["main_2"] = !wire_is_cut(src, WIRE_MAIN_POWER2)
	wire["backup_1"] = !wire_is_cut(src, WIRE_BACKUP_POWER1)
	wire["backup_2"] = !wire_is_cut(src, WIRE_BACKUP_POWER2)
	wire["shock"] = !wire_is_cut(src, WIRE_ELECTRIFY)
	wire["id_scanner"] = !wire_is_cut(src, WIRE_IDSCAN)
	wire["bolts"] = !wire_is_cut(src, WIRE_DOOR_BOLTS)
	wire["lights"] = !wire_is_cut(src, WIRE_BOLT_LIGHT)
	wire["safe"] = !wire_is_cut(src, WIRE_SAFETY)
	wire["timing"] = !wire_is_cut(src, WIRE_SPEED)
	data["wires"] = wire
	data["bolted"] = bolted
	data["electrified"] = electrified
	var/shock_left = 0
	for(var/source in held_by(src, STAT_ELECTRIFIED))
		var/left = hold_left(src, STAT_ELECTRIFIED, source)
		if(left == 0)
			shock_left = -1
			break
		shock_left = max(shock_left, left)
	data["electrified_left"] = shock_left > 0 ? round(shock_left / 10, 1) : (electrified ? -1 : 0)
	data["welded"] = weld_shut_welded(src)
	data["emergency"] = door_emergency_engaged(src)
	data["safe"] = !!safe
	data["speed"] = normalspeed
	return data

// ---- the touch ----

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

/// Someone holds the door: they stand by it, awake. A holder who walked off or fell lets go (hold_lapsed()).
/obj/machinery/door/airlock/proc/held_by_someone()
	var/mob/holder = hold_open()
	return holder && Adjacent(holder) && !holder.incapacitated()

/// The holder moved: once they are no longer beside the door, they let go of it.
/obj/machinery/door/airlock/proc/holder_moved(datum/act/A)
	var/datum/act/action/N = A
	var/mob/holder = N.target // the observed mob (the hook runs on this door)
	if(holder != hold_open())
		unobserve(holder, /datum/notice/moved, src)
		return
	if(!Adjacent(holder))
		unobserve(holder, /datum/notice/moved, src)
		rel_clear(src, nameof(hold_open))

/// The holder walked off or fell: they no longer hold the door.
/obj/machinery/door/airlock/proc/hold_lapsed()
	if(hold_open() && !held_by_someone())
		rel_clear(src, nameof(hold_open))

/// Anything held against the airlock touches it first (a phoron door ignites at a hot one).
/obj/machinery/door/airlock/proc/touched_early(datum/act/op/A)
	if(A.held && A.actor)
		touched_with(A.actor, A.held)
	return OP_OK

/// An item touched the airlock (before anything else it does). Subtypes react (phoron ignites).
/obj/machinery/door/airlock/proc/touched_with(mob/user, obj/item/held)
	return

/obj/machinery/door/airlock/proc/show_wires(datum/act/op/A)
	wires_open(src, A.actor)
	return OP_OK

/// A xeno's claws are on the hand.
/obj/machinery/door/airlock/proc/claws_tear(datum/act/op/A)
	var/mob/living/carbon/human/X = A.actor
	return !A.held && istype(X) && istype(X.species, /datum/species/xenos)

/// How long the tear takes: internals behind bolts or a weld, forcing a shut door, nothing for an open one (it is pushed shut).
/obj/machinery/door/airlock/proc/tear_wait(datum/act/A)
	if(bolted || weld_shut_welded(src))
		return 15 SECONDS
	if(density)
		return 5 SECONDS
	return 0

/obj/machinery/door/airlock/proc/tear_done(datum/act/op/A)
	var/mob/user = A.actor
	if(bolted || weld_shut_welded(src))
		act_message(user, src, others = span_alium("%U% tears %T% open, sparks flying from its electronics!"))
		do_animate("deny")
		do_animate("spark")
		play_sfx(src, SFX_MACHINES_DOOR_AIRLOCK_TEAR_APART, volume_channel = VOLUME_CHANNEL_DOORS)
		unbolt_unweld()
		open(TRUE)
		atom_break() //These aren't emags, these be CLAWS
	else if(density)
		play_sfx(src, SFX_MACHINES_DOOR_AIRLOCK_CREAKING, volume_channel = VOLUME_CHANNEL_DOORS)
		act_message(user, src, others = span_alium("%U% forces %T% open!"))
		open(TRUE)
	else
		act_message(user, src, others = span_danger("%U% forces %T% closed!"))
		close(TRUE)
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
	return istype(held) && held.pry && !held.has_tool_quality(TOOL_CROWBAR) && !power_systems_on() // ALLOW(reads): an item's pry is fixed for its life

/obj/machinery/door/airlock/proc/pry_weapon_forced(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	touched_early(A)
	if(bolted)
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
			close(TRUE)
	return OP_OK

/// A crowbar's force on a door that has lost its power and its bolts.

/// Why a crowbar cannot force the door now (a message), or null.
/obj/machinery/door/airlock/proc/pry_blocked(datum/act/A)
	if(power_systems_on())
		return /datum/msg/airlock/pry_motors
	if(bolted)
		return /datum/msg/airlock/pry_bolted
	return null

/obj/machinery/door/airlock/proc/pry_forced(datum/act/op/A)
	if(density)
		open(TRUE)
	else
		close(TRUE)
	return OP_OK

/obj/machinery/door/airlock/proc/panel_closable(datum/act/A)
	return (!(panel_open(src) && broken_now())) ? null : MSG(airlock/panel_broken)

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

/// A simple mob's smash on a door that lost its power: through bolts or a weld it breaks into the internals (an op, so it takes its time),
/// otherwise it forces the door open or shut at once.
/obj/machinery/door/airlock/proc/break_in_done(datum/act/op/A)
	unbolt_unweld()
	open(TRUE)
	if(prob(25))
		shock(A.actor, 100)
	return OP_OK

// ---- the ctrl-click: hammer, hold, bell ----

/obj/machinery/door/airlock/proc/hammer_on_door(datum/act/op/A)
	var/mob/user = A.actor
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	act_message(user, src, others = span_warning("%U% hammers on %T%!"), blind = span_warning("Someone hammers loudly on %T%!"))
	if(density && power_systems_on())
		flick("door_deny", src)
	playsound(src, knock_hammer_sound, 50, 0, 3)
	return OP_OK

/obj/machinery/door/airlock/proc/hold_door_open(datum/act/op/A)
	var/mob/user = A.actor
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	rel_set(src, nameof(hold_open), user)
	observe(user, /datum/notice/moved, src, then(PROC_REF(holder_moved)))
	act_message(user, src, others = span_info("%U% begins holding %T% open."), blind = span_info("Someone has started holding %T% open."))
	hold_release(user)
	toggle_by(user)
	return OP_OK

/// The bell on a powered door (a live one sparks), a knock on a dead one.
/obj/machinery/door/airlock/proc/ring_doorbell(datum/act/op/A)
	var/mob/user = A.actor
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	add_fingerprint(user)
	if(!power_systems_on())
		act_message(user, src, others = span_info("%U% knocks on %T%."), blind = span_info("Someone knocks on %T%."))
		playsound(src, knock_unpowered_sound, 50, 0, 3)
		return OP_OK
	if(electrified)
		act_message(user, src, others = span_warning("%U% presses the door bell on %T%, making it violently spark!"), blind = span_warning("%T% sparks!"))
		fx_sparks(src, 5)
	else
		act_message(user, src, others = span_info("%U% presses the door bell on %T%."), blind = span_info("%T%'s bell rings."))
	if(density)
		flick("door_deny", src)
	playsound(src, knock_sound, 50, 0, 3)
	return OP_OK

// ---- ice ----

// Runs on its own every(), declared only by the airlocks that can freeze (airlock_subtypes.dm), gated there by can_freeze().
/obj/machinery/door/airlock/proc/check_for_freeze(datum/act/A)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	// If we are not on a planet don't bother checking again. We physically cannot be outdoors. Except shuttles...
	var/area/our_area = get_area(src)
	var/turf/our_turf = get_turf(src)
	if(!our_turf || (!istype(our_area, /area/shuttle) && (our_turf.z > length(SSplanets.z_to_planet) || !SSplanets.z_to_planet[our_turf.z])))
		return
	if(operating)
		return
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
			set_frozen(TRUE)
	else if(planet_temp > T0C) // Above 0 to have any chance at unfreezing
		if(frozen && prob(20))
			set_frozen(FALSE)

/// Most airlocks don't freeze, subtypes set this
/obj/machinery/door/airlock/proc/can_freeze(datum/act/A)
	SHOULD_BE_PURE(TRUE) // Don't put logic here, just return if the airlock can freeze or not.
	PROTECTED_PROC(TRUE)
	return FALSE

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
			set_frozen(FALSE)
		return OP_OK
	// Melting with hot objects that don't take fuel
	if(held.is_hot())
		to_chat(user, span_notice("You finish melting the ice off \the [src]"))
		set_frozen(FALSE)
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
			set_frozen(FALSE)
			return OP_OK
	//if we can't de-ice the door tell them what's wrong.
	to_chat(user, span_notice("\the [src] is frozen shut!"))
	return OP_OK

// ---- the mechanism ----

/obj/machinery/door/airlock/get_material()
	if(mineral)
		return get_material_by_name(mineral)
	return get_material_by_name(MAT_STEEL)

// Power loss and electrification restore themselves on their own holds; the autoclose timer only keeps autoclose. An open door that cannot close
// drops it.
/obj/machinery/door/airlock/autoclose_due()
	if(!density && !operating && (bolted || weld_shut_welded(src) || !power_systems_on() || wire_is_cut(src, WIRE_OPEN_DOOR)))
		return
	return ..()

/obj/machinery/door/airlock/proc/resume_autoclose_if_possible()
	if(autoclose && !density && !operating && !bolted && !weld_shut_welded(src) && power_systems_on() && !wire_is_cut(src, WIRE_OPEN_DOOR))
		autoclose_in(next_close_wait())

/// An airlock's wires: twelve, or fourteen with secure electronics.
/obj/machinery/door/airlock/proc/wire_count()
	return secured_wires ? 14 : 12

/// Every airlock shares the round's colours, except one built with secure electronics.
/obj/machinery/door/airlock/proc/wires_randomized()
	return !!secured_wires

/obj/machinery/door/airlock/requiresID()
	return !(wire_is_cut(src, WIRE_IDSCAN) || aiDisabledIdScanner)

/// A mob walked into the door (the bump action, taken over before the door's own answer): a live door shocks a non-silicon (once a second), and
/// a hallucinating one may feel a phantom shock instead of the door opening. A bump that does neither goes on to the door's answer (door_bumped()).
/obj/machinery/door/airlock/proc/bump_shocks(datum/act/bump/A)
	var/mob/living/user = A.bumper
	if(!istype(user) || !bump_reaches_without_stamp(user))
		return HOOK_DECLINE
	return shocks_bumper(user) ? OP_OK : HOOK_DECLINE

/// The shock a mob walking or stumbling into the door takes: TRUE when it took one (or a phantom one), and the door does not open for it.
/obj/machinery/door/airlock/proc/shocks_bumper(mob/living/user)
	if(issilicon(user)) // a cyborg's chassis is insulated from the door
		return FALSE
	if(electrified)
		if(!COOLDOWN_FINISHED(src, bump_zap_cooldown))
			EXPIRY_STAMP(user, last_bumped, CLOCK_WORLD)
			return TRUE // the shock just fired: the bump does nothing
		if(shock(user, 100))
			EXPIRY_STAMP(user, last_bumped, CLOCK_WORLD)
			COOLDOWN_START(src, bump_zap_cooldown, 1 SECOND)
			return TRUE
		return FALSE
	if(user.status_units(STAT_HALLUCINATING) > 50 && prob(10) && operating == 0)
		EXPIRY_STAMP(user, last_bumped, CLOCK_WORLD)
		to_chat(user, span_danger("You feel a powerful shock course through your body!"))
		user.playsound_local(get_turf(user), get_sfx(SFX_SPARKS), vol = 75)
		user.injure(INJURY_PAIN, 10, null, src)
		user.status_adjust(STAT_STUNNED, 10)
		return TRUE
	return FALSE

/// A mech whose pilot may use the door asks its controller to report the door's state (a cycling airlock's sensors).
/obj/machinery/door/airlock/proc/mech_bumped_status(datum/act/A)
	var/datum/notice/bumped/N = A
	var/obj/mecha/mecha = N.bumper
	if(istype(mecha) && density && radio_connection() && mecha.slot_item(MECHA_SLOT_PILOT) && (allowed(mecha.slot_item(MECHA_SLOT_PILOT)) || check_access_list(mecha.operation_req_access)))
		send_status(1)

/// A simple mob that smashes an airlock which has lost its power: through bolts or a weld it breaks into the internals (an op, so it takes its time),
/// otherwise it forces the door open or shut at once. A door that works takes the smash as damage.
/obj/machinery/door/airlock/smashed_by(datum/act/hit/generic/A)
	var/mob/living/user = A.attacker
	var/damage = A.damage
	if(operable())
		return ..()
	if(damage < STRUCTURE_MIN_DAMAGE_THRESHOLD)
		act_message(user, src, others = span_notice("%U% strains fruitlessly to force %T% [density ? "open" : "closed"]."))
		return OP_OK
	if(bolted || weld_shut_welded(src))
		act_message(user, src, others = span_danger("%U% begins breaking into %T% internals!"))
		perform_op(user, src, "break_in", origin = ORIGIN_SYSTEM)
	else if(density)
		act_message(user, src, others = span_danger("%U% forces %T% open!"))
		open(TRUE)
	else
		act_message(user, src, others = span_danger("%U% forces %T% closed!"))
		close(TRUE)
	return OP_OK

/// A thrown metal thing striking a live door sparks.
/obj/machinery/door/airlock/door_thrown_at(datum/act/A)
	..()
	var/datum/notice/hit/N = A
	var/obj/item/thrown = N.packet?.source
	if(electrified && N.packet?.entry == DAMAGE_ENTRY_THROWN && istype(thrown))
		var/list/item_matter = thrown.material_totals()
		if(item_matter?[MAT_STEEL] > 0)
			fx_sparks(src, 5)

/// What a closing door crushes: everything standing in its tiles that takes the crush (airlock_crush()), for `amount` (the stock crush when null); the
/// door takes the same damage once per crushed thing.
/obj/machinery/door/airlock/proc/crush_contents(amount)
	var/dealt = isnull(amount) ? DOOR_CRUSH_DAMAGE : amount
	for(var/turf/T in locs)
		for(var/atom/movable/AM in contents_of(T))
			if(AM.airlock_crush(dealt))
				take_damage(dealt, BRUTE, MELEE)

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

	if(operating == -1 || (broken_now()))
		new /obj/item/circuitboard/broken(get_turf(src))
		set_operating(0)
	else
		if (!electronics) create_electronics()

		electronics.forceMove(get_turf(src))
		rel_take(src, nameof(electronics))
	replace_with(src, da)

/obj/machinery/door/airlock/proc/can_remove_electronics(datum/act/A)
	return !frozen && panel_open(src) && (operating < 0 || (!operating && weld_shut_welded(src) && !power_systems_on() && density && (!bolted || (broken_now()))))

/obj/machinery/door/airlock/on_broken()
	key_set(src, PANEL_OPEN, TRUE)
	if(secured_wires)
		drop_bolts(TRUE)
	visible_message("[name]'s control panel bursts open, sparks spewing out!")
	fx_sparks(src, 5)

/// The swing's noise, to each listener as their sound preferences choose: the legacy sounds, the department's, or the stock ones; an unpowered door
/// is forced, with no actuator.
/obj/machinery/door/airlock/proc/play_motion_sound(opening)
	var/powered = power_systems_on()
	var/turf/here = get_turf(src)
	for(var/mob/M in hearers(world.view * 2, here))
		if(!M.client)
			continue
		var/sound
		if(!powered)
			sound = open_sound_unpowered
		else if(M.read_preference(/datum/preference/toggle/old_door_sounds))
			sound = opening ? legacy_open_powered : legacy_close_powered
		else if(M.read_preference(/datum/preference/toggle/department_door_sounds) && (opening ? department_open_powered : department_close_powered))
			sound = opening ? department_open_powered : department_close_powered
		else
			sound = opening ? open_sound_powered : close_sound_powered
		var/volume = powered ? 50 : 75
		M.playsound_local(here, sound, volume, 1, null, 0, TRUE, sound(sound), volume_channel = VOLUME_CHANNEL_DOORS)

/obj/machinery/door/airlock/open(forced = 0)
	if(!can_open(forced))
		return FALSE
	if(frozen && !forced) //Frozen airlocks can't open.
		return FALSE
	if(frozen && forced)
		set_frozen(FALSE)
	use_power(AIRLOCK_ACTUATOR_POWER)
	if(hold_open())
		visible_message("[hold_open()] holds \the [src] open.")
	play_motion_sound(TRUE)
	SSmotiontracker.ping(src, 100)
	for(var/obj/machinery/door/airlock/other as anything in close_others)
		if(other != src && !other.density)
			other.close()
	. = ..()

/obj/machinery/door/airlock/can_open(forced = 0)
	if(!forced && (!power_systems_on() || wire_is_cut(src, WIRE_OPEN_DOOR)))
		return FALSE
	if(bolted || weld_shut_welded(src))
		return FALSE
	. = ..()

/// A predicate: it reads and writes nothing (close() lets go of a lapsed hold before it asks).
/obj/machinery/door/airlock/can_close(forced = 0)
	if(bolted || weld_shut_welded(src))
		return FALSE
	if(!forced && (held_by_someone() || !power_systems_on() || wire_is_cut(src, WIRE_OPEN_DOOR)))
		return FALSE
	. = ..()

/obj/machinery/door/airlock/close(forced = FALSE, ignore_safties = FALSE, crush_damage)
	if(!forced)
		hold_lapsed()
	if(!can_close(forced))
		return FALSE
	clear_autoclose_blockers()
	if(frozen && !forced)
		return FALSE
	if(frozen && forced) // Unfreeze on forced close
		set_frozen(FALSE)

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

	use_power(AIRLOCK_ACTUATOR_POWER)
	has_beeped = 0
	play_motion_sound(FALSE)
	SSmotiontracker.ping(src, 100)

	for(var/turf/turf in locs)
		var/obj/structure/window/killthis = (locate_within(turf, /obj/structure/window))
		if(killthis)
			killthis.ex_act(2)//Smashin windows
	. = ..()

/obj/machinery/door/airlock/allowed(mob/M)
	if(bolted)
		return FALSE
	. = ..()

/// The door's own req_access and req_one_access (a map varies them per door); emergency access lets anyone through.
/obj/machinery/door/airlock/check_access_list(list/L)
	if(door_emergency_engaged(src))
		return TRUE
	return ..()

/obj/machinery/door/airlock/can_pathfinding_enter(atom/movable/actor, dir, datum/pathfinding/search)
	return ..() || (has_access(req_access, req_one_access, search.ss13_with_access) && !bolted && operable())

/// The assembly a door is built from (its constructor param, dropped after init).
/obj/machinery/door/airlock/var/tmp/obj/structure/door_assembly/assembly_at_make

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). A door built from an assembly takes its electronics,
/// access, name and facing.
/obj/machinery/door/airlock/proc/build_from_assembly(obj/structure/door_assembly/assembly)
	if(!istype(assembly))
		return
	assembly_type = assembly.type
	var/obj/item/airlock_electronics/assembly_electronics = assembly.electronics
	assembly_electronics.forceMove(src)
	own_move(assembly_electronics, src, nameof(electronics)) // from the assembly to the door
	secured_wires = electronics.secure
	if(electronics.one_access)
		req_access = null
		req_one_access = electronics.conf_access
	else
		req_one_access = null
		req_access = electronics.conf_access
	name = assembly.created_name || "[istext(assembly.glass) ? "[assembly.glass] airlock" : assembly.base_name]"
	set_dir(assembly.dir)

// ALLOW(init/INSTANCE_STATE): a door on an admin level has secure wires, and every airlock joins its close group and tunes its radio
/obj/machinery/door/airlock/Initialize(mapload)
	// A door on an admin level gets the secure wires (wire_count(), wires_randomized()), made on first use.
	var/turf/T = get_turf(src)
	if(T && (T.z in using_map.admin_levels))
		secured_wires = 1
	. = ..()
	join_close_group()
	name = "\improper [name]"
	if(frequency)
		set_frequency(frequency)

/// The airlocks of each closeOtherId, so a door joins its group at init without a scan of every machine (an airlock is keyed by its id_tag
/// already, and a type has one key var: this index is the second key).
GLOBAL_LIST_EMPTY(airlock_close_groups) // closeOtherId -> the airlocks sharing it; each leaves it in on_destroy()

/// Links this airlock both ways with every airlock that shares its closeOtherId.
/obj/machinery/door/airlock/proc/join_close_group()
	if(isnull(closeOtherId))
		return
	for(var/obj/machinery/door/airlock/other as anything in LAZYACCESS(GLOB.airlock_close_groups, closeOtherId))
		rel_add(src, nameof(close_others), other)
		rel_add(other, nameof(close_others), src)
	LAZYADDASSOCLIST(GLOB.airlock_close_groups, closeOtherId, src)

/obj/machinery/door/airlock/on_destroy(force)
	if(!isnull(closeOtherId))
		LAZYREMOVEASSOC(GLOB.airlock_close_groups, closeOtherId, src)
	..()

// Most doors will never be deconstructed over the course of a round, so as an optimization defer the creation of electronics until the airlock is
// deconstructed
/obj/machinery/door/airlock/proc/create_electronics()
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

/// hold open (a relation view: it reads null once the target is deleted).
/obj/machinery/door/airlock/proc/hold_open() as /mob
	return hold_open

// ---- the look ----

/obj/machinery/door/airlock/draw(datum/look/look)
	..()
	// doorint.dmi and its kin have no wires, broken or dark states: the sparks below show damage. The bolts show as
	// door_locked (below) and emergency access has no sprite of its own.
	look.hide(LOOK_WIRES)
	look.hide(LOOK_BROKEN)
	look.hide(LOOK_DARK)
	look.hide(LOOK_BOLTS)
	look.hide(LOOK_EMERGENCY)
	var/powered = !power_lost()
	var/damaged = get_integrity() < max_integrity * 3/4
	if(density)
		look.state((bolted && lights && power_systems_on()) ? "door_locked" : "door_closed")
		if(panel_open(src) || weld_shut_welded(src))
			if(powered)
				if(broken_now())
					look.overlay("sparks_broken")
				else if(damaged)
					look.overlay("sparks_damaged")
		else if(damaged && powered)
			look.overlay("sparks_damaged")
	else
		look.hide(LOOK_PANEL_OPEN)
		look.hide("welded")
		look.state(open_state())
		look.overlay("sparks_open", when = broken_now() && powered)
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
			if(density && power_systems_on())
				flick("door_deny", src)
				playsound(src, denied_sound, 50, 0, 3)

// ---- what a closing airlock does to what is in its way ----

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
	status_set(STAT_STUNNED, 5)
	status_set(STAT_WEAKENED, 5)
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

// ---- the wires ----
//
// The capabilities that own their state bring five wires (code/library/machine/wire_caps.dm, door_parts.dm); the airlock's own hooks below add
// what else a wire does to it.
//	ID scanner    pulse: the red light flashes. Cut: the door stops asking for an ID (id_scan()).
//	main power    pulse: the breaker trips for a minute (the backup carries the door after ten seconds). Cut: main power is out until mended. Either may shock.
//	backup power  pulse: its breaker trips for a minute. Cut: no backup until mended. Either may shock.
//	bolts         pulse: drops raised bolts, raises dropped ones (with power). Cut: drops them; mending does not raise them.
//	open door     pulse: opens or shuts a door that asks no ID (not an emagged one).
//	AI control    pulse: silicons are locked out for a second. Cut: until mended (ai_control()).
//	electrify     pulse: thirty seconds of current. Cut: current until mended.
//	safety        pulse: flips the safeties (an open door shuts). Cut: no safeties until mended.
//	timing        pulse: flips the speed. Cut: no autoclose until mended (an open door shuts then).
//	bolt lights   pulse: flips the lights. Cut: dark until mended.

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
	var/haspower = power_systems_on() // no power, no lights
	return list(
		"The door bolts [bolted ? "have fallen!" : "look up."]",
		"The door bolt lights are [(lights && haspower) ? "on." : "off!"]",
		"The test light is [haspower ? "on." : "off!"]",
		"The backup power light is [backup_carries() ? "on." : "off!"]",
		"The 'AI control allowed' light is [(!aiControlDisabled && !emag_emagged(src) && haspower) ? "on" : "off"].",
		"The 'Check Wiring' light is [(!safe && haspower) ? "on" : "off"].",
		"The 'Check Timing Mechanism' light is [(!normalspeed && haspower) ? "on" : "off"].",
		"The IDScan light is [(!aiDisabledIdScanner && haspower) ? "on" : "off."]")

/// Reaching into a live door's wires shocks anyone but a silicon, instead.
/obj/machinery/door/airlock/proc/wire_touch_shocks(datum/act/A)
	var/datum/act/touch_wires/T = A
	if(!issilicon(T.user) && electrified && shock(T.user, 100)) // ALLOW(silicon_entry): moved from the deleted airlock wire datum unchanged: a silicon reaches the wires window with no hand on a live wire
		return OP_REFUSED
	return HOOK_DECLINE

/// Any wire moved: the door's look and panel follow it.
/obj/machinery/door/airlock/proc/wire_changed_look(datum/act/A)
	changed(src)

/// The ID wire pulsed flashes the red light (with power, while shut).
/obj/machinery/door/airlock/proc/idscan_wire_pulsed(datum/act/A)
	if(power_systems_on() && density)
		do_animate("deny")

/// A main power cable cut takes main power out until both are whole; mending the last frees it at once. Either may shock the hand.
/obj/machinery/door/airlock/proc/main_power_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(main_cables_cut())
		main_power_goes(SRC_POWER_WIRE)
	else
		release(src, STAT_MAIN_POWER_OUT, SRC_ALL)
	shock(N.user, 50)

/// A main power pulse trips its breaker.
/obj/machinery/door/airlock/proc/main_power_wire_pulsed(datum/act/A)
	lose_main_power()

/obj/machinery/door/airlock/proc/backup_power_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	if(backup_cables_cut())
		hold(src, STAT_BACKUP_POWER_OUT, TRUE, SRC_POWER_WIRE)
	else
		release(src, STAT_BACKUP_POWER_OUT, SRC_POWER_WIRE)
		release(src, STAT_BACKUP_POWER_OUT, SRC_BREAKER)
	shock(N.user, 50)

/obj/machinery/door/airlock/proc/backup_power_wire_pulsed(datum/act/A)
	lose_backup_power()

/// The door-open wire pulsed opens or shuts a door that asks no ID (or whose ID wire is cut), unless it is emagged.
/obj/machinery/door/airlock/proc/open_wire_pulsed(datum/act/A)
	if(emag_emagged(src))
		return
	if(!requiresID() || check_access(null))
		if(density)
			open()
		else
			close()

/// The safety wire pulsed (safety_wire() flipped the safeties): an open door shuts.
/obj/machinery/door/airlock/proc/safety_wire_pulsed(datum/act/A)
	if(!density)
		close()

/// The timing wire cut stops the autoclose; mended, it autocloses again (an open door shuts).
/obj/machinery/door/airlock/proc/speed_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	set_autoclose(N.mended)
	if(N.mended && !density)
		close()

/obj/machinery/door/airlock/proc/speed_wire_pulsed(datum/act/A)
	set_normalspeed(!normalspeed)

/obj/machinery/door/airlock/proc/bolt_light_wire_cut(datum/act/A)
	var/datum/notice/wire_cut/N = A
	set_lights(N.mended)

/obj/machinery/door/airlock/proc/bolt_light_wire_pulsed(datum/act/A)
	set_lights(!lights)

#undef AIRLOCK_ACTUATOR_POWER

/obj/machinery/door/airlock/proc/backup_available(datum/act/A)
	return backup_carries(A) ? null : MSG(airlock/backup_offline)

/obj/machinery/door/airlock/proc/power_available(datum/act/A)
	return power_systems_on(A) ? null : MSG(airlock/unpowered)
