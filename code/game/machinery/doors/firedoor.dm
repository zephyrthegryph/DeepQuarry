#define FIREDOOR_MAX_PRESSURE_DIFF 25 // kPa
// Bitflags
#define FIREDOOR_ALERT_HOT		1
#define FIREDOOR_ALERT_COLD		2
// Not used #define FIREDOOR_ALERT_LOWPRESS 4

/obj/machinery/door/firedoor
	/// Optional generated-turbolift owner; ordinary mapped firedoors leave null.
	var/datum/turbolift_floor/turbolift_floor
	name = "\improper Emergency Shutter"
	desc = "Emergency air-tight shutter, capable of sealing off breached areas."
	icon = 'icons/obj/doors/DoorHazard.dmi'
	icon_state = "door_open"
	req_one_access = list(ACCESS_EVA)	//ACCESS_ATMOSPHERICS, ACCESS_ENGINE_EQUIP)
	opacity = 0
	density = FALSE
	layer = DOOR_OPEN_LAYER - 0.01
	open_layer = DOOR_OPEN_LAYER - 0.01 // Just below doors when open
	closed_layer = DOOR_CLOSED_LAYER + 0.01 // Just above doors when closed

	//These are frequenly used with windows, so make sure zones can pass.
	//Generally if a firedoor is at a place where there should be a zone boundery then there will be a regular door underneath it.
	block_air_zones = 0
	heat_proof = 1

	var/blocked = 0
	var/lockdown = 0 // When the door has detected a problem, it locks.
	var/pdiff_alert = 0
	var/pdiff = 0
	var/nextstate = null
	var/net_id
	var/list/areas_added
	/// The mixture ids of the air watches a shut door has armed (null while it has none).
	var/list/datum/native_watch/gas/air_watches
	var/sleeping_signature
	var/datum/gas_mixture/dependency_air_0
	var/air_hot_0 = FALSE
	var/air_cold_0 = FALSE
	var/datum/gas_mixture/dependency_air_1
	var/air_hot_1 = FALSE
	var/air_cold_1 = FALSE
	var/datum/gas_mixture/dependency_air_2
	var/air_hot_2 = FALSE
	var/air_cold_2 = FALSE
	var/datum/gas_mixture/dependency_air_3
	var/air_hot_3 = FALSE
	var/air_cold_3 = FALSE
	var/datum/gas_mixture/dependency_air_4
	var/air_hot_4 = FALSE
	var/air_cold_4 = FALSE
	/// Lazy list of names who opened this door during an alert.
	var/list/users_to_open

	var/hatch_open = 0

	power_channel = ENVIRON
	use_power = USE_POWER_IDLE
	idle_power_usage = 5

	/// Lazy: 4 cardinal dirs of FIREDOOR_ALERT_* bitflags, null while no direction alerts.
	var/list/dir_alerts

	// MUST be in same order as FIREDOOR_ALERT_*
	var/static/list/ALERT_STATES=list(
		"hot",
		"cold"
	)
	var/open_sound = SFX_MACHINES_FIRELOCKOPEN // firedoor sound variable.
	var/close_sound = SFX_MACHINES_FIRELOCKCLOSE // firedoor sound variable.
TRACKED(/obj/machinery/door/firedoor, air_hot_0)
TRACKED(/obj/machinery/door/firedoor, air_cold_0)
TRACKED(/obj/machinery/door/firedoor, air_hot_1)
TRACKED(/obj/machinery/door/firedoor, air_cold_1)
TRACKED(/obj/machinery/door/firedoor, air_hot_2)
TRACKED(/obj/machinery/door/firedoor, air_cold_2)
TRACKED(/obj/machinery/door/firedoor, air_hot_3)
TRACKED(/obj/machinery/door/firedoor, air_cold_3)
TRACKED(/obj/machinery/door/firedoor, air_hot_4)
TRACKED(/obj/machinery/door/firedoor, air_cold_4)
TRACKED(/obj/machinery/door/firedoor, dir_alerts)
TRACKED(/obj/machinery/door/firedoor, pdiff_alert)

TRACKED(/obj/machinery/door/firedoor, blocked)
TRACKED(/obj/machinery/door/firedoor, hatch_open)

/obj/machinery/door/firedoor/Initialize(mapload)
	. = ..()
	//Delete ourselves if we find extra mapped in firedoors
	for(var/obj/machinery/door/firedoor/F in contents_of(loc))
		if(F != src)
			log_mapping("Duplicate firedoors at [x],[y],[z]")
			return INITIALIZE_HINT_QDEL

	var/area/A = get_area(src)
	ASSERT(istype(A))

	LAZYADD(A.all_doors, src)
	areas_added = list(A)

	for(var/direction in GLOB.cardinal)
		A = get_area(get_step(src,direction))
		if(istype(A) && !(A in areas_added))
			LAZYADD(A.all_doors, src)
			areas_added += A

/// Phase 2: leaves the door lists of every area it guards.
/obj/machinery/door/firedoor/lifecycle_dematerialize()
	. = ..()
	for(var/area/A in areas_added)
		LAZYREMOVE(A.all_doors, src)

/obj/machinery/door/firedoor/get_material()
	return get_material_by_name(MAT_STEEL)

/obj/machinery/door/firedoor/examine(mob/user)
	. = ..()

	if(!Adjacent(user))
		return .

	if(pdiff >= FIREDOOR_MAX_PRESSURE_DIFF)
		. += span_warning("WARNING: Current pressure differential is [pdiff]kPa! Opening door may result in injury!")

	. += span_bold("Sensor readings:")
	var/list/tile_info = getCardinalAirInfo(src.loc, list("temperature", "pressure"))
	for(var/index = 1; index <= tile_info.len; index++)
		var/o = "&nbsp;&nbsp;"
		switch(index)
			if(1)
				o += "NORTH: "
			if(2)
				o += "SOUTH: "
			if(3)
				o += "EAST: "
			if(4)
				o += "WEST: "
		if(tile_info[index] == null)
			o += span_warning("DATA UNAVAILABLE")
			. += o
			continue
		var/celsius = convert_k2c(tile_info[index][1])
		var/pressure = tile_info[index][2]
		var/temperature_string = "[celsius]&deg;C "
		o += ((LAZYACCESS(dir_alerts, index) & (FIREDOOR_ALERT_HOT|FIREDOOR_ALERT_COLD)) ? span_warning(temperature_string) : span_blue(temperature_string))
		o += span_blue("[pressure]kPa")
		o += "</li>"
		. += o

	if(islist(users_to_open) && users_to_open.len)
		var/users_to_open_string = users_to_open[1]
		if(users_to_open.len >= 2)
			for(var/i = 2 to users_to_open.len)
				users_to_open_string += ", [users_to_open[i]]"
		. += "These people have opened \the [src] during an alert: [users_to_open_string]."

// ---- what a firedoor is, declared ----
//
// A shutter that closes itself on an alarm and opens by a question: using it by hand asks whether to open or close it (opening it in an alarm is on
// the one who does, and is remembered), a card or another held thing works it like any door, and a weld holds it shut. What is the firedoor's own:
// the prompt, a welder's seam, the maintenance hatch a screwdriver opens on a closed one (and, welded, a crowbar takes the electronics out of it),
// a crowbar or an axe forcing it when it has no power or is open, and a claw or a smashing animal forcing it whatever holds it. Whatever works on
// a firedoor that is mid-swing is swallowed, and a welded one takes nothing that is not a tool.
//
// The tiers of the held-thing ops (from the top): the emag, the swallow of a busy door, the tools, tape, the weld's refusal, the axe's force; the
// base door's strike and the doors() touch sit below them.

MSG_DEF_SELF(firedoor/welded_solid, "It is welded solid!")
MSG_DEF_SELF(firedoor/welded_shut, "It is welded shut!")
MSG_DEF_SELF(firedoor/unable, "Sorry, you must remain able bodied in order to use it.")
MSG_DEF_SELF(firedoor/dead, "It is not functioning, you'll have to force it open manually.")
MSG_DEF_SELF(firedoor/locked_out, "Access denied. Please wait for authorities to arrive, or for the alert to clear.")
MSG_DEF_SELF(firedoor/hatch_first, "You must open the maintenance hatch first!")
MSG_DEF_SELF(firedoor/motors_resist, "Its motors resist your effort.")
MSG_DEF_SELF(firedoor/need_wield, "You need to be wielding that to do that.")
MSG_DEF_SELF(firedoor/busy_prying, "Someone's busy prying at it!")

CAPABILITIES(/obj/machinery/door/firedoor)
	owns_many(nameof(air_watches), /datum/native_watch/gas)
	ref_one(nameof(dependency_air_0), /datum/gas_mixture)
	gas_level(into = nameof(air_hot_0), reading = CH_GAS_TEMPERATURE, above = convert_c2k(FIREDOOR_MAX_TEMP - 0.01), hysteresis = 0, air = nameof(dependency_air_0))
	on_change(nameof(air_hot_0), ANY, then(PROC_REF(temperature_level_changed)))
	gas_level(into = nameof(air_cold_0), reading = CH_GAS_TEMPERATURE, below = convert_c2k(FIREDOOR_MIN_TEMP + 0.01), hysteresis = 0, air = nameof(dependency_air_0))
	on_change(nameof(air_cold_0), ANY, then(PROC_REF(temperature_level_changed)))
	ref_one(nameof(dependency_air_1), /datum/gas_mixture)
	gas_level(into = nameof(air_hot_1), reading = CH_GAS_TEMPERATURE, above = convert_c2k(FIREDOOR_MAX_TEMP - 0.01), hysteresis = 0, air = nameof(dependency_air_1))
	on_change(nameof(air_hot_1), ANY, then(PROC_REF(temperature_level_changed)))
	gas_level(into = nameof(air_cold_1), reading = CH_GAS_TEMPERATURE, below = convert_c2k(FIREDOOR_MIN_TEMP + 0.01), hysteresis = 0, air = nameof(dependency_air_1))
	on_change(nameof(air_cold_1), ANY, then(PROC_REF(temperature_level_changed)))
	ref_one(nameof(dependency_air_2), /datum/gas_mixture)
	gas_level(into = nameof(air_hot_2), reading = CH_GAS_TEMPERATURE, above = convert_c2k(FIREDOOR_MAX_TEMP - 0.01), hysteresis = 0, air = nameof(dependency_air_2))
	on_change(nameof(air_hot_2), ANY, then(PROC_REF(temperature_level_changed)))
	gas_level(into = nameof(air_cold_2), reading = CH_GAS_TEMPERATURE, below = convert_c2k(FIREDOOR_MIN_TEMP + 0.01), hysteresis = 0, air = nameof(dependency_air_2))
	on_change(nameof(air_cold_2), ANY, then(PROC_REF(temperature_level_changed)))
	ref_one(nameof(dependency_air_3), /datum/gas_mixture)
	gas_level(into = nameof(air_hot_3), reading = CH_GAS_TEMPERATURE, above = convert_c2k(FIREDOOR_MAX_TEMP - 0.01), hysteresis = 0, air = nameof(dependency_air_3))
	on_change(nameof(air_hot_3), ANY, then(PROC_REF(temperature_level_changed)))
	gas_level(into = nameof(air_cold_3), reading = CH_GAS_TEMPERATURE, below = convert_c2k(FIREDOOR_MIN_TEMP + 0.01), hysteresis = 0, air = nameof(dependency_air_3))
	on_change(nameof(air_cold_3), ANY, then(PROC_REF(temperature_level_changed)))
	ref_one(nameof(dependency_air_4), /datum/gas_mixture)
	gas_level(into = nameof(air_hot_4), reading = CH_GAS_TEMPERATURE, above = convert_c2k(FIREDOOR_MAX_TEMP - 0.01), hysteresis = 0, air = nameof(dependency_air_4))
	on_change(nameof(air_hot_4), ANY, then(PROC_REF(temperature_level_changed)))
	gas_level(into = nameof(air_cold_4), reading = CH_GAS_TEMPERATURE, below = convert_c2k(FIREDOOR_MIN_TEMP + 0.01), hysteresis = 0, air = nameof(dependency_air_4))
	on_change(nameof(air_cold_4), ANY, then(PROC_REF(temperature_level_changed)))
	ref_one(nameof(turbolift_floor), /datum/turbolift_floor)
	op("busy", inputs(hand(), item(/obj/item)), priority(OP_PRIORITY_CLAW + 8), when(nameof(operating)), wait(0), then(PROC_REF(nothing_done)))
	op("use", hand(), label("Use"), priority(OP_PRIORITY_PART), wait(0),
		needs(req_is(nameof(blocked), FALSE, because = MSG(firedoor/welded_solid)), req_capable(), req_bool(PROC_REF(can_work), because = MSG(firedoor/dead)),
			req_bool(PROC_REF(not_locked_out), because = MSG(firedoor/locked_out))),
		asks(/datum/prompt/yes_no, fields = list("question" = computed(PROC_REF(use_question)), "yes_text" = computed(PROC_REF(use_yes)))), then(PROC_REF(used)))
	// A silicon link and a pilot bump ask the same question by this key.
	op("remote_use", remote(), wait(0),
		needs(req_is(nameof(blocked), FALSE, because = MSG(firedoor/welded_solid)), req_capable(), req_bool(PROC_REF(can_work), because = MSG(firedoor/dead)),
			req_bool(PROC_REF(not_locked_out), because = MSG(firedoor/locked_out))),
		asks(/datum/prompt/yes_no, fields = list("question" = computed(PROC_REF(use_question)), "yes_text" = computed(PROC_REF(use_yes)))), then(PROC_REF(used)))
	op("force_claws", hand(), label("Force"), when(req_bool(PROC_REF(claws_force))), priority(OP_PRIORITY_TAKE_OUT), wait(PROC_REF(claws_wait)), then(PROC_REF(claws_forced)))
	op("force_generic", ai(), wait(PROC_REF(generic_wait)), then(PROC_REF(generic_forced)))
	op("tape", item(/obj/item/taperoll), priority(OP_PRIORITY_CLAW + 5), wait(0), then(PROC_REF(nothing_done)))
	op("welded", item(/obj/item), priority(OP_PRIORITY_CLAW + 4), when(nameof(blocked)), wait(0),
		needs(req_is(nameof(blocked), FALSE, because = MSG(firedoor/welded_shut))), then(PROC_REF(nothing_done)))
	op("pry", item(/obj/item), label("Force"), when(req_bool(PROC_REF(prying_item))), priority(OP_PRIORITY_CLAW + 3), wait(3 SECONDS), claims(),
		needs(req_bool(PROC_REF(wielded_if_axe), because = MSG(firedoor/need_wield))), then(PROC_REF(item_forced)))
	op("weld", tool(TOOL_WELDER), label("Weld"), when(cond_not(PROC_REF(repairable))), priority(OP_PRIORITY_CLAW + 6), wait(0), costs(RES_FUEL, 0),
		needs(req_unclaimed(because = MSG(firedoor/busy_prying))), then(PROC_REF(weld_toggled)))
	op("hatch", tool(TOOL_SCREWDRIVER), label("Maintenance hatch"), when(nameof(density)), priority(OP_PRIORITY_CLAW + 6), wait(0), then(PROC_REF(hatch_toggled)))
	op("remove_electronics", tool(TOOL_CROWBAR), label("Remove electronics"), when(nameof(blocked)), priority(OP_PRIORITY_CLAW + 6), wait(3 SECONDS),
		needs(req_bool(PROC_REF(hatch_reachable), because = MSG(firedoor/hatch_first))), then(PROC_REF(electronics_out)))
	op("pry_tool", tool(TOOL_CROWBAR), label("Force"), when(cond_not(nameof(blocked))), priority(OP_PRIORITY_CLAW + 6), wait(3 SECONDS), claims(),
		needs(req_bool(PROC_REF(pry_free), because = MSG(firedoor/motors_resist))), then(PROC_REF(tool_forced)))

/// An op that only swallows the touch (a busy door, tape, a welded door's refusal): nothing happens.
/obj/machinery/door/firedoor/proc/nothing_done(datum/act/op/A)
	return OP_OK

// ---- using it by hand ----

/// A fire alarm in any area it guards, or its own lockdown.
/obj/machinery/door/firedoor/proc/alarmed()
	if(lockdown)
		return TRUE
	for(var/area/A in areas_added)
		if(A.firedoors_closed) // ALLOW(reads): an area's alarm flag is read when the door is used and again when the question is answered
			return TRUE
	return FALSE

/// It is not a shut door with no power (a shut door with none must be forced; one that is open can still be closed).
/obj/machinery/door/firedoor/proc/can_work(datum/act/A)
	return !density || operable()

/// An alarm, a lockdown and no access keep a shut door shut (for whoever has no access).
/obj/machinery/door/firedoor/proc/not_locked_out(datum/act/op/A)
	return !(density && lockdown && alarmed() && !allowed(A.actor)) // ALLOW(reads): the alarm and the lockdown are read when the question is asked and again when it is answered

/// What is asked: to open or close it, with the warning that opening it in an alarm is on whoever does.
/// The yes button names what it does.
/obj/machinery/door/firedoor/proc/use_yes(datum/act/A)
	return "Yes, [density ? "open" : "close"]"

/obj/machinery/door/firedoor/proc/use_question(datum/act/A)
	var/doing = density ? "open" : "close"
	return "Would you like to [doing] this [name]?[ alarmed() && density ? "\nNote that by doing so, you acknowledge any damages from opening this\n[name] as being your own fault, and you will be held accountable under the law." : ""]"

/// The answer was yes: it opens (the one who opened it in an alarm is remembered and, unless a silicon, it closes again in five seconds) or closes.
/obj/machinery/door/firedoor/proc/used(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	act_message(user, src, MSG_SELF("%T% [density ? "open" : "close"]s."), \
		MSG_OTHERS(span_notice("%T% [density ? "open" : "close"]s for %U%.")), \
		MSG_BLIND("You hear a beep, and a door opening."))
	var/needs_to_close = FALSE
	if(density)
		if(alarmed())
			// Accountability!
			LAZYOR(users_to_open, user.name)
			needs_to_close = !issilicon(user)
		open()
	else
		close()
	if(needs_to_close)
		after(src, 5 SECONDS, PROC_REF(autoclose_check), key = "reclose", clock = CLOCK_WORLD)
	return OP_OK

/// A pilot's mecha bumping a shut one asks the pilot.
/obj/machinery/door/firedoor/door_bumped(datum/act/A)
	var/datum/notice/bumped/N = A
	var/atom/movable/AM = N.bumper
	if(panel_is_open(src) || operating)
		return
	if(!density)
		return ..()
	if(istype(AM, /obj/mecha))
		var/obj/mecha/mecha = AM
		if(mecha?.slot_item(MECHA_SLOT_PILOT))
			var/mob/M = mecha?.slot_item(MECHA_SLOT_PILOT)
			if(ELAPSED(M, last_bumped, CLOCK_WORLD) <= 1 SECOND) return //Can bump-open one airlock per second. This is to prevent popup message spam.
			EXPIRY_STAMP(M, last_bumped, CLOCK_WORLD)
			perform_op(M, src, "remote_use", origin = ORIGIN_SYSTEM)
	return 0

// ---- forcing it ----

/// A xeno's claws are on the hand.
/obj/machinery/door/firedoor/proc/claws_force(datum/act/op/A)
	var/mob/living/carbon/human/X = A.actor
	return !A.held && istype(X) && istype(X.species, /datum/species/xenos)

/// Claws dig into a welded one for five seconds, force a shut one open for two and push an open one shut at once.
/obj/machinery/door/firedoor/proc/claws_wait(datum/act/A)
	if(blocked)
		return 5 SECONDS
	if(density)
		return 2 SECONDS
	return 0

/obj/machinery/door/firedoor/proc/claws_forced(datum/act/op/A)
	var/mob/user = A.actor
	if(blocked)
		act_message(user, src, others = span_alium("%U% digs into %T% internals!"))
		play_sfx(src, SFX_MACHINES_DOOR_AIRLOCK_CREAKING)
		set_blocked(0)
		force_open_by(user)
	else if(density)
		play_sfx(src, SFX_MACHINES_DOOR_AIRLOCK_CREAKING)
		act_message(user, src, others = span_danger("%U% forces %T% open!"))
		force_open_by(user)
	else
		act_message(user, src, others = span_danger("%U% forces %T% closed!"))
		close(1)
	return OP_OK

/// A simple mob smashing at one that has lost its power: a strong one forces it (a second, two when welded; half that to shut), a weak one strains for nothing.
/// A door that works takes the smash as damage.
/obj/machinery/door/firedoor/smashed_by(datum/act/hit/generic/A)
	var/mob/living/user = A.attacker
	var/damage = A.damage
	if(!operable())
		if(damage >= STRUCTURE_MIN_DAMAGE_THRESHOLD)
			act_message(user, src, others = span_danger("%U% starts forcing %T% [density ? "open" : "closed"]!"))
			perform_op(user, src, "force_generic", origin = ORIGIN_SYSTEM)
		else
			act_message(user, src, others = span_notice("%U% strains fruitlessly to force %T% [density ? "open" : "closed"]."))
		return OP_OK
	return ..()

/obj/machinery/door/firedoor/proc/generic_wait(datum/act/A)
	var/time_to_force = (2 + (2 * blocked)) * 5
	return density ? time_to_force : time_to_force / 2

/obj/machinery/door/firedoor/proc/generic_forced(datum/act/op/A)
	var/mob/user = A.actor
	if(density)
		act_message(user, src, others = span_danger("%U% forces %T% open!"))
		set_blocked(0)
		force_open_by(user)
	else
		act_message(user, src, others = span_danger("%U% forces %T% closed!"))
		close(1)
	return OP_OK

/// A thing in hand that pries and is no crowbar tool (a fireaxe, a blade).
/obj/machinery/door/firedoor/proc/prying_item(datum/act/op/A)
	var/obj/item/held = A.held
	return istype(held) && held.pry == 1 // ALLOW(reads): an item's pry is fixed for its life

/// A fireaxe must be held in both hands to pry; anything else does not care.
/obj/machinery/door/firedoor/proc/wielded_if_axe(datum/act/op/A)
	var/obj/item/material/twohanded/fireaxe/F = A.held
	return !istype(F) || F.wielded // ALLOW(reads): whether an axe is wielded is read when the pry is tried

/// An axe or a blade has forced it (a welded one too: the seam gives).
/obj/machinery/door/firedoor/proc/item_forced(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/C = A.held
	act_message(user, src, MSG_SELF("You force \the [ blocked ? "welded" : "" ] %T% [density ? "open" : "closed"] with %I%!"), \
		MSG_OTHERS(span_danger("%U% forces \the [ blocked ? "welded" : "" ] %T% [density ? "open" : "closed"] with \a [C]!")), \
		MSG_BLIND("You hear metal strain and groan, and a door [density ? "opening" : "closing"]."), \
		item = C)
	if(density)
		force_open_by(user)
	else
		close()
	return OP_OK

/// A crowbar works a door with no power, or an open one.
/obj/machinery/door/firedoor/proc/pry_free(datum/act/A)
	return !operable() || !density

/obj/machinery/door/firedoor/proc/tool_forced(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	act_message(user, src, MSG_SELF("You force %T% [density ? "open" : "closed"] with %I%!"), \
		MSG_OTHERS(span_danger("%U% forces %T% [density ? "open" : "closed"] with \a [tool]!")), \
		MSG_BLIND("You hear metal strain, and a door [density ? "open" : "close"]."), \
		item = tool)
	if(density)
		force_open_by(user)
	else
		close()
	return OP_OK

// ---- the seam, the hatch, the electronics ----

/// A welder welds it shut or frees it.
/obj/machinery/door/firedoor/proc/weld_toggled(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/weldingtool/welder = A.held.get_welder()
	set_blocked(!blocked)
	act_message(user, src, MSG_SELF("You [blocked ? "weld" : "unweld"] %T% with %I%."), \
		MSG_OTHERS(span_danger("%U% [blocked ? "welds" : "unwelds"] %T% with \a [welder].")), \
		MSG_BLIND("You hear something being welded."), \
		item = welder)
	playsound(src, welder.usesound, 100, TRUE)
	return OP_OK

/// A screwdriver opens or closes the maintenance hatch of a shut door.
/obj/machinery/door/firedoor/proc/hatch_toggled(datum/act/op/A)
	var/mob/user = A.actor
	set_hatch_open(!hatch_open)
	playsound(src, A.held.usesound, 50, TRUE)
	act_message(user, src, MSG_SELF("You have [hatch_open ? "opened" : "closed"] %T% maintenance hatch."), \
		MSG_OTHERS(span_danger("%U% has [hatch_open ? "opened" : "closed"] %T% maintenance hatch.")))
	return OP_OK

/// The hatch is open on a shut door (the electronics can be reached).
/obj/machinery/door/firedoor/proc/hatch_reachable(datum/act/A)
	return blocked && density && hatch_open

/// A crowbar takes the electronics out of a welded, shut door with its hatch open: an assembly stands where it was.
/obj/machinery/door/firedoor/proc/electronics_out(datum/act/op/A)
	var/mob/user = A.actor
	playsound(src, A.held.usesound, 50, TRUE)
	act_message(user, src, MSG_SELF("You have removed the electronics from %T%."), MSG_OTHERS(span_danger("%U% has removed the electronics from %T%.")))
	if(broken_now())
		new /obj/item/circuitboard/broken(loc)
	else
		new /obj/item/circuitboard/airalarm(loc)
	var/obj/structure/firedoor_assembly/assembly = new(loc)
	assembly.set_anchored(TRUE)
	assembly.set_density(TRUE)
	graph_place(assembly, STAGE_FIREDOOR_ASSEMBLY_WIRED)
	assembly.set_glass(glass)
	replace_with(src, assembly)
	return OP_OK

// ---- the air it guards ----

/// A door that shuts reads the air once and then waits on it: an open one watches nothing.
/obj/machinery/door/firedoor/set_density(new_density)
	. = ..()
	if(.)
		density_changed()

/obj/machinery/door/firedoor/proc/density_changed()
	if(density)
		air_check()
		hibernate_until_air_changes()
	else
		clear_gas_dependencies()

/// Arms native gas watches per distinct mixture of the dependency turfs (the door's own plus its four cardinal neighbours), all sharing
/// firedoor_atmos_signature() as their getter: whichever one notices a change first recomputes the full signature and wakes the door if it
/// actually crossed a pressure or temperature band edge, not on every harmless diffusion tick. A shut door never polls the air.
/obj/machinery/door/firedoor/proc/hibernate_until_air_changes()
	clear_gas_dependencies()
	var/list/dependency_turfs = list(get_turf(src))
	for(var/direction in GLOB.cardinal)
		dependency_turfs += get_step(src, direction)
	var/list/mixtures = list()
	var/turf/dependency_0 = dependency_turfs[1]
	rel_set(src, nameof(dependency_air_0), dependency_0?.return_air())
	if(dependency_air_0)
		mixtures += dependency_air_0
	var/turf/dependency_1 = dependency_turfs[2]
	rel_set(src, nameof(dependency_air_1), dependency_1?.return_air())
	if(dependency_air_1)
		mixtures += dependency_air_1
	var/turf/dependency_2 = dependency_turfs[3]
	rel_set(src, nameof(dependency_air_2), dependency_2?.return_air())
	if(dependency_air_2)
		mixtures += dependency_air_2
	var/turf/dependency_3 = dependency_turfs[4]
	rel_set(src, nameof(dependency_air_3), dependency_3?.return_air())
	if(dependency_air_3)
		mixtures += dependency_air_3
	var/turf/dependency_4 = dependency_turfs[5]
	rel_set(src, nameof(dependency_air_4), dependency_4?.return_air())
	if(dependency_air_4)
		mixtures += dependency_air_4
	gas_level_rearm_all(src)
	// Settle every level before capturing the signature: opening crossings are inert.
	sleeping_signature = firedoor_atmos_signature()
	gas_watch_many(src, nameof(air_watches), mixtures, GAS_DEPENDENCY_PRESSURE, PROC_REF(air_heard))

/obj/machinery/door/firedoor/proc/clear_gas_dependencies()
	gas_watch_many_clear(src, nameof(air_watches))
	sleeping_signature = null
	for(var/datum/capability/lib/gas_level/def as anything in table_cap_defs(table_of(src), CAP_GAS_LEVEL))
		var/datum/cap_data/gas_level/data = gas_level_data(src, def)
		if(data)
			rel_clear(data, nameof(data.watch))
			data.armed_id = null
	rel_clear(src, nameof(dependency_air_0))
	rel_clear(src, nameof(dependency_air_1))
	rel_clear(src, nameof(dependency_air_2))
	rel_clear(src, nameof(dependency_air_3))
	rel_clear(src, nameof(dependency_air_4))

/obj/machinery/door/firedoor/proc/temperature_level_changed(datum/act/A)
	if(density && !isnull(sleeping_signature))
		reconsider_air_signature()

/obj/machinery/door/firedoor/proc/air_heard(datum/native_watch/gas/W, mixture_id, change_mask, list/observation, observation_index)
	reconsider_air_signature()

/obj/machinery/door/firedoor/proc/reconsider_air_signature()
	var/signature = firedoor_atmos_signature()
	if(signature != sleeping_signature)
		sleeping_signature = signature
		SSmachines.gas_woken_last++
		gas_dependency_wake_count++
		wake_from_air()

/// The air crossed a band edge: the door reads it and goes back to waiting.
/obj/machinery/door/firedoor/proc/wake_from_air()
	clear_gas_dependencies()
	if(density)
		air_check()
		hibernate_until_air_changes()

/obj/machinery/door/firedoor/proc/firedoor_atmos_signature()
	var/signature = getOPressureDifferential(src.loc) >= FIREDOOR_MAX_PRESSURE_DIFF
	var/band_0 = dependency_air_0 ? ((air_hot_0 ? FIREDOOR_ALERT_HOT : 0) | (air_cold_0 ? FIREDOOR_ALERT_COLD : 0)) : 0
	signature = (signature << 2) | band_0
	var/band_1 = dependency_air_1 ? ((air_hot_1 ? FIREDOOR_ALERT_HOT : 0) | (air_cold_1 ? FIREDOOR_ALERT_COLD : 0)) : 0
	signature = (signature << 2) | band_1
	var/band_2 = dependency_air_2 ? ((air_hot_2 ? FIREDOOR_ALERT_HOT : 0) | (air_cold_2 ? FIREDOOR_ALERT_COLD : 0)) : 0
	signature = (signature << 2) | band_2
	var/band_3 = dependency_air_3 ? ((air_hot_3 ? FIREDOOR_ALERT_HOT : 0) | (air_cold_3 ? FIREDOOR_ALERT_COLD : 0)) : 0
	signature = (signature << 2) | band_3
	var/band_4 = dependency_air_4 ? ((air_hot_4 ? FIREDOOR_ALERT_HOT : 0) | (air_cold_4 ? FIREDOOR_ALERT_COLD : 0)) : 0
	signature = (signature << 2) | band_4
	return signature

// Gas subscriptions are keyed by the mixtures of the turf the door sat on and its neighbours. After a move those ids are stale, so they are re-armed.
/obj/machinery/door/firedoor/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(air_watches)
		hibernate_until_air_changes()

/// A shut door on the map waits on its air from the moment the world is up.
/obj/machinery/door/firedoor/on_materialize()
	. = ..()
	if(density)
		hibernate_until_air_changes()

/// Reads the air around a shut door: a pressure difference past the limit or a band of temperature on any side is an alert, and any alert is a lockdown.
/obj/machinery/door/firedoor/proc/air_check(datum/act/A)
	var/redraw = FALSE
	lockdown = FALSE
	pdiff = getOPressureDifferential(src.loc)
	var/new_pdiff_alert = pdiff >= FIREDOOR_MAX_PRESSURE_DIFF
	lockdown ||= new_pdiff_alert
	if(pdiff_alert != new_pdiff_alert)
		set_pdiff_alert(new_pdiff_alert)
		redraw = TRUE
	var/list/tile_info = getCardinalAirInfo(src.loc, list("temperature", "pressure"))
	var/any_alerts = FALSE
	for(var/index = 1; index <= 4; index++)
		var/list/tileinfo = tile_info[index]
		var/alerts = tileinfo ? firedoor_temperature_band(tileinfo[1]) : 0
		if((LAZYACCESS(dir_alerts, index) || 0) != alerts)
			redraw = TRUE
			if(!dir_alerts)
				set_dir_alerts(new /list(4))
			dir_alerts[index] = alerts
		any_alerts ||= alerts
		lockdown ||= alerts
	if(!any_alerts)
		set_dir_alerts(null)
	if(redraw)
		changed(src) // the alert lights are no tracked var: the look is redrawn by hand

/obj/machinery/door/firedoor/proc/firedoor_temperature_band(temperature)
	// Auxmos publishes temperatures as 32-bit floats. Allow a tiny boundary
	// tolerance so an exact configured threshold survives the FFI round trip.
	var/celsius = convert_k2c(temperature)
	if(celsius >= FIREDOOR_MAX_TEMP - 0.01)
		return FIREDOOR_ALERT_HOT
	if(celsius <= FIREDOOR_MIN_TEMP + 0.01)
		return FIREDOOR_ALERT_COLD
	return 0

/obj/machinery/door/firedoor/proc/latetoggle()
	if(operating || !nextstate)
		return
	switch(nextstate)
		if(FIREDOOR_OPEN)
			nextstate = null

			open()
		if(FIREDOOR_CLOSED)
			nextstate = null
			close()
	return

/obj/machinery/door/firedoor/close()
	latetoggle()
	. = ..()

/// Actor-driven force opens keep attribution even when a timed action finishes later.
/obj/machinery/door/firedoor/proc/force_open_by(mob/user)
	if(user && user.ckey)
		log_admin("[user]([user.ckey]) has forced open an emergency shutter.")
		message_admins("[user]([user.ckey]) has forced open an emergency shutter.")
	return open(TRUE)

/obj/machinery/door/firedoor/open(forced = 0)
	if(hatch_open)
		set_hatch_open(0)
		visible_message("The maintenance hatch of \the [src] closes.")

	if(!forced)
		if(!operable())
			return //needs power to open unless it was forced
		else
			use_power(360)
	latetoggle()
	return ..()

/obj/machinery/door/firedoor/do_animate(animation)
	switch(animation)
		if("opening")
			flick("door_opening", src)
			playsound(src, open_sound, 37, 1) // var
		if("closing")
			playsound(src, close_sound, 37, 1) // var
			flick("door_closing", src)
	return

/obj/machinery/door/firedoor/draw(datum/look/look)
	..()
	var/prying = op_claimed(src)
	if(density)
		look.state(prying ? "prying_closed" : "door_closed")
		look.overlay("hatch", when = hatch_open)
		look.overlay("welded", when = blocked)
		look.overlay("palert", when = pdiff_alert)
		if(dir_alerts)
			for(var/d = 1 to 4)
				var/cdir = GLOB.cardinal[d]
				for(var/i = 1 to ALERT_STATES.len)
					if(dir_alerts[d] & (1<<(i-1)))
						look.overlay(image(icon = icon, icon_state = "alert_[ALERT_STATES[i]]", dir = cdir))
	else
		look.state(prying ? "prying_open" : "door_open")
		look.overlay("welded_open", when = blocked)

//These are playing merry hell on ZAS.  Sorry fellas :(

/obj/machinery/door/firedoor/border_only
/*
	icon = 'icons/obj/doors/edge_Doorfire.dmi'
	glass = 1 //There is a glass window so you can see through the door
			  //This is needed due to BYOND limitations in controlling visibility
	heat_proof = 1
	air_properties_vary_with_direction = 1

	CanPass(atom/movable/mover, turf/target)
		if(istype(mover) && mover.checkpass(PASSGLASS))
			return 1
		if(get_dir(loc, target) == dir) //Make sure looking at appropriate border
			return !density
		else
			return 1

	CheckExit(atom/movable/mover as mob|obj, turf/target as turf)
		if(istype(mover) && mover.checkpass(PASSGLASS))
			return 1
		if(get_dir(loc, target) == dir)
			return !density
		else
			return 1

	update_nearby_tiles(need_rebuild)
		if(!SSair) return 0

		var/turf/simulated/source = loc
		var/turf/simulated/destination = get_step(source,dir)

		update_heat_protection(loc)

		if(istype(source)) SSair.tiles_to_update += source
		if(istype(destination)) SSair.tiles_to_update += destination
		return 1
*/

/obj/machinery/door/firedoor/multi_tile
	icon = 'icons/obj/doors/DoorHazard2x1.dmi'
	width = 2
	open_sound = SFX_MACHINES_FIREWIDE1O
	close_sound = SFX_MACHINES_FIREWIDE1C

/obj/machinery/door/firedoor/glass
	name = "\improper Emergency Glass Shutter"
	desc = "Emergency air-tight shutter, capable of sealing off breached areas. This one has a resilient glass window, allowing you to see the danger."
	icon = 'icons/obj/doors/DoorHazardGlass.dmi'
	icon_state = "door_open"
	glass = 1

#undef FIREDOOR_MAX_PRESSURE_DIFF

#undef FIREDOOR_ALERT_HOT
#undef FIREDOOR_ALERT_COLD
// Not used #undef FIREDOOR_ALERT_LOWPRESS

//Glass variation of the 2x1 firedoor
/obj/machinery/door/firedoor/multi_tile/glass
	icon = 'icons/obj/doors/DoorHazardGlass2x1.dmi'
	width = 2
	glass = 1
	open_sound = SFX_MACHINES_FIREWIDE1O
	close_sound = SFX_MACHINES_FIREWIDE1C

/obj/machinery/door/firedoor/border_only/can_pathfinding_exit(atom/movable/actor, dir, datum/pathfinding/search)
	return (src.dir != dir) || ..()

/obj/machinery/door/firedoor/border_only/can_pathfinding_enter(atom/movable/actor, dir, datum/pathfinding/search)
	return (src.dir != dir) || ..()

/obj/machinery/door/firedoor/glass/hidden
	name = "\improper Emergency Shutter System"
	desc = "Emergency air-tight shutter, capable of sealing off breached areas. This model fits flush with the walls, and has a panel in the floor for maintenance."
	icon = 'icons/obj/doors/DoorHazardHidden.dmi'
	plane = TURF_PLANE

/obj/machinery/door/firedoor/glass/hidden/open()
	. = ..()
	plane = TURF_PLANE

/obj/machinery/door/firedoor/glass/hidden/close()
	. = ..()
	plane = OBJ_PLANE

/obj/machinery/door/firedoor/glass/hidden/steel
	name = "\improper Emergency Shutter System"
	desc = "Emergency air-tight shutter, capable of sealing off breached areas. This model fits flush with the walls, and has a panel in the floor for maintenance."
	icon = 'icons/obj/doors/DoorHazardHidden_steel.dmi'

/// Closes again after a manual open, if the fire alarm is still on.
/obj/machinery/door/firedoor/proc/autoclose_check()
	var/alarmed = 0
	for(var/area/A in areas_added)		//Just in case a fire alarm is turned off while the firedoor is going through an autoclose cycle
		if(A.firedoors_closed)
			alarmed = 1
	if(alarmed)
		nextstate = FIREDOOR_CLOSED
		close()

