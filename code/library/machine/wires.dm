// The wires capability (doc/rewrite/final_api.html, section 11 "The library": wires(type); section 16.1, 16.2).
//
// One /datum/wires (the wire system of code/datums/wires/) per holder, made on first use and kept in the capability's typed data
// (/datum/cap_data/wires). A multitool or wirecutters on the wires, which sit in space `at` (behind the panel, SPACE_PANEL), opens the wires window; the wires datum
// does the rest (cut, mend, pulse, signalers) and tells the holder when a wire changed, so what reads the wires follows.
//
//   wires(/datum/wires/apc)                      the wire set, behind the panel
//   wires(PROC_REF(wire_set))                    a proc of the holder returning the set (an airlock built with secure electronics)
//   wires(kind, by_hand = TRUE)                  an empty hand at the open panel opens the window too (wires.open)
//
// What the wires drive is the holder's: contributes(STAT_BOLTED, req_wire_cut(WIRE_DOOR_BOLTS)) says a cut bolt wire bolts the door;
// extend(CAP_LOCK, needs(req_wire(WIRE_IDSCAN))) says the ID scanner wire must be intact; a hit that tears the wires out is cuts_all_wires().
// A change of the wires publishes the key WIRES_KEY on the holder: a contribution or a condition that reads wires says reads = list(WIRES_KEY).

MSG_DEF_SELF(wires/hidden, "The wires are behind the maintenance panel.")
MSG_DEF_SELF(wires/cut, "That wire is cut.")
MSG_DEF_SELF(wires/intact, "That wire is not cut.")

/// The key a holder publishes when one of its wires is cut, mended or the set is rebuilt.
#define WIRES_KEY "wires"

CAPABILITY_TYPE(wires, CAP_WIRES, /datum/capability/lib/wires, key = NONE, kind = null, by_hand = FALSE, at = SPACE_PANEL)

/// The typed data of the wires capability: the holder's wire set.
/datum/cap_data/wires
	var/datum/wires/wire_set

/datum/capability/lib/wires
	holder_hooks = HOLDER_HOOK_DESTROY

/datum/capability/lib/wires/cap_data_type()
	return /datum/cap_data/wires

/datum/capability/lib/wires/entries()
	var/list/at_the_wires = list(global.at(at), wait(0), then(CAP_PROC(open_window)))
	. = list(
		op("pulse", tool(TOOL_MULTITOOL), label("Pulse wires"), at_the_wires),
		op("cut", tool(TOOL_WIRECUTTER), label("Cut wires"), at_the_wires),
		look_layer(LOOK_WIRES, when = PANEL_OPEN))
	if(by_hand)
		. += op("open", hand(), global.at(at), then(CAP_PROC(open_window_by_hand)))

/// The wires window: the wire set's own (its interactable() says whether this person can use it now).
/datum/capability/lib/wires/proc/open_window(datum/act/op/A)
	var/datum/wires/W = wire_set_of(A.holder)
	if(!W)
		return OP_FAILED
	W.Interact(A.actor)
	return OP_OK

/// wires(by_hand = TRUE): an empty hand at the open panel opens the window too (an AI's remote hand does not).
/datum/capability/lib/wires/proc/open_window_by_hand(datum/act/op/A)
	if(isAI(A.actor))
		return OP_REFUSED
	wire_set_of(A.holder)?.Interact(A.actor)
	return OP_OK

/// The wire set `holder` was built with, made on first use.
/datum/capability/lib/wires/proc/make_set(datum/holder)
	var/set_type = kind
	if(istext(set_type))
		set_type = call(holder, set_type)()
	if(!ispath(set_type, /datum/wires))
		return null
	return new set_type(holder)

/datum/capability/lib/wires/on_holder_destroy_ctx(datum/act/eval/A)
	var/datum/activation/act = cap_activation(A.holder, CAP_WIRES, null, FALSE)
	var/datum/cap_data/wires/D = act?.data
	if(D?.wire_set)
		var/datum/wires/W = D.wire_set
		D.wire_set = null // ALLOW(ownership): the wire set belongs to the capability's own data record, which is dropped with the activation
		qdel(W) // ALLOW(lifecycle): a wire set is a plain datum the capability's data holds, not an atom: the lifecycle verbs take atoms

/// The wire set of `holder`, made on first use, or null when it has no wires capability. The one reader: the wires window, the wire rules and
/// the holder's own code go through it.
/proc/wire_set_of(datum/holder)
	RETURN_TYPE(/datum/wires)
	var/datum/capability/lib/wires/def = cap_of(holder, CAP_WIRES)
	if(!def)
		return null
	var/datum/activation/act = cap_activation(holder, CAP_WIRES, null, TRUE)
	var/datum/cap_data/wires/D = cap_data(act)
	if(!D.wire_set)
		D.wire_set = def.make_set(holder) // ALLOW(ownership): the wire set belongs to the capability's own data record, which is dropped with the activation
	return D.wire_set

/// Is `wire` of `holder` cut? A holder whose wires were never touched has none cut.
/proc/wire_is_cut(datum/holder, wire)
	READS_FROM(holder)
	var/datum/activation/act = cap_activation(holder, CAP_WIRES, null, FALSE)
	var/datum/cap_data/wires/D = act?.data
	return D?.wire_set ? D.wire_set.is_cut(wire) : FALSE

/// A wire of the holder's set changed: what reads the wires hears it.
/datum/wires/proc/state_changed()
	if(holder && !QDELETED(holder))
		changed(holder, 0, WIRES_KEY)

// ---- requirements and the effect that read and write the wires ----

/// req_wire(W): the wire is intact.
/proc/req_wire(wire, because = null)
	return part_make(/datum/entry/part/req/wire, list("wire" = wire, "cut" = FALSE, "because" = because))

/// req_wire_cut(W): the wire is cut.
/proc/req_wire_cut(wire, because = null)
	return part_make(/datum/entry/part/req/wire, list("wire" = wire, "cut" = TRUE, "because" = because))

/datum/entry/part/req/wire
	part_name = "req_wire"

/datum/entry/part/req/wire/holds(datum/act/A)
	return wire_is_cut(A.holder, src.args["wire"]) == src.args["cut"]

/datum/entry/part/req/wire/read_keys(datum/act/op/A)
	return A.holder ? list(list(A.holder, WIRES_KEY)) : list()

/datum/entry/part/req/wire/refusal(datum/act/op/A)
	if(src.args["because"])
		return ..()
	return src.args["cut"] ? /datum/msg/wires/intact : /datum/msg/wires/cut

/// cuts_all_wires(): tears every wire of the holder out (a blob, a shredder's claws).
/proc/cuts_all_wires()
	return part_make(/datum/entry/part/effect/cuts_all_wires)

/datum/entry/part/effect/cuts_all_wires
	part_name = "cuts_all_wires"

/datum/entry/part/effect/cuts_all_wires/run_effect(datum/act/A)
	var/datum/wires/W = wire_set_of(A.holder)
	if(W)
		W.cut_all()
	return OP_OK
