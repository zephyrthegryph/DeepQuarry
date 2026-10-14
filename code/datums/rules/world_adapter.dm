// The one coupling point between rules and the Rust world (the native watches of
// code/engine/time/world_watches.dm, object_model_core.md §4.8).
//
// Rules call only the dq_rx_* procs below and receive wakes as
// rule_wake(reason, source). Nothing else in code/datums/rules/ uses a
// world_watch_* proc, a vg_* bind or a world constant. Every subscription is a
// /datum/native_watch (its own token): dq_rx_cancel() qdels it, and
// dq_rx_clear() qdels every watch the binding still holds.
//
//   dq_rx_when_threshold(D, node, ch, above, level, edges)  native heat watch
//   dq_rx_when_band(D, node, ch, levels)                     native heat watch
//   dq_rx_on_change(D, node, ch)                             native heat watch (body appears)
//   dq_rx_on_key(D, kind) / dq_rx_publish(thing, kind)       DM-owned keys: the binding hears dq_rules_publish()
//   hold_for is a keyed kernel timer of the binding (key "hold:N"), not a world watch.
//   dq_rx_cancel(D, token), dq_rx_clear(D)                   qdel / every watch
//
// DM-owned keys and timers live in DM only (the kernel's after()): there is no world-side timer, no key published into Rust and no
// Rust reactor key table. A key trigger is a text token ("key:<kind>") in the binding's key table; a publication re-evaluates
// the binding once per tick (merged), as the Rust key wake did.
//
// Heat nodes (H3). An object's heat node is its heat body in the heat domain
// (M4, code/modules/heat/heat.dm). A body exists only while the object
// diverges from its surroundings: add_heat() creates it, and Rust releases it
// at equilibrium (dropping its watches). A node's watches are native heat
// watches that follow the object's body (they relink when one is made). At
// rest the object reads its surroundings' temperature and costs nothing.

/// Called with the merged reasons of a wake. Read the current state; never count wakes.
/datum/proc/rule_wake(reason, source)
	return

/// A world watch made for a rule binding fired.
/datum/rule_binding/proc/on_world_wake(datum/native_watch/world/watch, reason, source, source_kind)
	rule_wake(reason, source)

/datum/rule_binding/proc/keep_watch(datum/native_watch/W)
	if(W)
		rel_add(src, nameof(world_watches), W)
	return W

/proc/dq_rx_now()
	return world.time

/// Subscribes `D` to DM-owned key `kind`. The token is text; dq_rx_cancel() gives it back.
/proc/dq_rx_on_key(datum/rule_binding/D, kind)
	LAZYINITLIST(D.key_subs)
	D.key_subs["[kind]"]++
	return "key:[kind]"

/// DM-owned state of `binding` under key `kind` changed: the binding re-evaluates once per tick.
/proc/dq_rx_publish(datum/rule_binding/binding, kind)
	binding.key_published(kind)

/// Every world subscription is a watch (cancelling it is deleting it); a key token is text.
/proc/dq_rx_cancel(datum/rule_binding/D, held)
	if(istext(held))
		if(istype(D) && D.key_subs)
			var/kind = copytext(held, 5)
			if(D.key_subs[kind] > 1)
				D.key_subs[kind]--
			else
				D.key_subs -= kind
			UNSETEMPTY(D.key_subs)
		return
	var/datum/native_watch/token = held
	if(istype(D))
		rel_remove(D, nameof(D.world_watches), token)
	if(istype(token) && !QDELETED(token))
		spent(token)

/proc/dq_rx_clear(datum/rule_binding/D)
	for(var/datum/native_watch/W as anything in D.world_watches?.Copy())
		dq_rx_cancel(D, W)
	rel_clear(D, nameof(D.world_watches))
	D.key_subs = null

// ---- Heat nodes ----

/// A rule's heat node: an atom's temperature, watched through native heat
/// watches that follow its body (code/modules/heat/heat.dm).
/datum/dq_rx_node
	/// The atom whose temperature this is: a one-sided back view (the atom owns us in rx_node).
	var/atom/node_atom
	/// The node's watches (/datum/native_watch/heat).
	var/list/watches

CAPABILITIES(/datum/dq_rx_node)
	owns_many(nameof(watches))

/datum/dq_rx_node/New(atom/A)
	..()
	rel_set(src, nameof(node_atom), A)

/datum/dq_rx_node/proc/atom_of()
	return QDELETED(node_atom) ? null : node_atom

/// The atom's heat node, if a rule made one.
/atom/var/tmp/datum/dq_rx_node/rx_node


/// A node watch fired: wake the rule binding.
/datum/proc/on_rx_node_heat(datum/native_watch/heat/watch, reason, source)
	rule_wake(DQ_RX_REASON_CONDITION, source)

/// A watch that fires whenever its target gets a new heat body (a change
/// watch between two heat nodes: at rest both follow their surroundings).
/datum/native_watch/heat/body_appears

/datum/native_watch/heat/body_appears/register()
	if(QDELETED(target))
		return TRUE
	HEAT_BODY_RESOLVE(target)
	if(!isnull(target.heat_body) && isnull(vg_heat_body_temperature(target.heat_body)))
		target.set_heat_body(null)
	if(!isnull(target.heat_body) && target.heat_body != body)
		body = target.heat_body
		fire(list(DQ_RX_REASON_CONDITION, target))
	return TRUE

/datum/native_watch/heat/body_appears/relink()
	register()

/proc/dq_rx_node_watch(datum/D, datum/dq_rx_node/node, kind, level, edges)
	var/atom/A = node?.atom_of()
	if(!A)
		return null
	var/datum/native_watch/heat/W
	if(kind == RULE_TRIGGER_DIFFERENCE)
		W = new /datum/native_watch/heat/body_appears(D, TYPE_PROC_REF(/datum, on_rx_node_heat))
		W = W.start(A, null, null, FALSE, HEAT_LANE_NORMAL, FALSE)
	else
		W = new(D, TYPE_PROC_REF(/datum, on_rx_node_heat))
		W = W.start(A, kind, level, edges, HEAT_LANE_NORMAL, FALSE)
	if(W)
		for(var/datum/native_watch/old as anything in node.watches?.Copy())
			if(QDELETED(old))
				own_take_member(node, nameof(node.watches), old)
		rel_add(node, nameof(node.watches), W)
	return W

/proc/dq_rx_when_threshold(datum/D, node, ch, above, level, edges)
	return dq_rx_node_watch(D, node, above ? HEAT_WATCH_ABOVE : HEAT_WATCH_BELOW, level, edges ? TRUE : FALSE)

/proc/dq_rx_when_band(datum/D, node, ch, list/levels)
	return dq_rx_node_watch(D, node, HEAT_WATCH_BAND, levels.Copy(), FALSE)

/proc/dq_rx_on_change(datum/D, node, ch)
	return dq_rx_node_watch(D, node, RULE_TRIGGER_DIFFERENCE, null, FALSE)

/// A heat node for atom `A`.
/proc/dq_rx_node_new(atom/A)
	if(!A.rx_node)
		rel_set(A, nameof(/atom::rx_node), new /datum/dq_rx_node(A))
	return A.rx_node

/// Sets the node's temperature (tests and DM authority): the atom gets a body
/// at `value`, isolated from its surroundings so the value holds.
/proc/dq_rx_node_write(datum/dq_rx_node/node, ch, value)
	var/atom/A = node?.atom_of()
	if(A && A.create_heat_body())
		vg_heat_body_couple(A.heat_body, 0, HEAT_TARGET_NONE, 0, 0)
		vg_heat_body_set_temperature(A.heat_body, value)
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	// Deterministic flush (doc/testing.md flaky notes): every caller of
	// dq_rx_node_write() is test code, and a write alone doesn't run a heat
	// frame or step the Rust world. Guarded because dq_rx_flush() only exists in
	// a test/lint build and must never run from production DM authority.
	dq_rx_flush()
#endif

/proc/dq_rx_node_read(datum/dq_rx_node/node, ch)
	var/atom/A = node?.atom_of()
	return A ? A.get_temperature() : null

/proc/dq_rx_node_free(datum/dq_rx_node/node)
	spent(node)

/// Whether the node's watches are live heat-domain watches right now (tests).
/proc/dq_rx_node_live(datum/dq_rx_node/node)
	for(var/datum/native_watch/heat/W as anything in node?.watches)
		if(W.is_live())
			return TRUE
	return FALSE
