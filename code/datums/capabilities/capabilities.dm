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
	SHOULD_CALL_PARENT(TRUE)
	RETURN_TYPE(/list)
	return list()

/// The cached capability list of A's type. Shared: never write into it.
/proc/caps_of(atom/A)
	RETURN_TYPE(/list)
	return type_list(A, TYPE_PROC_REF(/atom, capabilities), GLOBAL_PROC_REF(caps_intern_list))

/// Interns every capability of a freshly built list: identical constructor calls anywhere in the tree
/// (a type and each subtype that calls ..(), or two types with the same settings) share ONE datum, so
/// its built entries and their compiled predicates are shared too (the flyweight, review 2 H2).
/proc/caps_intern_list(list/built)
	. = list()
	var/list/at_key = list()
	for(var/entry in built)
		if(istype(entry, /datum/capability/refine))
			cap_apply_refine(., at_key, entry)
			continue
		if(!istype(entry, /datum/capability))
			. += entry
			continue
		var/datum/capability/C = cap_intern(entry)
		// One capability per key: a later entry with the same key replaces the earlier one in its
		// position (a bundle's plain panel is replaced by maintenance_hatch()'s gated one).
		var/slot = at_key["[C.key]"]
		if(slot)
			// An op key declared twice is an init error, unless the later one says replace = TRUE
			// (or is a refine(), handled above): two ops of one key silently shadowing each other is a bug.
			if(cap_op_key_conflict(C, .[slot]))
				stack_trace("duplicate op key '[cap_op_of(C).key]' in one capabilities() list: use refine() or replace = TRUE")
			.[slot] = C
			continue
		. += C
		at_key["[C.key]"] = length(.)

/// Applies refine() R to the op it names in list `into` (at_key: key -> position).
/proc/cap_apply_refine(list/into, list/at_key, datum/capability/refine/R)
	var/slot = at_key["op:[R.base_key]"]
	if(!slot)
		stack_trace("refine('[R.base_key]') refines an op nothing declared")
		return
	var/datum/capability/refined = cap_intern(cap_op_refined(into[slot], R))
	into[slot] = refined

/// The shared capability equal to C (same type, same saved settings), registering C if it's new.
/proc/cap_intern(datum/capability/C)
	var/signature = datum_signature(C)
	var/datum/capability/known = GLOB.caps_interned[signature]
	if(known)
		return known
	GLOB.caps_interned[signature] = C
	return C

/// signature -> the one shared capability with those settings.
GLOBAL_LIST_EMPTY(caps_interned)

/// The capability of A with this key (a type, or an explicit key), or null.
/proc/cap_of(atom/A, key)
	for(var/datum/capability/C as anything in caps_all(A))
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
	if(isnull(on))
		CRASH("cap_set: `on` is required (TRUE to set, FALSE to clear) for [A?.type]")
	var/was = A.cap_state
	if(on)
		A.cap_state |= bits
	else
		A.cap_state &= ~bits
	if(was == A.cap_state)
		return FALSE
	changed(A, CHANGE_CAPABILITY)
	// Waiting operations watch cap_state through their requirements' reads (operations/op_ctx.dm).
	op_reads_changed(A, OP_KEY_CAP_STATE)
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
/**
 * Whether A's screen or lamps show: it has power, isn't broken and nothing overrides its display
 * (screen_override()). What a lamp or glow draws behind, so every machine answers it the same way.
 */
/proc/is_lit(atom/A)
	return A.cap_powered() && !is_broken(A) && !A.screen_override()

/// TRUE while something other than power or damage keeps the screen from showing its normal display: a
/// bluescreen from a hack or an emag, unsecured electronics. Types with such a state override it; is_lit() reads it.
/atom/proc/screen_override()
	return FALSE

/// The wires capability's wires are exposed when everything they sit behind is open; without one,
/// the CAP_WIRES_EXPOSED bit answers.
/proc/wires_exposed(atom/A)
	var/datum/capability/wires/W = cap_of(A, /datum/capability/wires)
	if(W)
		return (A.cap_state & W.behind) == W.behind
	return !!(A.cap_state & CAP_WIRES_EXPOSED)

/**
 * Verbs this type has by what it is, beyond the /type/verb/ procs it inherits: a per-type list
 * (built once, no per-instance entry), read by the verb store. For a difference between types that
 * never changes per instance (an advanced scanner has the toggle, a basic one doesn't); state that
 * changes uses hidden_verbs(). Pure: read only initial() values here.
 *	/obj/item/healthanalyzer/type_verbs()
 *		. = ..()
 *		if(initial(profile_type) != /datum/diagnostic_profile/health_analyzer)
 *			. += /obj/item/healthanalyzer/proc/toggle_adv
 */
/atom/proc/type_verbs()
	SHOULD_CALL_PARENT(TRUE)
	RETURN_TYPE(/list)
	return list()

/// Whether A has power for its entries. Machines answer through their power state; anything else
/// is always powered. The powered capability overrides nothing: it reads this.
/atom/proc/cap_powered()
	return TRUE

/obj/machinery/cap_powered()
	return !(stat & NOPOWER)

// ---- lifecycle hooks ----

/// Runs every capability's on_init, then queues the first refresh when the type may derive something.
/// Called from /atom/Initialize() and table_initialize() after the declarations. Nothing derived is
/// probed here (review 2 H9: a draw() may read what the subtype's Initialize() sets up after ..()):
/// the first instance of each type is always queued, and its refresh records what the type derives.
/atom/proc/caps_init(mapload)
	var/flags = type_derive_flags(src)
	if(flags & TYPE_DERIVES_TYPE_VERBS)
		verb_store_refresh(src, type_list(src, TYPE_PROC_REF(/atom, type_verbs)))
	if(flags & TYPE_DERIVES_CAPS)
		for(var/datum/capability/C as anything in caps_of(src))
			C.on_holder_init(src, mapload)
			cap_join_systems(src, C)
		refresh_granted_verbs(src) // capability verbs are there from init, not a frame later
	if(flags & TYPE_DERIVES_DEPS)
		derived_attach(src)
	if(rx_type_enrols(src))
		rx_enrol(src) // per-instance every() work (reactions/work.dm)
	if(flags || periodic_cadence || periodic_interval)
		// The first refresh is queued, nothing changed: changed() would raise CHANGE_EXPLICIT, which every machine's
		// pipeline wakes on (wake_all), so declaring a capability or a membership woke its holder at init.
		refresh_mark(src, DEP_ALL)

/// TYPE_DERIVES_* known so far for A's type. A type seen for the first time is TYPE_DERIVES_PENDING
/// (plus CAPS when it has capabilities) until its first refresh fills in LOOK and VERBS.
/proc/type_derive_flags(atom/A)
	var/known = GLOB.type_derives_cache[A.type]
	if(!isnull(known))
		return known
	. = TYPE_DERIVES_PENDING
	if(length(caps_of(A)))
		. |= TYPE_DERIVES_CAPS
	if(length(type_list(A, TYPE_PROC_REF(/atom, type_verbs))))
		. |= TYPE_DERIVES_TYPE_VERBS
	if(derived_table_of(A))
		. |= TYPE_DERIVES_DEPS
	GLOB.type_derives_cache[A.type] = .

/// A refresh of A just ran draw() and hidden_verbs(): record what its type derives (first time only).
/proc/type_derive_record(atom/A, drew, hid)
	var/flags = GLOB.type_derives_cache[A.type]
	if(isnull(flags) || !(flags & TYPE_DERIVES_PENDING))
		return
	flags &= ~TYPE_DERIVES_PENDING
	if(drew)
		flags |= TYPE_DERIVES_LOOK
	if(hid)
		flags |= TYPE_DERIVES_VERBS
	GLOB.type_derives_cache[A.type] = flags

/// Whether A's type derives anything the refresh engine keeps up (a look or hidden verbs; unknown yet
/// counts as yes).
/proc/type_derives(atom/A)
	return !!(type_derive_flags(A) & (TYPE_DERIVES_LOOK | TYPE_DERIVES_VERBS | TYPE_DERIVES_CAPS | TYPE_DERIVES_PENDING))

GLOBAL_LIST_EMPTY(type_derives_cache)

/// Runs every capability's on_destroy and drops the data. Called from /atom/Destroy().
/atom/proc/caps_destroy()
	if(timed_until)
		timed_cancel_all(src)
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


/// Examine lines from every capability, in list order (appended by /atom/examine()).
/atom/proc/caps_examine(mob/user)
	. = list()
	for(var/datum/capability/C as anything in caps_ordered(src, CAP_ORDER_EXAMINE))
		var/list/lines = C.examine(src, user)
		if(lines)
			. += lines

/// Adds every capability's UI data under data["caps"][C.ui_key()], one list per capability, so no
/// capability key collides with the holder's own (M11). /datum/tgui_data() callers merge it through ..().
/atom/proc/caps_ui_data(mob/user, list/data)
	var/list/caps
	for(var/datum/capability/C as anything in caps_all(src))
		var/list/mine = list()
		C.ui_data(src, user, mine)
		if(!length(mine))
			continue
		caps ||= list()
		caps[C.ui_key()] = mine
	if(caps)
		data["caps"] = caps

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

/// C's entries, built on first use. Ids are unique per target (run_chosen_interaction() resolves a
/// Menu choice among the target's own interactions), so entries of different types may share one.
/proc/cap_built_entries(datum/capability/C, atom/A)
	if(isnull(C.built_entries))
		C.built_entries = C.interactions(A) || list()
		for(var/datum/interaction/capability/E as anything in C.built_entries)
			if(!E.cap)
				E.cap = C
			cap_apply_gating(C, E)
	return C.built_entries

// ---- gating ----

/**
 * Why `entry` (a capability entry of A) can't run for user now, or null. Order: broken, unpowered,
 * behind (needs the bits SET), blocked_by (needs them CLEAR: "only while the cover is closed"),
 * locked_by, needs (global chk_* refs or holder procs: library/checks.dm), then every capability's gate() (the cover, the lock, a slot's rules).
 */
/**
 * Why an operation used at compartment `bay` (BAY_*) on `holder` is refused right now, or null: the ONE
 * place the boundary is asked (op_ctx stage 2 and cap_gate_reason() both come here). Asks the holder's
 * boundary capability, passes(ctx.route, ctx), with the operation context. With no context (a caller that
 * has no attempt to describe) the question is asked of a short-lived context of the holder itself.
 * A holder that declares no such bay refuses an op (fails closed) and lets a context-less legacy entry through.
 */
/proc/op_at_reason(atom/holder, bay, datum/op_ctx/ctx)
	var/datum/capability/compartment/boundary = compartment_of(holder, bay)
	if(!boundary)
		return ctx?.op ? /datum/msg/req_sealed : null
	var/datum/op_ctx/asked = ctx
	if(!asked)
		asked = op_ctx_take(null, holder)
	asked.reason = null
	if(!boundary.passes(asked.route, asked))
		. = asked.reason || /datum/msg/req_sealed
	if(asked != ctx)
		asked.release()

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
	if(entry.cooldown && A.entry_cooldowns?[entry.id] > world.time)
		return "it isn't ready yet"
	if(entry.blocked_by & A.cap_state)
		var/present = entry.blocked_by & A.cap_state
		if(present & CAP_COVER_OPEN)
			return "close the cover first"
		if(present & CAP_PANEL_OPEN)
			return "close the maintenance panel first"
		return "you can't do that in its current state"
	if(entry.locked_by && (A.cap_state & entry.locked_by))
		return "it's locked"
	if(entry.at && !entry.op)
		// An op entry's compartment is asked in its context's route stage; only legacy entries ask here.
		var/datum/op_ctx/asked = op_ctx_take(user, A, held, null, GLOB.op_route_now)
		var/at_reason = op_at_reason(A, entry.at, asked)
		asked.release()
		if(at_reason)
			return at_reason
	var/needs_reason = cap_needs_reason(A, user, held, entry.needs, entry.else_say)
	if(needs_reason)
		return needs_reason
	for(var/datum/capability/C as anything in caps_all(A))
		var/reason = C.gate(A, user, entry)
		if(reason)
			return reason
	return null

// ---- the capability interaction entry ----

/// An interaction offered by a capability. Shared per (type, capability); per-instance state lives
/// on the holder. The handler is a proc on the holder, (mob/user, obj/item/held, ...named form answers).
/datum/interaction/capability
	/// The capability that built this entry (tmp: a back reference, not part of its settings).
	var/tmp/datum/capability/cap
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
	/// The compartment (BAY_*) this entry is used at, or null: the dispatcher asks op_at_reason().
	var/at
	/// Deciseconds after a success before this entry works again on the same holder (a per-holder,
	/// per-entry cooldown owned by the framework: no COOLDOWN_DECLARE trio in the type).
	var/cooldown
	/// Whether the handler takes the held item: (mob/user, obj/item/held, ...). hand() handlers are
	/// (mob/user, ...); tool()/use_on()/insert() and library item entries pass `held`.
	var/passes_held = TRUE
	/// Whether the handler takes the clicked atom as `target` (use_at entries: (mob/user, atom/target, ...)).
	var/passes_target = FALSE
	/// Whether the handler also gets its capability as the named arg `cap` (review 2 M15: a handler
	/// that serves several capability instances is told which, never looks it up after a sleep).
	var/passes_cap = FALSE
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

/// A plain click reaches an op with a `click_with` rule only holding one of those items (a card swiped across a
/// lock); every other gesture and route reaches it with whatever is in hand.
/datum/interaction/capability/is_meant(mob/actor, atom/target, obj/item/held)
	if(op?.click_with && GLOB.op_gesture_now == GESTURE_CLICK && !(held && is_type_in_list(held, op.click_with)))
		return FALSE
	return ..()

/datum/interaction/capability/applies_to(atom/target)
	// A holder can suspend all its capability entries (a frozen airlock): the input falls through to
	// whatever comes next (an attack), as if the entries weren't there.
	if(target.caps_suspended())
		return FALSE
	return applies ? call(target, applies)() : TRUE

/// Why the op is not meant here (its first failing `offered` requirement), or null. Not a refusal: is_meant() falls through on it.
/datum/interaction/capability/proc/offered_reason(mob/actor, atom/target, obj/item/held)
	if(!length(op?.offered))
		return null
	var/datum/op_ctx/asked = op_ctx_take(actor, target, held, op, GLOB.op_route_now)
	for(var/datum/req/R as anything in op.offered)
		var/why = R.test(asked)
		if(why)
			. = req_reason_phrase(why, asked)
			break
	asked.release()

/datum/interaction/capability/is_meant(mob/actor, atom/target, obj/item/held)
	. = ..()
	if(. && length(op?.offered) && offered_reason(actor, target, held))
		return FALSE

/datum/interaction/capability/why_not(mob/actor, atom/target, obj/item/held)
	if(op)
		// A cap_op() entry: the resolver predicate on the physical route (reach, selectors), then the op
		// context's ordered stages, whose target stage is cap_gate_reason() (operations/op_ctx.dm).
		var/why = GLOB.op_route_now == ROUTE_PHYSICAL ? ..() : null
		return op_entry_reason(src, actor, target, held, why || offered_reason(actor, target, held))
	. = ..()
	if(.)
		return
	return cap_gate_reason(target, actor, held, src)

/datum/interaction/capability/run_effect(mob/actor, atom/target, obj/item/held)
	// The holder-wide hook with side effects (the airlock's shock) runs only here, never while the
	// Menu is built: FALSE stops the entry (the input is used).
	if(!target.before_entry(actor, src, held))
		return UI_REFUSED
	var/datum/op_ctx/octx
	if(op)
		octx = op_ctx_take(actor, target, held, op, GLOB.op_route_now)
		// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
		octx.entry = src
		var/veto = op_before(octx)
		if(!isnull(veto))
			op_refusal_told(octx, veto)
			octx.release()
			return UI_REFUSED
	var/datum/dispatch_context/ctx = new(actor, target, held, src)
	. = cap_dispatch(ctx)
	var/asked = isnull(.) && length(form)
	if(isnull(.))
		. = TRUE // a handler that returned nothing (or went async to ask) handled it
	if(octx)
		// after_op reactions run only for an operation that committed: not a refused handler, and not one
		// still asking its form (its handler finishes later, on its own).
		if(!asked && dispatch_succeeded(.))
			op_after(octx)
		octx.release()

/// The atom whose capability this entry is, for a dispatch: the target, except a use_at entry (the held item).
/datum/interaction/capability/proc/holder_of(datum/dispatch_context/ctx)
	return ctx.target
/atom
	/// entry id -> world.time when a capability entry's cooldown ends (entry `cooldown =`). Lazy.
	var/tmp/list/entry_cooldowns

/// Starts entry E's cooldown on A (after a success).
/proc/cap_entry_cooldown_start(atom/A, datum/interaction/capability/E)
	if(!E?.cooldown || QDELETED(A))
		return
	LAZYSET(A.entry_cooldowns, E.id, world.time + E.cooldown)

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

/// Runs the entry's form and handler for ctx, async when it prompts (dispatch_call()). The handler runs
/// on, and the dispatch marks/fingerprints/logs, the entry's HOLDER (holder_of(): the target, except a
/// use_at entry, whose holder is the held item).
/proc/cap_dispatch(datum/dispatch_context/ctx)
	var/datum/interaction/capability/E = ctx.entry
	var/list/named = list("user" = ctx.user)
	if(E.passes_held)
		named["held"] = ctx.held
	if(E.passes_target)
		named["target"] = ctx.target
	if(E.passes_cap)
		named["cap"] = E.cap
	if(length(E.form))
		return cap_dispatch_form(ctx, named)
	return dispatch_call(ctx, E.holder_of(ctx), E.handler, named, E.name, E.log)

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
	if(E.passes_cap)
		named["cap"] = E.cap
	else
		named -= "cap"
	if(E.passes_target)
		named["target"] = ctx.target
	dispatch_call(ctx, E.holder_of(ctx), E.handler, named, E.name, E.log)

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
	E.at ||= C.at

/// Sets the standard gating arguments on capability C (every library constructor calls it with its
/// own same-named arguments). Returns C.
/proc/cap_gating(datum/capability/C, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, at)
	C.behind = behind
	C.blocked_by = blocked_by
	C.locked_by = locked_by
	C.needs = needs
	C.else_say = else_say
	C.works_broken = works_broken
	C.works_unpowered = works_unpowered
	C.log = log
	C.at = at
	return C

// ---- the bespoke entries: small capabilities ----

/// A capability that is just one entry.
/datum/capability/entry
	var/datum/interaction/capability/entry

/datum/capability/entry/interactions(atom/holder)
	return list(entry)

/// Shared constructor body for hand()/tool()/use_on()/insert().
/proc/cap_entry(entry_kind, name, handler, behind, locked_by, needs, else_say, works_broken, works_unpowered, log, list/form, held_type, tool_quality, delay, priority, stance, name_proc, applies, blocked_by, cooldown, fuel = 0, volume)
	var/datum/capability/entry/C = new
	var/datum/interaction/capability/E = new
	E.name = name
	E.id = "[entry_kind]:[name]:[handler]"
	E.handler = handler
	E.behind = behind
	E.blocked_by = blocked_by
	E.passes_held = entry_kind != "hand"
	E.cooldown = cooldown
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
			E.tool_amount = fuel || 0
			if(!isnull(volume))
				E.tool_volume = volume
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
	E.duration = delay || 0
	E.apply_stance_tags()
	C.entry = E
	C.key = E.id
	C.behind = behind
	C.locked_by = locked_by
	C.log = log
	return C

// ---- periodic work from capabilities (cadence / cap_should_run / cap_periodic_step) ----

/// Any capability with periodic work that wants to run keeps the holder stepping.
/atom/should_run()
	. = ..()
	if(. || !(type_derive_flags(src) & TYPE_DERIVES_CAPS))
		return
	for(var/datum/capability/C as anything in caps_all(src))
		if(C.cadence && C.cap_should_run(src))
			return TRUE
	return FALSE

/// Steps every capability whose periodic work wants to run. A type with its own periodic_step()
/// calls ..() to keep its capabilities stepping.
/atom/periodic_step(delta)
	if(!(type_derive_flags(src) & TYPE_DERIVES_CAPS))
		return PROCESS_KILL
	var/stepped = FALSE
	for(var/datum/capability/C as anything in caps_all(src))
		if(C.cadence && C.cap_should_run(src))
			C.cap_periodic_step(src, delta)
			stepped = TRUE
	if(!stepped)
		return PROCESS_KILL
