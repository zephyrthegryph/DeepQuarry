// The parts a door answers to (doc/rewrite/final_api.html, section 11 "The library"; the airlock is the reference user, doc/rewrite/conversion_guide.md).
//
//   bolts(drop = "drop_bolts", raise = "raise_bolts", starts = nameof(bolted_at_start))
//        STAT_BOLTED, a door's stat composed from sourced holds: the door's own motor (SRC_DOOR_BOLTS: a wire, a button, a radio command), and each
//        hand that bolts it on its own account (an AI's button holds with the AI as its source, so its unbolt releases only its own hold). `drop`
//        and `raise` name procs of the holder taking (forced) that move them and answer TRUE when they did. A map says a door starts bolted with the
//        holder var `starts` names. The look shows them as the layer "bolts".
//        bolts(wire = WIRE_DOOR_BOLTS) brings the bolt wire: cut, the bolts drop (mending does not raise them); pulsed, they drop or rise.
//   weld_shut(offered = PROC_REF(can_weld), starts = nameof(welded_at_start), tool = TOOL_WELDER)
//        State key WELD_SHUT_WELDED and op weld_shut.toggle: a lit welder welds the closed door shut and frees it again where `offered` (a proc of the
//        holder, x(datum/act/A)) says welding is on offer. Look layer and examine line. `tool` is the quality that seals it where it is not a welder
//        (a coffin is screwed shut): no flame is needed and no fuel is burned then.
//   door_emergency()
//        State key DOOR_EMERGENCY_ENGAGED: while engaged the door lets anyone through (the door's own check_access_list() reads it). The look shows
//        it as the layer "emergency".
//
// Reads go through the stat var (`bolted`) and the accessors the keys generate (weld_shut_welded(), door_emergency_engaged()), and
// through is_bolted()/set_bolted(), is_welded()/set_welded() and emergency_access_on()/set_emergency_access() below, the names the rest of the game
// has always used.

MSG_DEF_SELF(bolts/bolted, "The bolts are down.")
MSG_DEF_SELF(bolts/not_bolted, "The bolts are up.")

CAPABILITY_TYPE(bolts, CAP_BOLTS, /datum/capability/lib/bolts, key = NONE, drop = "drop_bolts", raise = "raise_bolts", starts = null, wire = null)

/// The door's bolts are down, whoever holds them.
STAT(/obj/machinery/door, bolted, ANY)
/// A door's own bolt motor: what a wire, a button, a radio command or a map start drops the bolts with.
SOURCE_DEF(door_bolts)

/datum/capability/lib/bolts
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/bolts/entries()
	return list(look_layer(LOOK_BOLTS, when = STAT_BOLTED))

/datum/capability/lib/bolts/brings_wires()
	return wire ? list(wire) : null

/// The bolt wire cut (WIRE_DEF in code/library/machine/wires.dm): the bolts drop, whatever holds them up.
/datum/capability/lib/bolts/proc/bolt_wire_cut(datum/holder, cut_wire, mob/user)
	set_bolted(holder, TRUE, TRUE)

/// The bolt wire pulsed: raised bolts drop, dropped ones rise (through the holder's own mechanism, which may refuse).
/datum/capability/lib/bolts/proc/bolt_wire_pulsed(datum/holder, pulsed_wire, mob/user)
	set_bolted(holder, !is_bolted(holder))

/datum/capability/lib/bolts/on_holder_init(datum/act/eval/A)
	var/wanted = starts
	if(istext(wanted))
		wanted = A.holder.vars[wanted]
	if(wanted)
		hold(A.holder, STAT_BOLTED, TRUE, SRC_DOOR_BOLTS)

/// Are the bolts of A down? (A holder without bolts says no.)
/proc/is_bolted(atom/A)
	READS_FROM(A)
	var/obj/machinery/door/D = A
	return istype(D) && cap_of(D, CAP_BOLTS) && D.bolted

/// Drops (on) or raises the bolts of A through the holder's own mechanism; `forced` skips its refusals. TRUE when they moved.
/proc/set_bolted(atom/A, on, forced = FALSE)
	var/datum/capability/lib/bolts/def = cap_of(A, CAP_BOLTS)
	if(!def)
		return FALSE
	return !!call(A, on ? def.drop : def.raise)(forced)

// ---- weld_shut ----

MSG_DEF(weld/welded, "You weld %T% shut.", "%U% welds %T% shut.")
MSG_DEF(weld/unwelded, "You unweld %T%.", "%U% unwelds %T%.")
MSG_DEF_SELF(weld/not_welded, "It is not welded shut.")
MSG_DEF_SELF(weld/needs_lit, "The welding tool needs to be lit.")
MSG_DEF_SELF(weld/examine, "It has been welded shut.")

CAPABILITY_TYPE(weld_shut, CAP_WELD_SHUT, /datum/capability/lib/weld_shut, key = NONE, offered = null, starts = null, tool = TOOL_WELDER)
cap_keys(CAP_WELD_SHUT, WELDED = MSG(weld/not_welded))

/datum/capability/lib/weld_shut
	holder_hooks = HOLDER_HOOK_INIT

/datum/capability/lib/weld_shut/entries()
	if(tool != TOOL_WELDER)
		return list(
			op("toggle", tool(tool), label("Seal"), when(offered), wait(0), toggles(WELD_SHUT_WELDED), says(CAP_PROC(toggled_message))),
			look_layer(LOOK_WELDED, when = WELD_SHUT_WELDED),
			examine_line(MSG(weld/examine), when = WELD_SHUT_WELDED))
	return list(
		op("toggle", tool(tool), label("Weld shut"), when(offered), wait(0), costs(RES_FUEL, 0), toggles(WELD_SHUT_WELDED), says(CAP_PROC(toggled_message)), \
			needs(req_bool(CAP_PROC(welder_lit), because = MSG(weld/needs_lit)))),
		look_layer(LOOK_WELDED, when = WELD_SHUT_WELDED),
		examine_line(MSG(weld/examine), when = WELD_SHUT_WELDED))

/datum/capability/lib/weld_shut/on_holder_init(datum/act/eval/A)
	var/wanted = starts
	if(istext(wanted))
		wanted = A.holder.vars[wanted]
	if(wanted)
		key_set(A.holder, WELD_SHUT_WELDED, TRUE)

/// The welder is lit.
/datum/capability/lib/weld_shut/proc/welder_lit(datum/act/op/A)
	var/obj/item/weldingtool/welder = A.held?.get_welder()
	return !welder || welder.isOn()

/// What weld_shut.toggle just did.
/datum/capability/lib/weld_shut/proc/toggled_message(datum/act/A)
	return weld_shut_welded(A.holder, null) ? /datum/msg/weld/welded : /datum/msg/weld/unwelded

/// Is A welded shut?
/proc/is_welded(atom/A)
	READS_FROM(A)
	if(!cap_of(A, CAP_WELD_SHUT))
		return !!(capability_bits(A) & CAP_WELDED) // the legacy bit of the holders that keep it (a vent)
	return weld_shut_welded(A, null)

/// Welds A shut or frees it with no welder (a construct's spell, a mech clamp tearing it open).
/proc/set_welded(atom/A, on)
	if(!cap_of(A, CAP_WELD_SHUT))
		return cap_set(A, CAP_WELDED, on)
	return key_set(A, WELD_SHUT_WELDED, !!on)

// ---- door_emergency ----

MSG_DEF_SELF(emergency/off, "Its emergency access mode is off.")
MSG_DEF_SELF(emergency/examine, "Its emergency access mode is engaged.")

CAPABILITY_TYPE(door_emergency, CAP_DOOR_EMERGENCY, /datum/capability/lib/door_emergency, key = NONE)
cap_keys(CAP_DOOR_EMERGENCY, ENGAGED = MSG(emergency/off))

/datum/capability/lib/door_emergency

/datum/capability/lib/door_emergency/entries()
	return list(
		look_layer(LOOK_EMERGENCY, when = DOOR_EMERGENCY_ENGAGED),
		examine_line(MSG(emergency/examine), when = DOOR_EMERGENCY_ENGAGED))

/// Does A let anyone through (its emergency access is engaged)?
/proc/emergency_access_on(atom/A)
	READS_FROM(A)
	if(!cap_of(A, CAP_DOOR_EMERGENCY))
		return FALSE
	return door_emergency_engaged(A, null)

/// Engages or lifts the emergency access of A.
/proc/set_emergency_access(atom/A, on)
	return key_set(A, DOOR_EMERGENCY_ENGAGED, !!on)
