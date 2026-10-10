// The wires capability (doc/rewrite/final_api.html, section 11 "The library": wires(); section 16.1, 16.2).
//
// Wires are COMPOSED from capabilities. A wire is defined once, in the WIRE_DEF table below: its name and what cutting, pulsing and mending it
// does, written as effects on the capability that brings it (holds on a stat the capability names, a proc of the capability). A capability brings
// its wires (brings_wires()): ai_control() the AI control wire, power_wires() the power wires, shock_wire() the electrification wire, lock(wire =)
// the ID scan wire, bolts(wire =) the bolt wire, ... (code/library/machine/wire_caps.dm). wires() derives the holder's wire list from the
// capabilities it has, and keeps only what belongs to the wiring as a whole:
//
//   wires(name = "APC", count = 4)                 the window title ("APC wires") and the blueprints' name; every wire, duds included
//   wires(..., randomize = TRUE)                   each holder its own colours; else every holder of that name shares one layout for the round
//   wires(..., count = PROC_REF(x), randomize = PROC_REF(y))     read from the holder at init (an airlock built with secure electronics)
//   wires(..., at = SPACE_X)                       the space the wires sit in (default SPACE_PANEL); null: always in reach (an exposed assembly)
//   wires(..., reach = cond)                       a further condition on the holder for working them (the APC's: the cover shut)
//   wires(..., status_lines = PROC_REF(x))         the status lines under the wires in the window ("The red light is blinking.")
//   wires(..., by_hand = TRUE)                     an empty hand opens the window too (op wires.open)
//   wires(..., tools = FALSE)                      no multitool or wirecutter op opens the window (the holder's own ops answer those tools)
//   wires(..., emp = FALSE)                        an EMP leaves the wires alone (by default it pulses up to three of them)
//   wires(..., starts_cut = PROC_REF(x))           the wires the holder starts with cut (a lathe mapped hacked), read once at init
//   wires(..., window = "WiresAirlock", record = /datum/cap_data/wires/airlock)   another window, a record with buttons of its own
//
// A wire only one type has is that type's own capability: on_wire(WIRE_X, cut = PROC_REF(a), pulse = PROC_REF(b)) brings WIRE_X to the type
// and hooks it (a(datum/notice/wire_cut/N) hears it cut and mended (N.mended), b(datum/notice/wire_pulsed/N) pulsed; N.user did it). On a
// wire a library capability brings, an on_wire() adds to what the wire does there (the airlock's ID wire also flashes the deny light).
//
//   on_notice(/datum/notice/wire_cut, then(...))                 any wire of the holder (a sorter's lights, a fridge waking)
//   extend(/datum/act/touch_wires, instead(...))                 touching the wires: an electrified machine shocks the toucher instead
//   contributes(STAT_X, req_wire_cut(WIRE_X)), extend(TAG_UI, needs(req_wire(WIRE_AI_CONTROL)))    rules that read the wires
//   extend(/datum/act/hit/blob, instead(cuts_all_wires()))      a hit that tears them out
//
// A wire's effects run first, then its notice is published (so on_notice hooks see the state the wire left). Pulse effects are keyed, sourced
// timed holds: each wire has one cut source and one pulse source, so a second pulse refreshes the one hold, a cut wire's hold outlasts any pulse,
// and mending releases both.
//
// The per-holder state (the colour layout, the cut wires, the signalers on them) is the capability's record, /datum/cap_data/wires, made when
// the holder initializes. It is also the wires window's host: interface("Wires") and the window's buttons are its ops, cut (cuts an intact
// wire, mends a cut one), pulse and attach (a signaler on or off a wire). Code works the wires through the procs at the bottom
// (wires_cut(), wires_mend(), wires_pulse(), wire_is_cut(), ...); a change publishes WIRES_KEY on the holder, so a contribution or a
// condition that reads wires says reads = list(WIRES_KEY).

MSG_DEF_SELF(wires/hidden, "The wires are behind the maintenance panel.")
MSG_DEF_SELF(wires/cut, "That wire is cut.")
MSG_DEF_SELF(wires/intact, "That wire is not cut.")
MSG_DEF_SELF(wires/need_cutters, "You need wirecutters!")
MSG_DEF_SELF(wires/need_multitool, "You need a multitool!")
MSG_DEF_SELF(wires/need_signaler, "You need a remote signaller!")
MSG_DEF_SELF(wires/out_of_reach, "You can't reach the wires.")
MSG_DEF_SELF(wires/stuck, "It is stuck to your hand!")

/// The key a holder publishes when one of its wires is cut, mended or the set is rebuilt.
#define WIRES_KEY "wires"
/// How many wires an EMP pulses at most.
#define WIRES_EMP_MAX_PULSES 3

/// A wire was cut or mended (N.mended): on_wire(W, cut = ...) and on_notice(/datum/notice/wire_cut, ...) hear it.
ACTION(cut_wire, wire, mended, mob/user, FIXED, notice = /datum/notice/wire_cut)
/// A wire was pulsed (a multitool, a signaler, an EMP): on_wire(W, pulse = ...) hears it.
ACTION(pulse_wire, wire, mob/user, FIXED, notice = /datum/notice/wire_pulsed)
/// Someone reaches into the wires (opens the window, presses a button in it): an instead() takes it over (a live machine shocks the toucher).
ACTION(touch_wires, mob/user, notice = /datum/notice/wires_touched)

// ---- the wire definitions ----

/// One wire, defined once (WIRE_DEF): its name and what cutting, pulsing and mending it does on the capability that brings it.
/datum/wire_def
	var/id
	var/name
	/// /datum/wire_effect lists, run in order.
	var/list/cut
	var/list/pulse
	var/list/mend
	/// The flyweight sources of this wire's holds: one for its cut, one for its pulse (a second pulse refreshes the one hold).
	var/datum/wire_hold_source/cut_source
	var/datum/wire_hold_source/pulse_source

/// The source of a wire's holds on a holder's stat ("the Primary Power wire, cut").
/datum/wire_hold_source
	var/wire
	var/kind

/proc/wire_def_make(wire, wire_name, cut = null, pulse = null, mend = null)
	RETURN_TYPE(/datum/wire_def)
	var/datum/wire_def/D = new
	D.id = wire
	D.name = wire_name
	D.cut = wire_effect_list(cut)
	D.pulse = wire_effect_list(pulse)
	D.mend = wire_effect_list(mend)
	D.cut_source = new // ALLOW(ownership): a flyweight source of holds, made once with its wire definition and kept for the round
	D.cut_source.wire = wire
	D.cut_source.kind = "cut"
	D.pulse_source = new // ALLOW(ownership): a flyweight source of holds, made once with its wire definition and kept for the round
	D.pulse_source.wire = wire
	D.pulse_source.kind = "pulse"
	return D

/proc/wire_effect_list(effects)
	if(isnull(effects))
		return list()
	return islist(effects) ? effects : list(effects)

/// The definition of `wire`, or null for a wire no library capability defines (a type's own on_wire() wire).
/proc/wire_def(wire)
	RETURN_TYPE(/datum/wire_def)
	READS_FROM()
	var/static/list/defs
	if(!defs)
		defs = wire_defs_build()
	return defs[wire]

/// WIRE_DEF(WIRE_X, "name", cut = effects, pulse = effects, mend = effects): one line of the table below.
#define WIRE_DEF(wire, wire_name, effects...) .[wire] = wire_def_make(wire, wire_name, ##effects)

/// The library's wires, each defined once. Every effect acts on the capability that brings the wire: wire_cut_holds() holds the stat that
/// capability's `stat` param names, wire_calls() runs a proc of it (and does nothing on a capability without that proc).
/proc/wire_defs_build()
	. = list()
	// ai_control(stat =, pulse_lasts =): cut, the AI is locked out until mended; pulsed, for pulse_lasts.
	WIRE_DEF(WIRE_AI_CONTROL, "AI Control", cut = wire_cut_holds(), pulse = wire_pulse_holds(), mend = wire_mend_releases())
	// id_scan(stat =): the wire overrides the scanner; lock(wire = WIRE_IDSCAN): a pulse opens the lock for a while.
	WIRE_DEF(WIRE_IDSCAN, "ID Scan", cut = wire_cut_holds(), pulse = list(wire_pulse_holds(), wire_calls(TYPE_PROC_REF(/datum/capability/lib/lock, id_wire_pulsed))), mend = wire_mend_releases())
	// power_wires(stat =, count =, pulse_lasts =, shock =): cut, the power is lost (and the hand may be shocked); pulsed, it trips for pulse_lasts.
	WIRE_DEF(WIRE_MAIN_POWER1, "Primary Power", cut = list(wire_cut_holds(), wire_calls(TYPE_PROC_REF(/datum/capability/lib/power_wires, power_wire_moved))), pulse = wire_pulse_holds(), mend = list(wire_mend_releases(), wire_calls(TYPE_PROC_REF(/datum/capability/lib/power_wires, power_wire_moved))))
	WIRE_DEF(WIRE_MAIN_POWER2, "Secondary Power", cut = list(wire_cut_holds(), wire_calls(TYPE_PROC_REF(/datum/capability/lib/power_wires, power_wire_moved))), pulse = wire_pulse_holds(), mend = list(wire_mend_releases(), wire_calls(TYPE_PROC_REF(/datum/capability/lib/power_wires, power_wire_moved))))
	// shock_wire(stat =, cut_value =, pulse_value =, pulse_lasts =): cut, live until mended (an untimed hold); pulsed, live for pulse_lasts (a timed
	// hold, refreshed by a second pulse); mending releases both. Read it with shock_live(): the hold counts only while the holder is operable.
	WIRE_DEF(WIRE_ELECTRIFY, "Electrification", cut = wire_cut_holds(), pulse = wire_pulse_holds(), mend = wire_mend_releases())
	WIRE_DEF(WIRE_SHOCK, "High Voltage Ground", cut = wire_cut_holds(), pulse = wire_pulse_holds(), mend = wire_mend_releases())
	// item_throw(stat =): cut, the machine throws its stock until mended; pulsed, the throwing flips.
	WIRE_DEF(WIRE_THROW_ITEM, "Item Throw", cut = wire_cut_holds(), pulse = wire_pulse_holds(), mend = wire_mend_releases())
	// safety_wire(stat =): cut, the safeties are off until mended; pulsed, they flip.
	WIRE_DEF(WIRE_SAFETY, "Safety", cut = wire_cut_holds(), pulse = wire_pulse_holds(), mend = wire_mend_releases())
	// lathe_wires(hack_stat =, disable_stat =, pulse_lasts =): the hack wire unlocks the hacked designs, the disable wire stops the machine.
	WIRE_DEF(WIRE_LATHE_HACK, "Hack", cut = list(wire_cut_holds("hack_stat"), wire_calls(TYPE_PROC_REF(/datum/capability/lib/lathe_wires, hack_wire_moved))), pulse = list(wire_pulse_holds("hack_stat"), wire_calls(TYPE_PROC_REF(/datum/capability/lib/lathe_wires, hack_wire_moved))), mend = list(wire_mend_releases("hack_stat"), wire_calls(TYPE_PROC_REF(/datum/capability/lib/lathe_wires, hack_wire_moved))))
	WIRE_DEF(WIRE_LATHE_DISABLE, "Disable", cut = wire_cut_holds("disable_stat"), pulse = wire_pulse_holds("disable_stat"), mend = wire_mend_releases("disable_stat"))
	// bolts(wire = WIRE_DOOR_BOLTS): cut, the bolts drop (mending does not raise them); pulsed, they drop or rise.
	WIRE_DEF(WIRE_DOOR_BOLTS, "Door Bolts", cut = wire_calls(TYPE_PROC_REF(/datum/capability/lib/bolts, bolt_wire_cut)), pulse = wire_calls(TYPE_PROC_REF(/datum/capability/lib/bolts, bolt_wire_pulsed)))

// ---- the effects ----

/// One thing a wire does to the capability that brings it.
/datum/wire_effect
	/// The capability param naming the stat it holds ("stat"), for the hold effects.
	var/stat_param

/datum/wire_effect/proc/apply(datum/capability/C, datum/holder, datum/wire_def/D, mob/user)
	return

/// The stat the capability names, or null (a capability bringing the wire with no state of its own).
/datum/wire_effect/proc/stat_of(datum/capability/C)
	return stat_param ? cap_param(C, stat_param) : null

/// wire_cut_holds(stat = "stat"): the cut wire holds the stat at the capability's cut_value (TRUE by default) until it is mended.
/proc/wire_cut_holds(stat = "stat")
	var/datum/wire_effect/cut_holds/E = new
	E.stat_param = stat
	return E

/datum/wire_effect/cut_holds

/datum/wire_effect/cut_holds/apply(datum/capability/C, datum/holder, datum/wire_def/D, mob/user)
	var/stat = stat_of(C)
	if(isnull(stat))
		return
	hold(holder, stat, wire_hold_value(stat, cap_param(C, "cut_value")), D.cut_source, null, WIRE_CUT_PRIORITY)

/// wire_pulse_holds(stat = "stat"): the pulse holds the stat at the capability's pulse_value for its pulse_lasts (a second pulse refreshes the
/// one hold); pulse_lasts = WIRE_PULSE_TOGGLES flips the hold; no pulse_lasts, the pulse does nothing.
/proc/wire_pulse_holds(stat = "stat")
	var/datum/wire_effect/pulse_holds/E = new
	E.stat_param = stat
	return E

/datum/wire_effect/pulse_holds

/datum/wire_effect/pulse_holds/apply(datum/capability/C, datum/holder, datum/wire_def/D, mob/user)
	var/stat = stat_of(C)
	var/lasts = cap_param(C, "pulse_lasts")
	if(isnull(stat) || !lasts)
		return
	var/value = wire_hold_value(stat, cap_param(C, "pulse_value"))
	if(lasts == WIRE_PULSE_TOGGLES)
		if(D.pulse_source in held_by(holder, stat))
			release(holder, stat, D.pulse_source)
		else
			hold(holder, stat, value, D.pulse_source)
		return
	hold(holder, stat, value, D.pulse_source, lasts)

/// wire_mend_releases(stat = "stat"): mending the wire releases its cut hold and any pulse still running: the wire's resting state.
/proc/wire_mend_releases(stat = "stat")
	var/datum/wire_effect/mend_releases/E = new
	E.stat_param = stat
	return E

/datum/wire_effect/mend_releases

/datum/wire_effect/mend_releases/apply(datum/capability/C, datum/holder, datum/wire_def/D, mob/user)
	var/stat = stat_of(C)
	if(isnull(stat))
		return
	release(holder, stat, D.cut_source)
	release(holder, stat, D.pulse_source)

/// wire_calls(TYPE_PROC_REF(/datum/capability/x, y)): runs y(holder, wire, user) on the capability bringing the wire, when it has that proc.
/proc/wire_calls(proc_name)
	var/datum/wire_effect/calls/E = new
	E.proc_name = proc_name
	return E

/datum/wire_effect/calls
	var/proc_name

/datum/wire_effect/calls/apply(datum/capability/C, datum/holder, datum/wire_def/D, mob/user)
	if(hascall(C, proc_name))
		call(C, proc_name)(holder, D.id, user)

/// The value a wire holds a stat at: none on a boolean stat (its rule forces it), else the capability's value (TRUE when it gives none).
/proc/wire_hold_value(stat, value)
	var/datum/stat_def/def = stat_def_of(stat)
	if(def?.boolean)
		return null
	return isnull(value) ? TRUE : value

// ---- capabilities bring wires ----

/// The wires a capability type brings to its holder (WIRE_* ids): TYPE_TABLE(/datum/capability/lib/x, brought_wires, list(WIRE_X)). Most bring none.
TYPE_TABLE_DECLARE(/datum/capability, brought_wires, null)

/// The wires this capability brings to its holder: its type's brought_wires, or what its params say (lock(wire =), shock_wire(wire =)).
/datum/capability/proc/brings_wires()
	return TYPE_TABLE_GET(src, brought_wires)

/// One of the wires this capability brought was cut (`event` "cut"), mended ("mend") or pulsed ("pulse"): the wire's definition says what that
/// does to the capability.
/datum/capability/proc/wire_event(datum/holder, wire, event, mob/user)
	var/datum/wire_def/D = wire_def(wire)
	if(!D)
		return
	var/list/effects
	switch(event)
		if("cut")
			effects = D.cut
		if("pulse")
			effects = D.pulse
		if("mend")
			effects = D.mend
	for(var/datum/wire_effect/E as anything in effects)
		E.apply(src, holder, D, user)

/// The capabilities of `holder` that bring wires: wire -> list of definitions, in declaration order.
/proc/wire_bringers(datum/holder)
	READS_FROM() // the type's compiled table and the holder's activations, not its state
	. = list()
	var/list/defs = list()
	var/datum/type_table/T = table_of(holder)
	for(var/key in T.caps)
		defs |= T.caps[key]
	for(var/datum/activation/A as anything in holder.rx?.activations)
		if(!A.dead)
			defs |= A.def
	for(var/datum/capability/C as anything in defs)
		for(var/wire in C.brings_wires())
			if(isnull(wire))
				continue
			var/list/bringers = .[wire]
			if(!bringers)
				bringers = list()
				.[wire] = bringers
			bringers += C

/// on_wire(WIRE_X, cut = PROC_REF(a), pulse = PROC_REF(b)): a type's own wire. It brings WIRE_X to the type and hooks it: a(datum/notice/wire_cut/N)
/// runs when it is cut and when it is mended (N.mended), b(datum/notice/wire_pulsed/N) when it takes a pulse. On a wire a library capability
/// brings too, it adds to what that wire does there.
CAPABILITY_TYPE(on_wire, CAP_ON_WIRE, /datum/capability/lib/on_wire, key = wire, wire = null, cut = null, pulse = null)

/datum/capability/lib/on_wire/entries()
	. = list()
	if(cut)
		. += on_notice(/datum/notice/wire_cut, then(cut), op = wire)
	if(pulse)
		. += on_notice(/datum/notice/wire_pulsed, then(pulse), op = wire)

/datum/capability/lib/on_wire/brings_wires()
	return list(wire)

/// The type's own hooks are its effects: the library definition of the wire (when there is one) is left to the capabilities that bring it.
/datum/capability/lib/on_wire/wire_event(datum/holder, wire, event, mob/user)
	return

// ---- layouts ----

/// Every wire of a holder, duds included (named WIRE_DUD_PREFIX + n, as the blueprints and the window expect).
/proc/wires_with_duds(list/wires, count)
	. = wires.Copy()
	var/duds = count - length(wires)
	while(duds > 0)
		var/dud = WIRE_DUD_PREFIX + "[--duds]"
		if(!(dud in .))
			. += dud

/// A fresh colour layout: colour -> wire, the wires shuffled over the palette.
/proc/wires_fresh_layout(list/all)
	var/static/list/palette = list("red", "blue", "green", "darkmagenta", "orange", "brown", "gold", "grey", "cyan", "white", "purple", "pink", "darkslategrey", "yellow")
	var/list/colors = palette.Copy()
	. = list()
	for(var/wire in shuffle(all))
		.[pick_n_take(colors)] = wire

/// The layout a new holder gets: its own when it randomizes, else the round's for its wiring's name (made by the first holder, kept in the
/// blueprints' directory). The round's list is shared: never written.
/proc/wires_layout_for(layout_key, list/all, randomize)
	if(randomize)
		return wires_fresh_layout(all)
	var/list/shared = GLOB.wire_color_directory[layout_key]
	if(!shared)
		shared = wires_fresh_layout(all)
		GLOB.wire_color_directory[layout_key] = shared
		GLOB.wire_name_directory[layout_key] = layout_key
	return shared

/proc/wire_is_dud(wire)
	return findtext(wire, WIRE_DUD_PREFIX, 1, length(WIRE_DUD_PREFIX) + 1)

// ---- the capability ----

CAPABILITY_TYPE(wires, CAP_WIRES, /datum/capability/lib/wires, key = NONE, name = "Unknown", count = 0, randomize = FALSE, window = "Wires", record = /datum/cap_data/wires, tools = TRUE, by_hand = FALSE, at = SPACE_PANEL, reach = null, status_lines = null, starts_cut = null, emp = TRUE)

/datum/capability/lib/wires
	holder_hooks = HOLDER_HOOK_INIT | HOLDER_HOOK_DESTROY

/datum/capability/lib/wires/cap_data_type()
	return /datum/cap_data/wires

/datum/capability/lib/wires/entries()
	var/list/at_the_wires = list(wait(0), then(CAP_PROC(open_window)))
	if(at)
		at_the_wires += global.at(at)
	. = list(look_layer(LOOK_WIRES, when = PANEL_OPEN))
	if(tools)
		. += op("pulse", tool(TOOL_MULTITOOL), label("Pulse wires"), at_the_wires)
		. += op("cut", tool(TOOL_WIRECUTTER), label("Cut wires"), at_the_wires)
	if(by_hand)
		. += op("open", hand(), at ? global.at(at) : null, then(CAP_PROC(open_window_by_hand)))

/// The wires window, for the actor.
/datum/capability/lib/wires/proc/open_window(datum/act/op/A)
	return wires_open(A.holder, A.actor) ? OP_OK : OP_REFUSED

/// wires(by_hand = TRUE): an empty hand opens the window too (a hand() op: an AI has no hand to reach it with).
/datum/capability/lib/wires/proc/open_window_by_hand(datum/act/op/A)
	wires_open(A.holder, A.actor)
	return OP_OK

/// A param that may be a proc of the holder (count = PROC_REF(x)): its value for `holder`.
/datum/capability/lib/wires/proc/holder_value(datum/holder, value)
	return istext(value) ? call(holder, value)() : value

/// The record is made when the holder initializes: the round's layout is laid out by the first holder, and a holder that starts with a wire cut
/// (a lathe mapped hacked) says so through `starts_cut` before anyone looks.
/datum/capability/lib/wires/on_holder_init(datum/act/eval/A)
	wiring_make(A.holder)

/// The holder goes: the signalers on its wires drop out of it.
/datum/capability/lib/wires/on_holder_destroy(datum/act/eval/A)
	var/datum/activation/act = cap_activation(A.holder, CAP_WIRES, null, FALSE)
	var/datum/cap_data/wires/W = act?.data
	if(!istype(W))
		return
	for(var/color in W.assemblies?.Copy())
		W.detach(color)
	W.owner = null // ALLOW(ownership): the record's back view of its holder, cleared as the holder goes; the activation drops the record

/// The holder's wire record, or null when it has no wires capability. Made when the holder initializes (wiring_make()).
/proc/wiring_of(datum/holder)
	RETURN_TYPE(/datum/cap_data/wires)
	READS_FROM(holder)
	if(!holder)
		return null
	var/datum/activation/act = cap_activation(holder, CAP_WIRES, null, FALSE)
	var/datum/cap_data/wires/W = act?.data
	return istype(W) ? W : null

/// Makes the holder's wire record: the wires its capabilities bring, the duds up to the count, the colour layout (the round's for the wiring's
/// name, or its own when it randomizes), the wires it starts with cut. Once, when the holder initializes.
/proc/wiring_make(datum/holder)
	RETURN_TYPE(/datum/cap_data/wires)
	var/datum/cap_data/wires/W = wiring_of(holder)
	if(W)
		return W
	var/datum/capability/lib/wires/def = cap_of(holder, CAP_WIRES)
	if(!def)
		return null
	var/list/bringers = wire_bringers(holder)
	var/list/real = list()
	for(var/wire in bringers)
		real += wire
	var/count = def.holder_value(holder, def.count)
	var/randomize = def.holder_value(holder, def.randomize)
	var/datum/activation/act = cap_activation(holder, CAP_WIRES, null, TRUE)
	var/record_type = def.record
	W = new record_type
	W.owner = holder // ALLOW(ownership): the record's back view of its holder, which owns the record through its wires activation
	W.def = def
	W.bringers = bringers
	W.colors = wires_layout_for(def.name, wires_with_duds(real, count), randomize)
	act.data = W // ALLOW(ownership): the capability's typed data, owned by the activation and dropped with it
	if(def.starts_cut)
		for(var/wire in call(holder, def.starts_cut)())
			if(!W.is_cut(wire))
				LAZYADD(W.cut, wire)
				W.wire_effects(wire, "cut", null)
	return W

// ---- the record: the holder's wires, and the window ----

/// One holder's wires: the colour layout, the cut wires and the signalers on them. The wires window's host.
/datum/cap_data/wires
	/// The holder (a back view: the holder's wires activation owns this record).
	var/datum/owner
	/// wire -> the capabilities that brought it (their wire effects run when it is cut, mended or pulsed).
	var/list/bringers
	/// colour -> wire. A set that does not randomize shares the round's list: never written, replaced (wires_shuffle()).
	var/list/colors
	/// The cut wires (lazy).
	var/list/cut
	/// colour -> the signaler on that wire (lazy).
	var/list/assemblies
	/// Admin: hide what each wire is, even from those who could see it.
	var/hide_wire_names = FALSE
	/// REF() of the last mob that cut, mended or pulsed a wire (wires_last_user(): a lathe refreshes that hand's window when a pulse runs out).
	var/last_user_ref
	var/datum/capability/lib/wires/def

CAPABILITIES(/datum/cap_data/wires)
	owns_many(nameof(assemblies))
	interface("Wires", state = nameof(GLOB.tgui_physical_state))
	op("cut", ui_act(arg("wire", schema_text(32))), needs(req_wires_in_reach(),
		req(PROC_REF(holds_cutters))), then(PROC_REF(cut_pressed)))
	op("pulse", ui_act(arg("wire", schema_text(32))), needs(req_wires_in_reach(),
		req(PROC_REF(holds_multitool))), then(PROC_REF(pulse_pressed)))
	op("attach", ui_act(arg("wire", schema_text(32))), needs(req_wires_in_reach(),
		req(PROC_REF(can_attach))), then(PROC_REF(attach_pressed)))

/datum/cap_data/wires/proc/all_wires()
	. = list()
	for(var/color in colors)
		. += colors[color]

/datum/cap_data/wires/proc/is_cut(wire)
	return (wire in cut)

/datum/cap_data/wires/proc/wire_of(color)
	return colors[color]

/datum/cap_data/wires/proc/color_of(wire)
	for(var/color in colors)
		if(colors[color] == wire)
			return color
	return null

/// The owner's wires changed: what reads them hears it.
/datum/cap_data/wires/proc/changed_wires()
	if(owner && !QDELETED(owner))
		changed(owner, 0, WIRES_KEY)

/// Runs the wire's effects on each capability that brought it, for the event "cut", "mend" or "pulse".
/datum/cap_data/wires/proc/wire_effects(wire, event, mob/user)
	if(user)
		last_user_ref = REF(user)
	for(var/datum/capability/C as anything in bringers?[wire])
		C.wire_event(owner, wire, event, user)

/// Cuts an intact wire: TRUE when it changed.
/datum/cap_data/wires/proc/cut_wire(wire, mob/user)
	if(isnull(wire) || is_cut(wire))
		return FALSE
	LAZYADD(cut, wire)
	wire_effects(wire, "cut", user)
	wires_publish(owner, /datum/notice/wire_cut, wire, FALSE, user)
	changed_wires()
	return TRUE

/// Mends a cut wire: TRUE when it changed.
/datum/cap_data/wires/proc/mend_wire(wire, mob/user)
	if(isnull(wire) || !is_cut(wire))
		return FALSE
	LAZYREMOVE(cut, wire)
	wire_effects(wire, "mend", user)
	wires_publish(owner, /datum/notice/wire_cut, wire, TRUE, user)
	changed_wires()
	return TRUE

/// Pulses an intact wire: TRUE when it took the pulse.
/datum/cap_data/wires/proc/pulse_wire(wire, mob/user)
	if(isnull(wire) || is_cut(wire))
		return FALSE
	wire_effects(wire, "pulse", user)
	wires_publish(owner, /datum/notice/wire_pulsed, wire, FALSE, user)
	return TRUE

/// Puts signaler S on the wire of `color`: S, or null when the wire already has one.
/datum/cap_data/wires/proc/attach(color, obj/item/assembly/signaler/S)
	if(!istype(S) || !(color in colors) || LAZYACCESS(assemblies, color))
		return null
	var/atom/A = owner
	if(isatom(A))
		S.forceMove(A)
	rel_add(src, nameof(assemblies), S, color) // we hold it (dropped by detach()); S.connected is the back view
	rel_set(S, nameof(S.connected), src)
	return S

/// Takes the signaler off the wire of `color`: it drops beside the owner. The signaler, or null.
/datum/cap_data/wires/proc/detach(color)
	var/obj/item/assembly/signaler/S = LAZYACCESS(assemblies, color)
	if(!istype(S))
		return null
	own_take_member(src, nameof(assemblies), color)
	rel_clear(S, nameof(S.connected))
	var/atom/A = owner
	if(isatom(A))
		S.forceMove(A.drop_location())
	return S

/// A signaler on a wire went off: its wire takes a pulse.
/datum/cap_data/wires/proc/signaled(obj/item/assembly/signaler/S)
	for(var/color in assemblies)
		if(assemblies[color] == S)
			pulse_wire(colors[color])
			return TRUE
	return FALSE

// ---- the window ----

/datum/cap_data/wires/ui_interface(mob/user)
	return def?.window || "Wires"

/datum/cap_data/wires/ui_title(mob/user)
	return "[def?.name] wires"

/// The window follows the owner: its distance, its view.
/datum/cap_data/wires/tgui_host()
	return owner

/// The wires' reach for the actor: the space they sit in is open to them and the owner's own condition holds. Pure.
/datum/cap_data/wires/proc/reach_reason(mob/user)
	var/atom/A = owner
	if(!istype(A) || QDELETED(A))
		return /datum/msg/wires/out_of_reach
	if(def?.at)
		var/why = A.space_reason(def.at, AUTH_PHYSICAL, user)
		if(why)
			return why
	if(!isnull(def?.reach) && !change_condition(A, def.reach))
		return /datum/msg/wires/out_of_reach
	return null

/// req_wires_in_reach(): a window button of the wire record answers only while its owner's wires are in the actor's reach.
/proc/req_wires_in_reach()
	return part_make(/datum/entry/part/req/wires_in_reach)

/datum/entry/part/req/wires_in_reach
	part_name = "req_wires_in_reach"
	default_reason = /datum/msg/wires/out_of_reach

/datum/entry/part/req/wires_in_reach/holds(datum/act/op/A)
	var/datum/cap_data/wires/W = A.holder
	return istype(W) && isnull(W.reach_reason(A.actor))

/datum/entry/part/req/wires_in_reach/refusal(datum/act/op/A)
	var/datum/cap_data/wires/W = A.holder
	return (istype(W) && W.reach_reason(A.actor)) || default_reason

/datum/entry/part/req/wires_in_reach/read_keys(datum/act/op/A)
	var/datum/cap_data/wires/W = A.holder
	var/atom/H = W?.owner
	if(!istype(H))
		return list()
	. = W.def?.at ? H.space_read_keys(W.def.at) : list()
	var/list/keys = list()
	present_condition_reads(H, W.def?.reach, keys)
	for(var/key in keys)
		. += list(list(H, key))

/// Reaching in: the owner may take it over (a live machine shocks the toucher). TRUE when the toucher got to the wires.
/datum/cap_data/wires/proc/touch(mob/user)
	if(!owner || QDELETED(owner))
		return FALSE
	return !isnull(act_touch_wires(owner, user))

/// The tool the actor works the wires with: the held item, or an emagged pAI card's built-in multitool or signaler.
/datum/cap_data/wires/proc/tool_of(mob/user)
	var/obj/item/I = user?.get_active_hand()
	var/obj/item/paicard/card = I
	if(istype(card) && card.emagged && card.has_emag_toolkit)
		switch(card.selected_system)
			if("MultiTool")
				return card.multitool
			if("Signaler")
				return card.signaler
	return I

/datum/cap_data/wires/proc/holds_cutters(datum/act/op/A)
	var/obj/item/I = tool_of(A.actor)
	return (istype(I) && I.has_tool_quality(TOOL_WIRECUTTER)) ? null : /datum/msg/wires/need_cutters

/datum/cap_data/wires/proc/holds_multitool(datum/act/op/A)
	var/obj/item/I = tool_of(A.actor)
	return (istype(I) && I.has_tool_quality(TOOL_MULTITOOL)) ? null : /datum/msg/wires/need_multitool

/// A signaler in hand for a free wire, or a wire with one to take off.
/datum/cap_data/wires/proc/can_attach(datum/act/op/A)
	var/color = lowertext(A.args?["wire"])
	return (!!LAZYACCESS(assemblies, color) || istype(tool_of(A.actor), /obj/item/assembly/signaler)) ? null : /datum/msg/wires/need_signaler

/// The cut button: cuts an intact wire, mends a cut one.
/datum/cap_data/wires/proc/cut_pressed(datum/act/op/A, wire)
	var/mob/user = A.actor
	if(!touch(user))
		return OP_REFUSED
	var/atom/H = owner
	H.add_hiddenprint(user)
	var/obj/item/I = tool_of(user)
	playsound(H, I.usesound, 20, 1)
	var/target = wire_of(lowertext(wire))
	if(is_cut(target))
		mend_wire(target, user)
	else
		cut_wire(target, user)
	return OP_OK

/// The pulse button. Pulsing the shock wire reaches in again (a live machine shocks the hand on it).
/datum/cap_data/wires/proc/pulse_pressed(datum/act/op/A, wire)
	var/mob/user = A.actor
	if(!touch(user))
		return OP_REFUSED
	var/atom/H = owner
	H.add_hiddenprint(user)
	play_sfx(H, SFX_WEAPONS_EMPTY, 0.4)
	var/target = wire_of(lowertext(wire))
	pulse_wire(target, user)
	if(target == WIRE_ELECTRIFY)
		touch(user)
	return OP_OK

/// The attach button: takes a signaler off the wire into the hand, or puts the held one on.
/datum/cap_data/wires/proc/attach_pressed(datum/act/op/A, wire)
	var/mob/user = A.actor
	if(!touch(user))
		return OP_REFUSED
	var/atom/H = owner
	H.add_hiddenprint(user)
	var/color = lowertext(wire)
	if(LAZYACCESS(assemblies, color))
		var/obj/item/O = detach(color)
		if(O)
			user.put_in_hands(O)
		return OP_OK
	var/obj/item/assembly/signaler/S = tool_of(user)
	if(!user.unEquip(S))
		op_tell(user, /datum/msg/wires/stuck)
		return OP_REFUSED
	attach(color, S)
	return OP_OK

/// Can `user` see what each wire is (an alien multitool, the trait)?
/datum/cap_data/wires/proc/can_see_wire_names(mob/user)
	if(hide_wire_names)
		return FALSE
	var/obj/item/held = user.get_active_hand()
	if(held && ispath(held.type, /obj/item/multitool/alien)) // the alien multitool reads the wires
		return TRUE
	return has_trait(user, TRAIT_CAN_SEE_WIRES) || (user.mind && has_trait(user.mind, TRAIT_CAN_SEE_WIRES))

/// The status lines under the wires: the owner's lights.
/datum/cap_data/wires/proc/status_lines()
	if(!def?.status_lines || !owner)
		return list()
	var/list/lines = call(owner, def.status_lines)()
	return islist(lines) ? lines : list()

/datum/cap_data/wires/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/replace_colors
	var/mob/living/L = user
	if(istype(L))
		replace_colors = L.body_effect_wire_colors()
	var/see_names = istype(user) && can_see_wire_names(user)
	var/list/wires_list = list()
	for(var/color in colors)
		var/replaced_color = color
		var/color_name = color
		if(color in replace_colors) // a colourblind viewer sees another colour
			replaced_color = replace_colors[color]
			color_name = (replaced_color in LIST_COLOR_RENAME) ? LIST_COLOR_RENAME[replaced_color] : replaced_color
		if(color in LIST_COLOR_RENAME)
			color_name = LIST_COLOR_RENAME[color]
		wires_list += list(list(
			"seen_color" = replaced_color,
			"color_name" = color_name,
			"color" = color,
			"wire" = see_names && !wire_is_dud(colors[color]) ? colors[color] : null,
			"cut" = is_cut(colors[color]),
			"attached" = !!LAZYACCESS(assemblies, color)))
	var/list/status = status_lines()
	if(replace_colors)
		for(var/i in 1 to length(status))
			for(var/color in replace_colors)
				var/new_color = replace_colors[color]
				if(new_color in LIST_COLOR_RENAME)
					new_color = LIST_COLOR_RENAME[new_color]
				if(findtext(status[i], color))
					status[i] = replacetext(status[i], color, new_color)
					break
	return list("wires" = wires_list, "status" = status)

// ---- what code calls ----

/// Publishes a wire notice from `holder`: on_wire(W, ...) hooks hear only their wire (the notice's selector is the wire).
/proc/wires_publish(datum/holder, notice_type, wire, mended, mob/user)
	if(!holder || !notice_wanted(holder, notice_type, ACT_COMMITTED))
		return
	if(notice_type == /datum/notice/wire_cut)
		var/datum/notice/wire_cut/C = notice_take(notice_type)
		C.wire = wire
		C.mended = mended
		C.user = user // ALLOW(ownership): a pooled notice holds its entities for one trigger and is reset on release
		C.op_key = wire
		notice_publish(holder, C, ACT_COMMITTED)
		return
	var/datum/notice/wire_pulsed/P = notice_take(notice_type)
	P.wire = wire
	P.user = user // ALLOW(ownership): a pooled notice holds its entities for one trigger and is reset on release
	P.op_key = wire
	notice_publish(holder, P, ACT_COMMITTED)

/// The last mob that worked a wire of `holder` (cut, mended or pulsed it), or null when it is gone.
/proc/wires_last_user(datum/holder)
	RETURN_TYPE(/mob)
	var/datum/cap_data/wires/W = wiring_of(holder)
	var/mob/user = W?.last_user_ref ? locate(W.last_user_ref) : null
	return istype(user) && !QDELETED(user) ? user : null

/// Is `wire` of `holder` cut?
/proc/wire_is_cut(datum/holder, wire)
	READS_FROM(holder)
	var/datum/cap_data/wires/W = wiring_of(holder)
	return W ? W.is_cut(wire) : FALSE

/// Cuts the wire if it is intact. TRUE when it changed.
/proc/wires_cut(datum/holder, wire, mob/user)
	return wiring_of(holder)?.cut_wire(wire, user) || FALSE

/// Mends the wire if it is cut. TRUE when it changed.
/proc/wires_mend(datum/holder, wire, mob/user)
	return wiring_of(holder)?.mend_wire(wire, user) || FALSE

/// The cut button's toggle: cuts an intact wire, mends a cut one.
/proc/wires_toggle(datum/holder, wire, mob/user)
	var/datum/cap_data/wires/W = wiring_of(holder)
	if(!W)
		return FALSE
	return W.is_cut(wire) ? W.mend_wire(wire, user) : W.cut_wire(wire, user)

/// Pulses the wire if it is intact. TRUE when it took the pulse.
/proc/wires_pulse(datum/holder, wire, mob/user)
	return wiring_of(holder)?.pulse_wire(wire, user) || FALSE

/// Cuts every intact wire: how many changed.
/proc/wires_cut_all(datum/holder)
	. = 0
	var/datum/cap_data/wires/W = wiring_of(holder)
	for(var/wire in W?.all_wires())
		. += W.cut_wire(wire)

/// Mends every cut wire: how many changed.
/proc/wires_mend_all(datum/holder)
	. = 0
	var/datum/cap_data/wires/W = wiring_of(holder)
	for(var/wire in W?.cut?.Copy())
		. += W.mend_wire(wire)

/// Every wire whole again at once, with no notice published (a camera's reset): the capabilities that brought the wires release what the cut
/// wires held; anything a type's own on_wire() hooks did is the caller's to undo.
/proc/wires_repair(datum/holder)
	var/datum/cap_data/wires/W = wiring_of(holder)
	if(!W)
		return
	var/list/was_cut = W.cut
	W.cut = null
	for(var/wire in was_cut)
		W.wire_effects(wire, "mend", null)
	W.changed_wires()

/// Cuts one intact wire at random: TRUE when there was one.
/proc/wires_cut_random(datum/holder)
	var/datum/cap_data/wires/W = wiring_of(holder)
	if(!W)
		return FALSE
	var/list/intact = W.all_wires() - W.cut
	if(!length(intact))
		return FALSE
	return W.cut_wire(pick(intact))

/// Is every wire of the holder cut?
/proc/wires_all_cut(datum/holder)
	READS_FROM(holder)
	var/datum/cap_data/wires/W = wiring_of(holder)
	return W && length(W.cut) == length(W.colors)

// Cut/mend publishes this holder's wire-state key; requirements observe that key
// instead of subscribing to the capability record's implementation lists.
READS_AS(/proc/wires_all_cut, WIRES_KEY)

/// An EMP pulses up to three wires, each with a one in three chance, in random order (unless the holder said wires(emp = FALSE)).
/proc/wires_emp(datum/holder)
	var/datum/cap_data/wires/W = wiring_of(holder)
	if(!W || !W.def?.emp)
		return
	var/remaining = WIRES_EMP_MAX_PULSES
	for(var/wire in shuffle(W.all_wires()))
		if(prob(33))
			W.pulse_wire(wire)
			remaining--
			if(!remaining)
				break

/// Every wire of the holder, duds included.
/proc/wires_all(datum/holder)
	return wiring_of(holder)?.all_wires() || list()

/// The holder's colour layout, colour -> wire (a copy).
/proc/wires_layout(datum/holder)
	var/datum/cap_data/wires/W = wiring_of(holder)
	return W ? W.colors.Copy() : list()

/// Opens the wires window for `user`, when the wires are in their reach and touching them goes through. TRUE when it opened.
/proc/wires_open(datum/holder, mob/user)
	var/datum/cap_data/wires/W = wiring_of(holder)
	if(!W || !istype(user) || W.reach_reason(user) || !W.touch(user))
		return FALSE
	W.tgui_interact(user)
	return TRUE

/// Puts signaler S on the wire of `color`: S, or null.
/proc/wire_attach_signaler(datum/holder, color, obj/item/assembly/signaler/S)
	return wiring_of(holder)?.attach(color, S)

/// Takes the signaler off the wire of `color`: it drops beside the holder. The signaler, or null.
/proc/wire_detach_signaler(datum/holder, color)
	return wiring_of(holder)?.detach(color)

/// The signaler on the wire of `color`, or null.
/proc/wire_signaler_at(datum/holder, color)
	return LAZYACCESS(wiring_of(holder)?.assemblies, color)

/// Takes every signaler off the holder's wires (a disarmed mine kicks them off).
/proc/wires_detach_all(datum/holder)
	var/datum/cap_data/wires/W = wiring_of(holder)
	for(var/color in W?.assemblies?.Copy())
		W.detach(color)

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
	wires_cut_all(A.holder)
	return OP_OK

#undef WIRES_EMP_MAX_PULSES
