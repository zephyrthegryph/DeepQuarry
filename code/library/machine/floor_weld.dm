// The floor weld (doc/rewrite/final_api.html, section 11 "The library"): a heavy machine that is bolted to the floor with a wrench and then
// welded down, the singularity engine's emitters and field generators. Its rung is the concrete holder's saved `state` (0 loose, 1 bolted, 2 welded;
// floor_weld_set_state() delegates to its tracked setter): op floor_weld.bolt (a wrench, instant) bolts a loose machine down or unbolts a
// bolted one, op floor_weld.weld (a lit welder, `weld_time`) welds a bolted one down or cuts a welded one free. Neither works while the
// holder's `busy` var is set (a running emitter, an active field generator). What the holder does when its rung changes (an emitter joins its
// cable network when welded) is its `changed` proc, x(datum/act/op/A), called after the rung moved.
//
//   floor_weld()                                                 the ladder, always workable
//   floor_weld(busy = nameof(active))                            ...but not while the machine runs
//   floor_weld(busy = nameof(active), changed = PROC_REF(x))     ...and the holder hears every move of the rung

MSG_DEF(floor_weld/bolted, "You secure the external reinforcing bolts to the floor.", "%U% secures %T% to the floor.")
MSG_DEF(floor_weld/unbolted, "You undo the external reinforcing bolts.", "%U% unsecures %T% reinforcing bolts from the floor.")
MSG_DEF(floor_weld/welded, "You weld %T% to the floor.", "%U% welds %T% to the floor.")
MSG_DEF(floor_weld/cut_free, "You cut %T% free from the floor.", "%U% cuts %T% free from the floor.")
MSG_DEF_SELF(floor_weld/needs_unwelding, "It needs to be unwelded from the floor.")
MSG_DEF_SELF(floor_weld/needs_bolting, "It needs to be wrenched to the floor.")
MSG_DEF_SELF(floor_weld/busy, "Turn it off first.")
MSG_DEF_SELF(floor_weld/loose_examine, "It is not secured in place!")
MSG_DEF_SELF(floor_weld/bolted_examine, "It has been bolted down securely, but not welded into place.")
MSG_DEF_SELF(floor_weld/welded_examine, "It has been bolted down securely and welded down into place.")

CAPABILITY_TYPE(floor_weld, CAP_FLOOR_WELD, /datum/capability/lib/floor_weld, key = NONE, busy = null, weld_time = 2 SECONDS, changed = null)

/datum/capability/lib/floor_weld

/datum/capability/lib/floor_weld/entries()
	var/list/idle = busy ? needs(req_is(busy, FALSE, because = MSG(floor_weld/busy))) : null
	return list(
		op("bolt", tool(TOOL_WRENCH), label("Bolt to the floor"), wait(0), idle,
			needs(req_bool(CAP_PROC(not_welded), because = MSG(floor_weld/needs_unwelding))), then(CAP_PROC(bolt_toggled)), says(CAP_PROC(bolt_message))),
		op("weld", lit_welder(), label("Weld to the floor"), wait(weld_time), idle,
			needs(req_bool(CAP_PROC(not_loose), because = MSG(floor_weld/needs_bolting))), then(CAP_PROC(weld_toggled)), says(CAP_PROC(weld_message))),
		examine_line(CAP_PROC(examine_rung)))

/datum/capability/lib/floor_weld/proc/not_welded(datum/act/A)
	var/obj/machinery/M = A.holder
	return M.floor_weld_state() != FLOOR_WELD_WELDED

/datum/capability/lib/floor_weld/proc/not_loose(datum/act/A)
	var/obj/machinery/M = A.holder
	return M.floor_weld_state() != FLOOR_WELD_LOOSE

/// The wrench: a loose machine is bolted down, a bolted one comes loose.
/datum/capability/lib/floor_weld/proc/bolt_toggled(datum/act/op/A)
	var/obj/machinery/M = A.holder
	var/bolting = M.floor_weld_state() == FLOOR_WELD_LOOSE
	M.floor_weld_set_state(bolting ? FLOOR_WELD_BOLTED : FLOOR_WELD_LOOSE)
	M.set_anchored(bolting)
	play_sfx(M, SFX_ITEMS_RATCHET)
	rung_moved(A)
	return OP_OK

/// The holder's own reaction to the rung's move, when it named one.
/datum/capability/lib/floor_weld/proc/rung_moved(datum/act/op/A)
	if(changed)
		call(A.holder, changed)(A)

/datum/capability/lib/floor_weld/proc/bolt_message(datum/act/A)
	var/obj/machinery/M = A.holder
	return M.floor_weld_state() == FLOOR_WELD_BOLTED ? /datum/msg/floor_weld/bolted : /datum/msg/floor_weld/unbolted

/// The welder: a bolted machine is welded down, a welded one is cut free.
/datum/capability/lib/floor_weld/proc/weld_toggled(datum/act/op/A)
	var/obj/machinery/M = A.holder
	M.floor_weld_set_state(M.floor_weld_state() == FLOOR_WELD_BOLTED ? FLOOR_WELD_WELDED : FLOOR_WELD_BOLTED)
	rung_moved(A)
	return OP_OK

/datum/capability/lib/floor_weld/proc/weld_message(datum/act/A)
	var/obj/machinery/M = A.holder
	return M.floor_weld_state() == FLOOR_WELD_WELDED ? /datum/msg/floor_weld/welded : /datum/msg/floor_weld/cut_free

/datum/capability/lib/floor_weld/proc/examine_rung(datum/act/A)
	var/obj/machinery/M = A.holder
	switch(M.floor_weld_state())
		if(FLOOR_WELD_LOOSE)
			return /datum/msg/floor_weld/loose_examine
		if(FLOOR_WELD_BOLTED)
			return /datum/msg/floor_weld/bolted_examine
	return /datum/msg/floor_weld/welded_examine

/// The shared ladder uses the concrete holder's saved rung; unrelated machines own no rung.
/obj/machinery/proc/floor_weld_state()
	READS_FROM()
	CRASH("floor_weld: [type] does not implement its rung reader")
READS_AS(/obj/machinery/proc/floor_weld_state, state)

/obj/machinery/proc/floor_weld_set_state(rung)
	CRASH("floor_weld: [type] does not implement its rung setter")
