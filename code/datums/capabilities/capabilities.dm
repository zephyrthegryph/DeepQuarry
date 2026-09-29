// capabilities(), cap_state, capability data, gating and the capability interaction entry
// (doc/rewrite/dx_conventions.md §2). The datum interface is in _capability.dm.

/atom
	/// One bit per boolean capability state (CAP_*). A type default is free per instance.
	var/cap_state = 0
	/// Lazily created per-instance capability data: capability key -> datum (cap_data()).
	var/tmp/list/cap_data

/// The capabilities this type has, in declaration order (menu, examine and draw order). Built once
/// per type and cached: `. = ..()` then `. += ...`; `. = without(., /datum/capability/x)` drops one.
/// Pure: read no instance state here.
/atom/proc/capabilities()
	RETURN_TYPE(/list)
	return list()

/// The cached capability list of A's type. Shared: never write into it.
/proc/caps_of(atom/A)
	RETURN_TYPE(/list)
	return type_list(A, TYPE_PROC_REF(/atom, capabilities))

/// The capability of A with this key (a type, or an explicit key), or null.
/proc/cap_of(atom/A, key)
	for(var/datum/capability/C as anything in caps_of(A))
		if(C.key == key || (ispath(key) && istype(C, key)))
			return C
	return null

/// L without the entries whose key is `key`, or which are of type `key`. Returns a new list.
/proc/without(list/L, key)
	. = list()
	for(var/entry in L)
		var/datum/capability/C = entry
		if(istype(C) && (C.key == key || (ispath(key) && istype(C, key))))
			continue
		. += entry

/datum/capability/New()
	..()
	if(isnull(key))
		key = type

// ---- state ----

/// TRUE when every bit in `bits` is set on A.
/proc/cap_has(atom/A, bits)
	return (A.cap_state & bits) == bits

/// Sets or clears `bits` on A through the change path. TRUE when the state changed.
/proc/cap_set(atom/A, bits, on)
	var/was = A.cap_state
	if(on)
		A.cap_state |= bits
	else
		A.cap_state &= ~bits
	if(was == A.cap_state)
		return FALSE
	changed(A, CHANGE_CAPABILITY)
	return TRUE

/// The per-instance data datum of capability C on A, created on first use (C.data_type).
/proc/cap_data(atom/A, datum/capability/C)
	var/datum/D = A.cap_data?[C.key]
	if(D || !C.data_type)
		return D
	D = new C.data_type
	LAZYSET(A.cap_data, C.key, D)
	return D

/datum/capability
	/// The datum type cap_data() creates per instance, or null for bit-only state.
	var/data_type
	/// This capability's interaction entries, built once (shared by every holder of the type).
	var/tmp/list/built_entries

// The accessors, written once per capability.
/proc/cover_is_open(atom/A)
	return !!(A.cap_state & CAP_COVER_OPEN)
/proc/panel_is_open(atom/A)
	return !!(A.cap_state & CAP_PANEL_OPEN)
/proc/is_locked(atom/A)
	return !!(A.cap_state & CAP_LOCKED)
/proc/is_emagged(atom/A)
	return !!(A.cap_state & CAP_EMAGGED)
/proc/is_broken(atom/A)
	return !!(A.cap_state & CAP_BROKEN)
/// The wires capability's wires are exposed when everything they sit behind is open; without one,
/// the CAP_WIRES_EXPOSED bit answers.
/proc/wires_exposed(atom/A)
	var/datum/capability/wires/W = cap_of(A, /datum/capability/wires)
	if(W)
		return (A.cap_state & W.behind) == W.behind
	return !!(A.cap_state & CAP_WIRES_EXPOSED)

/// Whether A has power for its entries. Machines answer through their power state; anything else
/// is always powered. The powered capability overrides nothing: it reads this.
/atom/proc/cap_powered()
	return TRUE

/obj/machinery/cap_powered()
	return !(stat & NOPOWER)

// ---- lifecycle hooks ----

#define TYPE_DERIVES_CAPS (1<<0)
#define TYPE_DERIVES_LOOK (1<<1)
#define TYPE_DERIVES_VERBS (1<<2)

/// Runs every capability's on_init, then queues the first refresh when the type has anything derived
/// (capabilities, a draw() that sets something, hidden verbs, periodic work). Called from
/// /atom/Initialize() and table_initialize() after the declarations. Runs for every atom: the
/// per-type answer is cached, so an atom with nothing derived costs one list lookup.
/atom/proc/caps_init(mapload)
	var/flags = type_derive_flags(src)
	if(flags & TYPE_DERIVES_CAPS)
		for(var/datum/capability/C as anything in caps_of(src))
			C.on_holder_init(src, mapload)
			cap_join_systems(src, C)
	if(flags || periodic_cadence)
		changed(src)

/// TYPE_DERIVES_* for A's type: it has capabilities, its draw() sets something, its hidden_verbs()
/// hides something. Worked out on the type's first instance and remembered.
/proc/type_derive_flags(atom/A)
	var/known = GLOB.type_derives_cache[A.type]
	if(!isnull(known))
		return known
	. = 0
	if(length(caps_of(A)))
		. |= TYPE_DERIVES_CAPS
	var/datum/look/L = GLOB.look_builder
	L.reset()
	A.draw(L)
	if(L.touched)
		. |= TYPE_DERIVES_LOOK
	if(length(A.hidden_verbs()))
		. |= TYPE_DERIVES_VERBS
	GLOB.type_derives_cache[A.type] = .

/// Whether A's type derives anything the refresh engine keeps up (a look or hidden verbs).
/proc/type_derives(atom/A)
	return !!(type_derive_flags(A) & (TYPE_DERIVES_LOOK | TYPE_DERIVES_VERBS))

GLOBAL_LIST_EMPTY(type_derives_cache)

/// Runs every capability's on_destroy and drops the data. Called from /atom/Destroy().
/atom/proc/caps_destroy()
	var/flags = GLOB.type_derives_cache[type]
	if(!isnull(flags) && !(flags & TYPE_DERIVES_CAPS) && !cap_data && !cap_extras)
		return
	var/list/caps = caps_all(src)
	for(var/datum/capability/C as anything in caps)
		C.on_holder_destroy(src)
		cap_leave_systems(src, C)
	cap_extras = null
	for(var/key in cap_data)
		var/datum/D = cap_data[key]
		if(isdatum(D))
			qdel(D)
	cap_data = null

#undef TYPE_DERIVES_CAPS
#undef TYPE_DERIVES_LOOK
#undef TYPE_DERIVES_VERBS

/// Examine lines from every capability, in list order (appended by /atom/examine()).
/atom/proc/caps_examine(mob/user)
	. = list()
	for(var/datum/capability/C as anything in caps_ordered(src, CAP_ORDER_EXAMINE))
		var/list/lines = C.examine(src, user)
		if(lines)
			. += lines

/// Adds every capability's UI data. /datum/tgui_data() callers merge it through ..().
/atom/proc/caps_ui_data(mob/user, list/data)
	for(var/datum/capability/C as anything in caps_all(src))
		C.ui_data(src, user, data)

/// Every capability's hidden verbs plus the type's own hidden_verbs().
/atom/proc/caps_hidden_verbs()
	. = list()
	for(var/datum/capability/C as anything in caps_all(src))
		var/list/hidden = C.hidden_verbs(src)
		if(hidden)
			. |= hidden

/// The capability interaction entries of A's type (resolver candidates).
/proc/cap_interactions(atom/A)
	. = list()
	for(var/datum/capability/C as anything in caps_of(A))
		. += cap_built_entries(C, A)

/// C's entries, built on first use and registered by id (the Menu runs a chosen entry by id).
/proc/cap_built_entries(datum/capability/C, atom/A)
	if(isnull(C.built_entries))
		C.built_entries = C.interactions(A) || list()
		for(var/datum/interaction/capability/E as anything in C.built_entries)
			if(!E.cap)
				E.cap = C
			cap_apply_gating(C, E)
			var/datum/interaction/clash = GLOB.cap_entries_by_id[E.id]
			if(clash && clash != E)
				E.id = "[E.id]#[C.key]"
			GLOB.cap_entries_by_id[E.id] = E
	return C.built_entries

// ---- gating ----

/**
 * Why `entry` (a capability entry of A) can't run for user now, or null. Order: broken, unpowered,
 * behind (needs the bits SET), blocked_by (needs them CLEAR: "only while the cover is closed"),
 * locked_by, needs, then every capability's gate() (the cover, the lock, a slot's rules).
 */
/proc/cap_gate_reason(atom/A, mob/user, obj/item/held, datum/interaction/capability/entry)
	if(!entry.works_broken && is_broken(A))
		return "it's broken"
	if(!entry.works_unpowered && !A.cap_powered())
		return "it has no power"
	if(entry.behind & ~A.cap_state)
		var/missing = entry.behind & ~A.cap_state
		if(missing & CAP_COVER_OPEN)
			return "open the cover first"
		return "open the maintenance panel first"
	if(entry.blocked_by & A.cap_state)
		var/present = entry.blocked_by & A.cap_state
		if(present & CAP_COVER_OPEN)
			return "close the cover first"
		if(present & CAP_PANEL_OPEN)
			return "close the maintenance panel first"
		return "you can't do that in its current state"
	if(entry.locked_by && (A.cap_state & entry.locked_by))
		return "it's locked"
	if(entry.needs)
		var/list/needs = islist(entry.needs) ? entry.needs : list(entry.needs)
		for(var/proc_ref in needs)
			var/result = call(A, proc_ref)(user, held)
			if(istext(result))
				return result
			if(!result)
				return entry.else_say || "you can't do that right now"
	for(var/datum/capability/C as anything in caps_all(A))
		var/reason = C.gate(A, user, entry)
		if(reason)
			return reason
	return null

// ---- the capability interaction entry ----

/// An interaction offered by a capability. Shared per (type, capability); per-instance state lives
/// on the holder. The handler is a proc on the holder, (mob/user, obj/item/held, ...named form answers).
/datum/interaction/capability
	var/datum/capability/cap
	/// PROC_REF on the holder.
	var/handler
	var/behind = NONE
	/// CAP_* bits that must be CLEAR (the APC's ID swipe only while the cover is closed).
	var/blocked_by = NONE
	var/locked_by = NONE
	var/needs
	var/else_say
	var/works_broken = FALSE
	var/works_unpowered = FALSE
	var/log
	/// Whether the handler takes the held item: (mob/user, obj/item/held, ...). hand() handlers are
	/// (mob/user, ...); tool()/use_on()/insert() and library item entries pass `held`.
	var/passes_held = TRUE
	/// Form fields (choice_field()/text_field()/number_field()): asked in order, answers passed by name.
	var/list/form
	/// A proc on the holder, (mob/user) -> the Menu name for this state ("Open cover"/"Close cover").
	var/name_proc
	/// A proc on the holder, () -> whether this entry is offered at all on this instance (not a refusal:
	/// the entry doesn't exist for it). Cheap, no actor.
	var/applies
	/// The entry never touches the holder's live parts (cap_electrify() doesn't zap it).
	var/insulated = FALSE

/// Keyed by the entry itself: two capabilities can build entries with one id (the same handler
/// and name) but different selectors (anchor(tool = TOOL_WRENCH) vs anchor(tool = TOOL_SCREWDRIVER)).
/datum/interaction/capability/predicate_key()
	return "cap:[id]:[SHARED_CACHE_UID(src)]"

/datum/interaction/capability/display_name(mob/actor, atom/target)
	if(name_proc)
		return call(target, name_proc)(actor)
	return name

/datum/interaction/capability/applies_to(atom/target)
	// A holder can suspend all its capability entries (a frozen airlock): the input falls through to
	// whatever comes next (an attack), as if the entries weren't there.
	if(target.caps_suspended())
		return FALSE
	return applies ? call(target, applies)() : TRUE

/datum/interaction/capability/why_not(mob/actor, atom/target, obj/item/held)
	. = ..()
	if(.)
		return
	return cap_gate_reason(target, actor, held, src)

/datum/interaction/capability/run_effect(mob/actor, atom/target, obj/item/held)
	// The holder-wide hook with side effects (the airlock's shock) runs only here, never while the
	// Menu is built: FALSE stops the entry (the input is used).
	if(!target.before_entry(actor, src, held))
		return UI_REFUSED
	var/datum/dispatch_context/ctx = new(actor, target, held, src)
	. = cap_dispatch(ctx)
	if(isnull(.))
		. = TRUE // a handler that returned nothing (or went async to ask) handled it

/// Holder-wide hook before any of its capability entries runs, with side effects allowed (the airlock
/// shocks a non-silicon while electrified). FALSE stops the entry; the input is used up.
/// The default asks each capability's own before_entry() (cap_electrify() zaps here).
/atom/proc/before_entry(mob/user, datum/interaction/capability/entry, obj/item/held)
	for(var/datum/capability/C as anything in caps_all(src))
		if(C.before_entry(src, user, held, entry))
			return FALSE // stopped (the capability told the user)
	return TRUE

/// TRUE while none of this atom's capability entries are offered at all (a frozen airlock): input
/// falls through to the next handler instead of being refused.
/atom/proc/caps_suspended()
	return FALSE

/// Runs the entry's form and handler for ctx, async when it prompts (dispatch_call()).
/proc/cap_dispatch(datum/dispatch_context/ctx)
	var/datum/interaction/capability/E = ctx.entry
	var/list/named = list("user" = ctx.user)
	if(E.passes_held)
		named["held"] = ctx.held
	if(length(E.form))
		return cap_dispatch_form(ctx, named)
	return dispatch_call(ctx, ctx.target, E.handler, named, E.name, E.log)

/proc/cap_dispatch_form(datum/dispatch_context/ctx, list/named)
	set waitfor = FALSE
	var/datum/interaction/capability/E = ctx.entry
	for(var/datum/form_field/F as anything in E.form)
		var/answer = F.ask(ctx)
		if(isnull(answer))
			return
		named[F.name] = answer
	// Reserved names last: no form field can shadow them.
	named["user"] = ctx.user
	if(E.passes_held)
		named["held"] = ctx.held
	else
		named -= "held"
	dispatch_call(ctx, ctx.target, E.handler, named, E.name, E.log)

/**
 * Merges capability C's gating (its constructor's behind / blocked_by / locked_by / needs / else_say /
 * works_* / log) onto entry E, which may be stricter on its own: bits are OR-ed, needs are all
 * required, works_* hold only when both allow, the entry's own log and else_say win. Every library
 * constructor takes the same gating arguments and sets them on the capability with cap_gating();
 * this applies them once, centrally, when the entries are built.
 */
/proc/cap_apply_gating(datum/capability/C, datum/interaction/capability/E)
	if(C == E.cap && istype(C, /datum/capability/entry))
		return // a bespoke entry: its gating is the entry's own
	E.behind |= C.behind
	E.blocked_by |= C.blocked_by
	E.locked_by |= C.locked_by
	if(C.needs)
		var/list/merged = list()
		if(E.needs)
			merged += E.needs
		merged += C.needs
		E.needs = merged
	E.else_say ||= C.else_say
	if(!C.works_broken)
		E.works_broken = FALSE
	if(!C.works_unpowered)
		E.works_unpowered = FALSE
	E.log ||= C.log

/// Sets the standard gating arguments on capability C (every library constructor calls it with its
/// own same-named arguments). Returns C.
/proc/cap_gating(datum/capability/C, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	C.behind = behind
	C.blocked_by = blocked_by
	C.locked_by = locked_by
	C.needs = needs
	C.else_say = else_say
	C.works_broken = works_broken
	C.works_unpowered = works_unpowered
	C.log = log
	return C

// ---- the bespoke entries: small capabilities ----

/// A capability that is just one entry.
/datum/capability/entry
	var/datum/interaction/capability/entry

/datum/capability/entry/interactions(atom/holder)
	return list(entry)

/// A library capability's own entry: takes the interaction out of a hand()/tool()/use_on()/insert()
/// wrapper, gives it a stable id (the predicate cache key: it must differ wherever the tool or held
/// type differs) and makes this capability its owner.
/datum/capability/proc/own_entry(datum/capability/entry/wrapper, id)
	var/datum/interaction/capability/E = wrapper.entry
	E.cap = src
	if(id)
		E.id = id
	return E

/// Shared constructor body for hand()/tool()/use_on()/insert().
/proc/cap_entry(entry_kind, name, handler, behind, locked_by, needs, else_say, works_broken, works_unpowered, log, list/form, held_type, tool_quality, delay, priority, stance, name_proc, applies, blocked_by)
	var/datum/capability/entry/C = new
	var/datum/interaction/capability/E = new
	E.name = name
	E.id = "[entry_kind]:[name]:[handler]"
	E.handler = handler
	E.behind = behind
	E.blocked_by = blocked_by
	E.passes_held = entry_kind != "hand"
	E.locked_by = locked_by
	E.needs = needs
	E.else_say = else_say
	E.works_broken = works_broken
	E.works_unpowered = works_unpowered
	E.log = log
	E.form = form
	E.name_proc = name_proc
	// Reach, as every resolver-native interaction has it: the empty-hand path asks the resolver
	// before it checks adjacency.
	E.requires = list(REQ_INTERACTION_REACH)
	E.applies = applies
	E.priority = priority || 0
	E.stance = stance
	E.cap = C
	switch(entry_kind)
		if("hand")
			E.entry = null
			E.category = INTERACTION_CAT_TOGGLE
			E.default_action = INPUT_ACTION_USE
		if("tool")
			E.tool = tool_quality
			E.duration = delay || 0
			E.category = INTERACTION_CAT_MAINTAIN
			E.default_action = INPUT_ACTION_USE
		if("use_on")
			E.held_type = held_type
			E.category = INTERACTION_CAT_TOGGLE
			E.default_action = INPUT_ACTION_USE
		if("insert")
			E.held_type = held_type
			E.category = INTERACTION_CAT_INSERT
			E.default_action = INPUT_ACTION_USE
	E.apply_stance_tags()
	C.entry = E
	C.key = E.id
	C.behind = behind
	C.locked_by = locked_by
	C.log = log
	return C

/// An empty-hand action: hand("Toggle", PROC_REF(toggle)). Handler (mob/user).
/proc/cap_hand(name, handler, behind = NONE, locked_by = NONE, needs, else_say, works_broken = FALSE, works_unpowered = FALSE, log, list/form, priority, stance, name_proc, applies, blocked_by = NONE)
	return cap_entry("hand", name, handler, behind, locked_by, needs, else_say, works_broken, works_unpowered, log, form, null, null, null, priority, stance, name_proc, applies, blocked_by)

/// A tool action: tool("Unbolt", TOOL_WRENCH, PROC_REF(unbolt), delay = 2 SECONDS). Handler (mob/user, obj/item/held).
/proc/cap_tool(name, quality, handler, delay, behind = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, list/form, priority, name_proc, applies, blocked_by = NONE)
	return cap_entry("tool", name, handler, behind, locked_by, needs, else_say, works_broken, works_unpowered, log, form, null, quality, delay, priority, null, name_proc, applies, blocked_by)

/// Using a held item of `held_type` on the holder, which keeps the item. Handler (mob/user, obj/item/held).
/proc/cap_use_on(name, held_type, handler, behind = NONE, locked_by = NONE, needs, else_say, works_broken = FALSE, works_unpowered = FALSE, log, list/form, priority, stance, name_proc, applies, blocked_by = NONE)
	return cap_entry("use_on", name, handler, behind, locked_by, needs, else_say, works_broken, works_unpowered, log, form, held_type, null, null, priority, stance, name_proc, applies, blocked_by)

/// Putting a held item of `held_type` into the holder (the handler adopts it: own_set moves it).
/proc/cap_insert(name, held_type, handler, behind = NONE, locked_by = NONE, needs, else_say, works_broken = FALSE, works_unpowered = TRUE, log, list/form, priority, name_proc, applies, blocked_by = NONE)
	return cap_entry("insert", name, handler, behind, locked_by, needs, else_say, works_broken, works_unpowered, log, form, held_type, null, null, priority, null, name_proc, applies, blocked_by)
