// The items-wave entries (doc/rewrite/migration_guide.md A3/A4): what an item does when it is used on
// ITSELF (cap_use_self, replaces attack_self) and when it is used on ANOTHER atom (cap_use_at, replaces
// afterattack and the use-on-target half of attack()).
//
// cap_use_self is an ordinary capability entry on the item (target = held = the item), run from
// attack_self() through the INTERACTION_ENTRY_SELF path; the handler is (mob/user, ...form args).
//
// cap_use_at is different: the item is the HOLDER and the atom clicked is the TARGET, so it is never a
// candidate on the target's own entry list. The click path (`/obj/item/proc/after_click`, called where
// afterattack used to be) asks the held item for its use_at entries (cap_use_at_try). Order of a click:
// resolve_attackby() -> the target's attackby() first (an ordinary attackby on the target still
// happens, and a consumed result stops here, as before) -> only then the item's use_at entries ->
// only if none answered, the legacy afterattack(). A matching entry that is gated (not in hand,
// needs, broken...) tells the user why and uses the input up, like a legacy handler that spoke and
// returned; a handler returning FALSE (not null, not truthy) declines and the next entry / afterattack
// runs. The dispatch context has target = the clicked atom and held = the item; dispatch marks changed,
// fingerprints and logs the ITEM (the holder). The clicked target is marked only if the handler says so
// with changed(target).

/// A held item used on itself (attack_self, the Z key): the holder is the item, which must be in the
/// actor's hands (needs cap_in_hand; `in_inventory = TRUE` also accepts a worn item, for a native verb).
/// Runs from attack_self() (INTERACTION_ENTRY_SELF), not from clicks on the item, so an empty hand still
/// picks it up. Answers INPUT_ACTION_SELF_USE. Handler on the item: (mob/user, ...form answers).
/// Gating arguments as cap_hand() (works_broken/unpowered default FALSE); `entry_type` lets a library
/// capability give the entry its own why_not(). A real op: `key` (default: the snake_case name), ACT_USE (the
/// GESTURE_SELF action) offering req_self_held(), so a click on the item never means it; `priority` orders it among the
/// item's other self-uses.
/proc/cap_use_self(name, handler, behind = NONE, locked_by = NONE, needs, else_say, works_broken = FALSE, works_unpowered = FALSE, log, list/form, priority, name_proc, applies, blocked_by = NONE, delay, cooldown, in_inventory = FALSE, entry_type = /datum/interaction/capability, key)
	var/datum/capability/entry/C = new
	var/datum/interaction/capability/E = new entry_type
	var/list/all_needs = list(in_inventory ? GLOBAL_PROC_REF(cap_in_inventory) : GLOBAL_PROC_REF(cap_in_hand))
	if(needs)
		all_needs += needs
	E.name = name
	E.id = "use_self:[name]:[own_proc_name(handler)]"
	E.handler = handler
	E.behind = behind
	E.blocked_by = blocked_by
	E.locked_by = locked_by
	E.needs = all_needs
	E.else_say = else_say
	E.works_broken = works_broken
	E.works_unpowered = works_unpowered
	E.log = log
	E.form = form
	E.name_proc = name_proc
	E.applies = applies
	E.priority = priority || 0
	E.passes_held = FALSE
	E.cooldown = cooldown
	E.duration = delay || 0
	E.entry = INTERACTION_ENTRY_SELF
	E.category = INTERACTION_CAT_TOGGLE
	E.default_action = INPUT_ACTION_SELF_USE
	E.cap = C
	op_attach(E, key || replacetext(lowertext("[name]"), " ", "_"), ACT_USE, priority || 0, offered = req_self_held())
	C.entry = E // ALLOW(ownership): C is the capability entry wrapper being built here: its entry is set once before the wrapper is shared, not an owned relation
	C.key = E.id
	C.behind = behind
	C.locked_by = locked_by
	C.log = log
	return C

/// needs: the holder (an item) is on the actor: held or worn.
/proc/cap_in_inventory(mob/user, atom/holder, obj/item/held)
	return dq_interaction_in_inventory(user, holder, held) ? TRUE : "you need to be carrying it"

/// The held item used on another atom. Handler on the item: (mob/user, atom/target, ...form answers).
/// range 1 is adjacent only; a larger range also fires at a target up to that many tiles away (the old
/// afterattack with proximity FALSE). target_types (a type or a list) limits what may be clicked.
/// Gating arguments as cap_hand(); the gate reads the ITEM's state bits.
/proc/cap_use_at(name, handler, range = 1, target_types, behind = NONE, locked_by = NONE, needs, else_say, works_broken = FALSE, works_unpowered = FALSE, log, list/form, priority, name_proc, applies, blocked_by = NONE, cooldown)
	var/datum/capability/entry/use_at/C = new
	var/datum/interaction/capability/use_at/E = new
	E.name = name
	E.id = "use_at:[name]:[own_proc_name(handler)]"
	E.handler = handler
	E.range = range
	E.target_types = target_types
	E.behind = behind
	E.blocked_by = blocked_by
	E.locked_by = locked_by
	E.needs = needs
	E.else_say = else_say
	E.works_broken = works_broken
	E.works_unpowered = works_unpowered
	E.log = log
	E.form = form
	E.name_proc = name_proc
	E.applies = applies
	E.priority = priority || 0
	E.passes_held = FALSE
	E.cooldown = cooldown
	E.passes_target = TRUE
	E.category = INTERACTION_CAT_TOGGLE
	E.cap = C
	C.entry = E // ALLOW(ownership): C is the capability entry wrapper being built here: its entry is set once before the wrapper is shared, not an owned relation
	C.key = E.id
	C.behind = behind
	C.locked_by = locked_by
	C.log = log
	return C

/// A capability made of one use_at entry. It has no interactions on its holder: the entry is offered
/// only by cap_use_at_try().
/datum/capability/entry/use_at

/datum/capability/entry/use_at/interactions(atom/holder)
	return list()

/// An entry whose holder is the held item and whose target is the clicked atom.
/datum/interaction/capability/use_at
	/// Furthest tile distance it fires at; 1 = adjacent only.
	var/range = 1
	/// A type or list of types the clicked atom must be (null: anything).
	var/target_types

/datum/interaction/capability/use_at/holder_of(datum/dispatch_context/ctx)
	return ctx.held

/// Whether a click at `target` from `actor` (proximity: adjacent) is one this entry answers.
/datum/interaction/capability/use_at/proc/matches(mob/actor, atom/target, proximity)
	if(!proximity)
		if(range <= 1 || target.z != actor.z || get_dist(actor, target) > range)
			return FALSE
	if(target_types)
		var/list/types = islist(target_types) ? target_types : list(target_types)
		var/found = FALSE
		for(var/path in types)
			if(istype(target, path))
				found = TRUE
				break
		if(!found)
			return FALSE
	return TRUE

/// `held` is the holder here (the item in hand), `target` the clicked atom.
/datum/interaction/capability/use_at/why_not(mob/actor, atom/target, obj/item/held)
	if(!held)
		return "you're not holding anything"
	if(!dq_interaction_self_reach(actor, held, held))
		return "it's not in your hand"
	return cap_gate_reason(held, actor, held, src)

/datum/interaction/capability/use_at/applies_to(atom/target)
	return TRUE

/// Runs it for actor clicking target with held: the holder hook, then the dispatch (target = target).
/datum/interaction/capability/use_at/run_effect(mob/actor, atom/target, obj/item/held)
	if(!held.before_entry(actor, src, held))
		return UI_REFUSED
	var/datum/dispatch_context/ctx = new(actor, target, held, src)
	. = cap_dispatch(ctx)
	if(isnull(.))
		. = TRUE // returned nothing, or went async to ask

/// The item's use_at entries for a click on `target`, or a used-up input: TRUE when one answered (or told
/// the user why it could not). FALSE lets the legacy afterattack() run.
/proc/cap_use_at_try(obj/item/holder, atom/target, mob/user, proximity)
	if(!length(caps_all(holder)) || caps_suspended(holder))
		return FALSE
	for(var/datum/capability/C as anything in caps_all(holder))
		if(!istype(C, /datum/capability/entry/use_at))
			continue
		var/datum/capability/entry/use_at/U = C
		var/datum/interaction/capability/use_at/E = U.entry
		if(!istype(E) || !E.matches(user, target, proximity))
			continue
		if(E.applies && !holder_call(holder, E.applies))
			continue
		var/reason = E.why_not(user, target, holder)
		if(reason)
			E.tell_blocked(user, holder, reason)
			return TRUE
		var/result = E.run_effect(user, target, holder)
		if(result != FALSE)
			return TRUE
	return FALSE

/// Where afterattack() used to be called from a click: the item's use_at entries, else afterattack().
/proc/after_click(obj/item/holder, atom/target, mob/user, proximity_flag, click_parameters, stance = I_HURT)
	if(cap_use_at_try(holder, target, user, proximity_flag))
		return
	holder.afterattack(target, user, proximity_flag, click_parameters, stance)
