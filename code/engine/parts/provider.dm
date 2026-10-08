#define HANDS_KEY "working_hands"

// Providers, the actor gate and the reach gate (doc/rewrite/final_api.html, section 8 "Origin, reach, provider, authority and channel", "Who may
// act, and what they can reach"; section 19 "E2, parts").
//
// Five separate facts describe an input: origin, reach policy, provider, authority and channel. A PROVIDER is what performs an op: a hand, a
// held tool, a telekinesis mutation, a robot's interface. It is declared where it comes from (provides(AFF_X, reach =, line_of_sight =,
// authority =, accepts =) in a capability or an item's own declarations), and the gates read what the actor and the held item provide now:
//
//   Actor gate. The origin the input arrived on has to be in the actor's acts_via mask (ORIGIN_SYSTEM is not masked); an op with a physical
//   binding also gets an implicit req_capable().
//   Reach gate. For REACH_ADJACENT: collect the candidate providers, take the largest reach among them, ask whether the target is that near,
//   walk the containment chain from the target up to the first container the actor can touch (every bay on the way exposed), then each op
//   checks its own provider. REACH_RANGE(n) and REACH_VIEW skip the two distance steps; the exposure walk applies to every spatial policy.
//
// There is no hand provider on /mob/living: a species with hands grants hands() (provides(AFF_MANIPULATE | AFF_ATTACK | AFF_HOLD, reach = 1)),
// a mob with no species declares its own. The provider that performs an op is the held item's, then the hand, then any other by shortest reach.

/// A provider declaration: what its holder can do for an actor. Interned like every entry.
/proc/provides(aff, reach = null, line_of_sight = FALSE, authority = AUTH_PHYSICAL, accepts = null, key = null)
	return entry_make(ENTRY_PROVIDES, key, list("aff" = aff, "reach" = reach, "los" = line_of_sight, "authority" = authority, "accepts" = accepts))

/// hands(): the hand provider a species grants: provides(AFF_MANIPULATE | AFF_ATTACK | AFF_HOLD, reach = 1) while the body has a working hand
/// (when(PROC_REF(has_working_hand), ...), hands.dm). The condition is read when the provider set is read; what changes it (a limb attached or lost)
/// publishes HANDS_KEY and bumps the actor's provider set generation (hands_refresh()), so a cached menu is stale at once.
/proc/hands()
	return when(TYPE_PROC_REF(/datum, can_provide_hands), provides(AFF_MANIPULATE | AFF_ATTACK | AFF_HOLD, reach = 1), reads = list(HANDS_KEY))

/// One provider in play: the declaration and the entity that gives it.
/datum/prov
	var/datum/entry/entry
	var/datum/source

/// The engine for provides entries of a granted capability: the actor's provider set changed.
/datum/entry_engine/provides
	kind = ENTRY_PROVIDES

/datum/entry_engine/provides/apply(datum/activation/A, datum/entry/E, datum/centry/C)
	provider_set_changed(A.holder)
	return TRUE

/datum/entry_engine/provides/remove(datum/activation/A, datum/entry/E)
	provider_set_changed(A.holder)

/datum/rx_state
	/// The provider set generation: bumped when an activation with provides attaches or detaches (menus and reach walks key on it).
	var/provider_gen = 0
	/// The act generation: bumped when a published key, relation or containment of this entity changes (caches key on it).
	var/act_gen = 0
	/// The waiting claiming op (claims()) that holds this entity, or null.
	var/datum/pending_op/claimed_by

/proc/provider_set_changed(datum/D)
	if(!D)
		return
	var/datum/rx_state/S = rx_of(D)
	S.provider_gen++
	S.act_gen++

/// The provider set generation of an entity.
/proc/provider_gen_of(datum/D)
	return D?.rx ? D.rx.provider_gen : 0

/// The act generation of an entity.
/proc/act_gen_of(datum/D)
	return D?.rx ? D.rx.act_gen : 0

/// An entity's state state_changed (a published key, a relation, a stat, its contents or its place): the menus cached on its generation are unreachable now.
/// An entity nobody has asked about yet has no record and nothing cached on it.
/proc/op_changed(datum/D)
	if(D?.rx)
		D.rx.act_gen++

/// A thing entered or left a container (or a turf): it and the container have changed what an op can reach, and a wait that keeps it in place re-checks.
/proc/op_moved(atom/movable/AM, atom/container)
	var/datum/rx_state/moved_state = AM.rx
	if(moved_state)
		moved_state.act_gen++
		if(moved_state.observed?[OP_KEEP_MOVED])
			publish_change(AM, OP_KEEP_MOVED)
	if(isturf(container))
		return
	var/datum/rx_state/container_state = container.rx
	if(container_state)
		container_state.act_gen++
		if(container_state.observed?[OP_KEEP_HAND])
			publish_change(container, OP_KEEP_HAND)

/// A keep of a waiting op on `D` state_changed (the actor swapped hands): published when something watches it.
/proc/op_keep_poke(datum/D, key)
	if(D.rx?.observed?[key])
		publish_change(D, key)

/// The providers an actor holding `held` has now: its own table's, its live activations', the held item's, and the carrier's (what holds `held` for
/// the actor: a cyborg's gripper). Each is a /datum/prov.
/proc/providers_for(mob/actor, obj/held)
	. = list()
	if(actor && !QDELETED(actor))
		provider_collect(actor, actor, .)
		var/obj/carrier = actor.held_carrier()
		if(carrier && carrier != held && !QDELETED(carrier))
			provider_collect(carrier, carrier, .)
	if(held && !QDELETED(held) && op_item_like(held)) // a dragged mob is no provider
		provider_collect(held, held, .)

/// What the actor's ops see as its held item (A.held): what is in its active hand. A cyborg with a gripper selected holds what the gripper carries.
/mob/proc/held_for_ops()
	return null

/// The item that carries the actor's held item for it and is a provider in its own right (a cyborg's selected gripper), or null. It counts as the
/// held item when the provider of an op is chosen, and what an op takes out goes into it (op_deliver()).
/mob/proc/held_carrier()
	return null

/// Can this item carry `thing` for `actor` now? An item that provides AFF_HOLD or AFF_HOLD_SMALL and carries things (a gripper) overrides it.
/obj/proc/can_carry(obj/thing, mob/actor)
	return FALSE

/// Carries `thing` for `actor` (it is already out of where it was). TRUE when it holds it now.
/obj/proc/carry(obj/thing, mob/actor)
	return FALSE

/proc/provider_collect(datum/D, datum/source, list/into)
	var/datum/type_table/T = table_of(D)
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_PROVIDES))
		if(op_whens_hold(D, C.whens))
			var/datum/prov/P = new
			P.entry = C.item // ALLOW(ownership): a transient record of one resolution: dropped with it
			P.source = source // ALLOW(ownership): a transient record of one resolution: dropped with it
			into += P
	for(var/datum/activation/A as anything in D.rx?.activations)
		if(A.dead || !A.runs)
			continue
		if(T.caps[A.def.key])
			continue // a type-level capability: its entries are in the table already
		for(var/datum/centry/C as anything in activation_plan(A.def))
			var/datum/entry/E = C.item
			if(istype(E) && E.kind == ENTRY_PROVIDES && op_whens_hold(D, C.whens))
				var/datum/prov/P = new
				P.entry = E // ALLOW(ownership): a transient record of one resolution: dropped with it
				P.source = source // ALLOW(ownership): a transient record of one resolution: dropped with it
				into += P

/// Do the when() blocks an entry sits inside all hold on `holder`? (Evaluated when read: a condition used for matching.)
/proc/op_whens_hold(datum/holder, list/whens)
	for(var/datum/entry/W as anything in whens)
		if(!condition_holds(holder, W.args["cond"]))
			return FALSE
	return TRUE

/datum/prov/proc/aff()
	return entry.args["aff"] || 0

/datum/prov/proc/reach()
	return entry.args["reach"]

/datum/prov/proc/authority_mask()
	return entry.args["authority"] || AUTH_PHYSICAL

/// Does the provider accept `thing` (a hold filter: provides(accepts = list(types)))? No filter: anything.
/datum/prov/proc/accepts(thing)
	var/list/filter = entry.args["accepts"]
	if(!length(filter))
		return TRUE
	for(var/path in filter)
		if(istype(thing, path))
			return TRUE
	return FALSE

// ---- the actor gate ----

/// The authority an actor's clicks and menu picks carry (what its providers give: a mob with hands, AUTH_PHYSICAL; an AI's interface,
/// AUTH_REMOTE_ACCESS; a cyborg's gripper and interface, both). The mob's own choice: /mob/proc/click_authority().
/proc/actor_authority(mob/actor)
	return actor ? actor.click_authority() : AUTH_PHYSICAL

/// The authority this mob's clicks and menu picks carry. A silicon overrides it (code/library/mob/silicon.dm).
/mob/proc/click_authority()
	return AUTH_PHYSICAL

/// Can this mob see `target` for a REACH_VIEW op (a remote() op on what it sees)? An AI sees through its cameras (silicon.dm).
/mob/proc/reach_view_sees(atom/target)
	var/turf/here = get_turf(src)
	return here && (target in dview(world.view, here)) // dview(): a dark room is still seen, as in reach_line_clear()

/// The mask of origins the actor can act through (acts_via), ORIGIN_ALL for what has none.
/proc/actor_acts_via(mob/actor)
	if(actor?.op_uses_actor_stats())
		var/mask = stat_value(actor, STAT_ACTS_VIA)
		return isnull(mask) ? ORIGIN_ALL : mask
	return ORIGIN_ALL

/// The reason the actor gate drops an input of `origin`, or null when it passes. ORIGIN_SYSTEM is never masked, AUTH_ADMIN bypasses it.
/proc/actor_gate_reason(mob/actor, origin, authority)
	if(origin == ORIGIN_SYSTEM || (authority & AUTH_ADMIN) || !actor)
		return null
	if(actor_acts_via(actor) & origin)
		return null
	return stat_hold_reason(actor, STAT_ACTS_VIA) || /datum/msg/req_not_capable

/// The strongest hold's reason on a stat of an entity, or null (the actor gate shows it: "You can't act from inside it").
/proc/stat_hold_reason(datum/D, stat_id)
	var/datum/stat_def/def = stat_def_of(stat_id)
	if(!def)
		return null
	var/best_priority = null
	var/best_reason = null
	for(var/list/row as anything in D?.rx?.stats?.holds)
		if(row[H_STAT] != def.id || !row[H_REASON])
			continue
		if(isnull(best_priority) || row[H_PRIORITY] > best_priority)
			best_priority = row[H_PRIORITY]
			best_reason = row[H_REASON]
	return best_reason

// ---- the reach gate ----

/// The container of `target` the actor can touch: the target itself when it is on a turf or on the actor, else the outermost thing up the
/// chain before a turf (a locker's contents are reached through the locker). Null when the chain never reaches the actor's surroundings.
/proc/reach_surface(mob/actor, atom/target)
	if(!isatom(target))
		return null
	var/atom/at = target
	while(at.loc && !isturf(at) && !isturf(at.loc)) // a turf is its own surface (its loc is an area, which is nothing to touch)
		if(at.loc == actor)
			return at
		at = at.loc
	return at

/// The reason an op of `plan` cannot reach `target`, or null when it can, and the provider that does it (set in `chosen`). Providers are
/// the actor's and the held item's now.
/proc/reach_gate(mob/actor, atom/target, obj/held, datum/op_plan/P, datum/entry/part/bind/B, authority, list/chosen)
	var/policy = op_reach_policy(P, B)
	var/need = op_affordance(P, B, held)
	var/list/provs = providers_for(actor, held)
	var/list/fits = list()
	// The authority a provider has to carry is the input's narrowed to what the binding accepts: a borg's click carries both physical and remote
	// access, and a hand op takes only its hand, a remote() op only its interface.
	if(!(authority & AUTH_ADMIN))
		var/chosen_authority = LAZYACCESS(P.selects, "authority")
		authority &= isnull(chosen_authority) ? B.authority_mask() : chosen_authority
	for(var/datum/prov/V as anything in provs)
		if(need && (V.aff() & need) != need)
			continue
		if(!(V.authority_mask() & authority) && (policy != REACH_ANY))
			continue
		if(!V.accepts(held))
			continue
		fits += V
	if(need && !length(fits))
		return /datum/msg/op/no_hands
	// Distance (REACH_ADJACENT only), then exposure (every spatial policy), then each op's own provider.
	var/atom/surface = isatom(target) ? reach_surface(actor, target) : null
	var/dist = null
	if(policy == REACH_ADJACENT || policy >= REACH_RANGE_BASE)
		if(!isatom(target))
			return /datum/msg/op/unreachable
		dist = surface ? reach_distance(actor, surface) : null
		if(isnull(dist))
			return /datum/msg/op/unreachable
	switch(policy)
		if(REACH_ADJACENT)
			// Each provider reaches the surface when its reach covers the distance (and a clear line when it asks for one).
			var/list/able = list()
			if(!need && !length(fits))
				// an op that needs nothing of its provider (by(0): a mouse climbing into a bag) reaches what is next to the actor
				if(dist > 1)
					return /datum/msg/op/unreachable
				able = null
			for(var/datum/prov/V as anything in fits)
				var/range = V.reach()
				if(isnull(range) || range < dist)
					continue
				if(V.entry.args["los"] && dist > 0 && !reach_line_clear(actor, surface))
					continue
				able += V
			if(!isnull(able))
				if(!length(able))
					return /datum/msg/op/unreachable
				fits = able
		if(REACH_INSIDE)
			var/inside = FALSE
			if(isatom(target) && actor)
				for(var/atom/up = actor.loc; up; up = up.loc)
					if(up == target)
						inside = TRUE
						break
			if(!inside)
				return /datum/msg/op/unreachable
		if(REACH_VIEW)
			if(!isatom(target) || !actor || !actor.reach_view_sees(target))
				return /datum/msg/op/unreachable
		if(REACH_ANY)
			pass()
		else
			if(policy >= REACH_RANGE_BASE && dist > (policy - REACH_RANGE_BASE))
				return /datum/msg/op/unreachable
	// Exposure: every bay between the target and the surface the actor touches is open for this authority.
	if(isatom(target) && policy != REACH_ANY && policy != REACH_INSIDE)
		var/why = reach_exposure(actor, target, authority)
		if(why)
			return why
	// The provider: the held item's (or its carrier's) first, then the hand, then any other by shortest reach.
	if(length(fits))
		chosen += reach_pick_provider(fits, held, actor?.held_carrier())
	return null

/// The provider that performs an op among `fits`: the held item's (or the carrier's that holds it: a cyborg's gripper), else the shortest reach.
/proc/reach_pick_provider(list/fits, obj/held, obj/carrier = null)
	var/datum/prov/best = null
	for(var/datum/prov/V as anything in fits)
		if(!best)
			best = V
			continue
		var/best_held = (best.source == held) || (carrier && best.source == carrier)
		var/this_held = (V.source == held) || (carrier && V.source == carrier)
		if(this_held != best_held)
			if(this_held)
				best = V
			continue
		var/best_reach = isnull(best.reach()) ? 1000 : best.reach()
		var/this_reach = isnull(V.reach()) ? 1000 : V.reach()
		if(this_reach < best_reach)
			best = V
	return best

/// Chebyshev distance from the actor to the surface the target is reached through, or null on another z-level.
/proc/reach_distance(mob/actor, atom/surface)
	if(!actor)
		return 0
	var/turf/A = get_turf(actor)
	var/turf/B = get_turf(surface)
	if(!A || !B || A.z != B.z)
		return null
	if(surface.loc == actor || surface == actor)
		return 0
	return max(abs(A.x - B.x), abs(A.y - B.y))

/// Is there a clear line from the actor to the surface? (A provider with line_of_sight = TRUE: telekinesis.) The step-towards walk of can_see() asks
/// for opaque turfs and things on the way, not for light: view() would call a dark room unseen.
/proc/reach_line_clear(mob/actor, atom/surface)
	if(!actor)
		return TRUE
	return !!can_see(actor, surface, TK_MAXRANGE)

/// Is the path from the actor to `target` open for `authority` at every container on the way? (A closed cover is part of reach: each container
/// answers space_blocked(), the path through its spaces and doors, code/engine/library/spaces.dm.)
/proc/reach_exposure(mob/actor, atom/target, authority)
	var/atom/at = target
	while(at.loc && !isturf(at) && !isturf(at.loc) && at.loc != actor)
		var/atom/container = at.loc
		var/why = container.space_blocked(at, authority, actor)
		if(why)
			return why
		at = container
	return null

/// The reach policy an op's binding gives: the select reach(), else the binding's own.
/proc/op_reach_policy(datum/op_plan/P, datum/entry/part/bind/B)
	var/chosen = LAZYACCESS(P.selects, "reach")
	return isnull(chosen) ? B.reach_policy() : chosen

/// The affordance mask an op's binding needs of its provider (a tool binding needs the held tool's own).
/proc/op_affordance(datum/op_plan/P, datum/entry/part/bind/B, obj/held)
	var/chosen = LAZYACCESS(P.selects, "by")
	return isnull(chosen) ? B.affordance() : chosen

// ---- what a binding implies (the preset table of section 8) ----

/datum/entry/part/bind/proc/origins()
	switch(bind_kind)
		if(BIND_HAND, BIND_TOOL, BIND_ITEM, BIND_STACK, BIND_IN_HAND, BIND_AT_TARGET, BIND_INSIDE, BIND_TK)
			return ORIGIN_CLICK | ORIGIN_MENU | ORIGIN_AI
		if(BIND_REMOTE)
			return ORIGIN_CLICK | ORIGIN_MENU | ORIGIN_UI
		if(BIND_OBSERVE)
			return ORIGIN_CLICK | ORIGIN_MENU
		if(BIND_MENU)
			return ORIGIN_VERB | ORIGIN_HOTKEY | ORIGIN_MENU
		if(BIND_UI, BIND_TOPIC)
			return ORIGIN_UI
		if(BIND_AI)
			return ORIGIN_AI
		if(BIND_CLICKS)
			return ORIGIN_CLICK
	return ORIGIN_NONE

/datum/entry/part/bind/proc/reach_policy()
	switch(bind_kind)
		if(BIND_INSIDE)
			return REACH_INSIDE
		if(BIND_REMOTE)
			return REACH_VIEW
		if(BIND_MENU, BIND_UI, BIND_TOPIC, BIND_AI, BIND_OBSERVE)
			return REACH_ANY
	return REACH_ADJACENT

/// The affordance bits the provider has to give (0: none needed).
/datum/entry/part/bind/proc/affordance()
	switch(bind_kind)
		if(BIND_HAND, BIND_ITEM, BIND_STACK, BIND_INSIDE)
			return AFF_MANIPULATE
		if(BIND_IN_HAND, BIND_AT_TARGET)
			return AFF_HOLD
		if(BIND_REMOTE)
			return AFF_INTERFACE
		if(BIND_TK)
			return AFF_TELEKINESIS
		if(BIND_OBSERVE)
			return AFF_OBSERVE
	return 0

/datum/entry/part/bind/proc/authority_mask()
	switch(bind_kind)
		if(BIND_REMOTE)
			return AUTH_REMOTE_ACCESS
		if(BIND_UI, BIND_TOPIC)
			return AUTH_PHYSICAL | AUTH_REMOTE_ACCESS
		if(BIND_AI)
			return AUTH_AI
	return AUTH_PHYSICAL | AUTH_AI

/// Is this a physical binding (hand, tool, item, stack, in_hand, at_target, inside)?
/datum/entry/part/bind/proc/physical()
	return bind_kind in list(BIND_HAND, BIND_TOOL, BIND_ITEM, BIND_STACK, BIND_IN_HAND, BIND_AT_TARGET, BIND_INSIDE, BIND_CLICKS, BIND_TK)

/// The origins the op accepts through this binding: the select origin() when the op names one.
/proc/op_accepts_origin(datum/op_plan/P, datum/entry/part/bind/B, origin)
	if(origin == ORIGIN_SYSTEM)
		return TRUE
	var/chosen = LAZYACCESS(P.selects, "origin")
	return !!(origin & (isnull(chosen) ? B.origins() : chosen))

/// Does the binding accept the authority in use?
/proc/op_accepts_authority(datum/op_plan/P, datum/entry/part/bind/B, authority)
	if(authority & AUTH_ADMIN)
		return TRUE
	var/chosen = LAZYACCESS(P.selects, "authority")
	return !!(authority & (isnull(chosen) ? B.authority_mask() : chosen))

/// Gameplay adapters may withdraw manipulation providers when a body loses its hands.
/datum/proc/can_provide_hands(datum/act/A)
	return TRUE
