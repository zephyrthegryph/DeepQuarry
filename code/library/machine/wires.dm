// The wires capability (doc/rewrite/final_api.html, section 11 "The library": wires(set); section 16.1, 16.2).
//
// A holder's wires are a WIRE SET, declared as data: a /datum/wire_set subtype with the wires that do something (WIRE_* ids), how many wires
// there are in all (the rest are duds), whether each holder gets its own colours or the set keeps one layout for the round, and the window.
//
//   /datum/wire_set/apc
//   	name = "APC"                                   the window title ("APC wires") and the blueprints' name
//   	count = 4                                      every wire, duds included
//   	wires = list(WIRE_IDSCAN, WIRE_MAIN_POWER1, WIRE_MAIN_POWER2, WIRE_AI_CONTROL)
//   	randomize = FALSE                              TRUE: each holder its own colours, else one layout per set for the round
//
// The holder declares the capability with its set, where the wires sit and what they do:
//
//   wires(/datum/wire_set/apc)                     the set, behind the panel (space SPACE_PANEL, which panel() declares)
//   wires(PROC_REF(wire_set))                      a proc of the holder returning the set (an airlock built with secure electronics)
//   wires(set, at = SPACE_X)                       the space the wires sit in; null: always in reach (an exposed assembly)
//   wires(set, reach = cond)                       a further condition on the holder for working them (the APC's: the cover shut)
//   wires(set, status_lines = PROC_REF(x))         the status lines under the wires in the window ("The red light is blinking.")
//   wires(set, by_hand = TRUE)                     an empty hand opens the window too (op wires.open)
//   wires(set, tools = FALSE)                      no multitool or wirecutter op opens the window (the holder's own ops answer those tools)
//   wires(set, emp = FALSE)                        an EMP leaves the wires alone (by default it pulses up to three of them)
//   wires(set, starts_cut = PROC_REF(x))           the wires the holder starts with cut (a lathe mapped hacked), read once at init
//
//   on_wire(WIRE_X, cut = PROC_REF(a), pulse = PROC_REF(b))     what one wire does: a(datum/notice/wire_cut/N) hears it cut and mended
//                                                                (N.mended), b(datum/notice/wire_pulsed/N) hears it pulsed; N.user did it
//   on_notice(/datum/notice/wire_cut, then(...))                 any wire of the set (a sorter's lights, a fridge waking)
//   extend(/datum/act/touch_wires, instead(...))                 touching the wires: an electrified machine shocks the toucher instead
//   contributes(STAT_X, req_wire_cut(WIRE_X)), extend(TAG_UI, needs(req_wire(WIRE_AI_CONTROL)))    rules that read the wires
//   extend(/datum/act/hit/blob, instead(cuts_all_wires()))      a hit that tears them out
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

// ---- the wire set: data ----

/// A wire set. Subtypes are pure data; one instance per type (wire_set_def()) is shared by every holder.
/datum/wire_set
	/// The window title's name ("APC" -> "APC wires") and the blueprints'.
	var/name = "Unknown"
	/// The wires that do something: WIRE_* ids.
	var/list/wires
	/// Every wire, duds included. Fewer than `wires` means none are duds.
	var/count = 0
	/// TRUE: each holder gets its own colours. FALSE: every holder of the set shares one layout for the round.
	var/randomize = FALSE
	/// The tgui interface of the window.
	var/window = "Wires"
	/// The record the holder's wires are kept in: a subtype adds window buttons of its own (the airlock's ID tag and frequency).
	var/record = /datum/cap_data/wires

/// The shared instance of a wire set type.
/proc/wire_set_def(set_type)
	RETURN_TYPE(/datum/wire_set)
	var/static/list/defs = list()
	if(!ispath(set_type, /datum/wire_set))
		return null
	var/datum/wire_set/S = defs[set_type]
	if(!S)
		S = new set_type
		defs[set_type] = S
	return S

/// Every wire of the set, duds included (named WIRE_DUD_PREFIX + n, as the blueprints and the window expect).
/datum/wire_set/proc/all_wires()
	. = wires.Copy()
	var/duds = count - length(wires)
	while(duds > 0)
		var/dud = WIRE_DUD_PREFIX + "[--duds]"
		if(!(dud in .))
			. += dud

/// A fresh colour layout: colour -> wire, the wires shuffled over the palette.
/datum/wire_set/proc/fresh_layout()
	var/static/list/palette = list("red", "blue", "green", "darkmagenta", "orange", "brown", "gold", "grey", "cyan", "white", "purple", "pink", "darkslategrey", "yellow")
	var/list/colors = palette.Copy()
	. = list()
	for(var/wire in shuffle(all_wires()))
		.[pick_n_take(colors)] = wire

/// The layout a new holder of this set gets: its own when the set randomizes, else the round's (made by the first holder, kept in the
/// blueprints' directory). The round's list is shared: never written.
/datum/wire_set/proc/layout_for_holder()
	if(randomize)
		return fresh_layout()
	var/list/shared = GLOB.wire_color_directory[type]
	if(!shared)
		shared = fresh_layout()
		GLOB.wire_color_directory[type] = shared
		GLOB.wire_name_directory[type] = name
	return shared

/proc/wire_is_dud(wire)
	return findtext(wire, WIRE_DUD_PREFIX, 1, length(WIRE_DUD_PREFIX) + 1)

// ---- the capability ----

CAPABILITY_TYPE(wires, CAP_WIRES, /datum/capability/lib/wires, key = NONE, kind = null, tools = TRUE, by_hand = FALSE, at = SPACE_PANEL, reach = null, status_lines = null, starts_cut = null, emp = TRUE)

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

/// The set `holder` is built with: `kind`, or what the holder's proc answers.
/datum/capability/lib/wires/proc/set_type_for(datum/holder)
	var/set_type = kind
	if(istext(set_type))
		set_type = call(holder, set_type)()
	return ispath(set_type, /datum/wire_set) ? set_type : null

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

/// Makes the holder's wire record: the set its capability names, the colour layout (the round's, or its own when the set randomizes), the
/// wires it starts with cut. Once, when the holder initializes.
/proc/wiring_make(datum/holder)
	RETURN_TYPE(/datum/cap_data/wires)
	var/datum/cap_data/wires/W = wiring_of(holder)
	if(W)
		return W
	var/datum/capability/lib/wires/def = cap_of(holder, CAP_WIRES)
	if(!def)
		return null
	var/set_type = def.set_type_for(holder)
	var/datum/wire_set/S = wire_set_def(set_type)
	if(!S)
		return null
	var/datum/activation/act = cap_activation(holder, CAP_WIRES, null, TRUE)
	var/record_type = S.record
	W = new record_type
	W.owner = holder
	W.set_type = set_type
	W.colors = S.layout_for_holder()
	W.def = def // ALLOW(ownership): an interned capability definition, never written
	act.data = W // ALLOW(ownership): the capability's typed data, owned by the activation and dropped with it
	if(def.starts_cut)
		for(var/wire in call(holder, def.starts_cut)())
			LAZYADD(W.cut, wire)
	return W

// ---- the record: the holder's wires, and the window ----

/// One holder's wires: the colour layout, the cut wires and the signalers on them. The wires window's host.
/datum/cap_data/wires
	/// The holder (a back view: the holder's wires activation owns this record).
	var/datum/owner
	/// The /datum/wire_set type.
	var/set_type
	/// colour -> wire. A set that does not randomize shares the round's list: never written, replaced (wires_shuffle()).
	var/list/colors
	/// The cut wires (lazy).
	var/list/cut
	/// colour -> the signaler on that wire (lazy).
	var/list/assemblies
	/// Admin: hide what each wire is, even from those who could see it.
	var/hide_wire_names = FALSE
	var/datum/capability/lib/wires/def

CAPABILITIES(/datum/cap_data/wires)
	owns_many(nameof(assemblies))
	interface("Wires", state = nameof(GLOB.tgui_physical_state))
	op("cut", ui_act(arg("wire", schema_text(32))), needs(req_wires_in_reach(),
		req(PROC_REF(holds_cutters), because = MSG(wires/need_cutters))), then(PROC_REF(cut_pressed)))
	op("pulse", ui_act(arg("wire", schema_text(32))), needs(req_wires_in_reach(),
		req(PROC_REF(holds_multitool), because = MSG(wires/need_multitool))), then(PROC_REF(pulse_pressed)))
	op("attach", ui_act(arg("wire", schema_text(32))), needs(req_wires_in_reach(),
		req(PROC_REF(can_attach), because = MSG(wires/need_signaler))), then(PROC_REF(attach_pressed)))

/datum/cap_data/wires/proc/wire_set()
	RETURN_TYPE(/datum/wire_set)
	return wire_set_def(set_type)

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

/// Cuts an intact wire: TRUE when it changed.
/datum/cap_data/wires/proc/cut_wire(wire, mob/user)
	if(isnull(wire) || is_cut(wire))
		return FALSE
	LAZYADD(cut, wire)
	wires_publish(owner, /datum/notice/wire_cut, wire, FALSE, user)
	changed_wires()
	return TRUE

/// Mends a cut wire: TRUE when it changed.
/datum/cap_data/wires/proc/mend_wire(wire, mob/user)
	if(isnull(wire) || !is_cut(wire))
		return FALSE
	LAZYREMOVE(cut, wire)
	wires_publish(owner, /datum/notice/wire_cut, wire, TRUE, user)
	changed_wires()
	return TRUE

/// Pulses an intact wire: TRUE when it took the pulse.
/datum/cap_data/wires/proc/pulse_wire(wire, mob/user)
	if(isnull(wire) || is_cut(wire))
		return FALSE
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
	return wire_set()?.window || "Wires"

/datum/cap_data/wires/ui_title(mob/user)
	return "[wire_set()?.name] wires"

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
	return istype(I) && I.has_tool_quality(TOOL_WIRECUTTER)

/datum/cap_data/wires/proc/holds_multitool(datum/act/op/A)
	var/obj/item/I = tool_of(A.actor)
	return istype(I) && I.has_tool_quality(TOOL_MULTITOOL)

/// A signaler in hand for a free wire, or a wire with one to take off.
/datum/cap_data/wires/proc/can_attach(datum/act/op/A)
	var/color = lowertext(A.args?["wire"])
	return !!LAZYACCESS(assemblies, color) || istype(tool_of(A.actor), /obj/item/assembly/signaler)

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

/// on_wire(WIRE_X, cut = PROC_REF(a), pulse = PROC_REF(b)): what one wire of the holder does. a(datum/notice/wire_cut/N) runs when it is cut
/// and when it is mended (N.mended), b(datum/notice/wire_pulsed/N) when it takes a pulse.
/proc/on_wire(wire, cut = null, pulse = null)
	. = list()
	if(cut)
		. += on_notice(/datum/notice/wire_cut, then(cut), op = wire)
	if(pulse)
		. += on_notice(/datum/notice/wire_pulsed, then(pulse), op = wire)

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

/// Every wire whole again at once, with nothing told (a malfunctioning AI's reset): the wires' effects are the caller's.
/proc/wires_repair(datum/holder)
	var/datum/cap_data/wires/W = wiring_of(holder)
	if(!W)
		return
	W.cut = null
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
	var/datum/cap_data/wires/W = wiring_of(holder)
	return W && length(W.cut) == length(W.colors)

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
