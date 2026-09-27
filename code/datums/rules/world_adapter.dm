// The one coupling point between rules and the Rust world (om_world_* in
// code/datums/om/world_watch.dm, object_model_core.md §4.8).
//
// Rules call only the dq_rx_* procs below and receive wakes as
// rule_wake(reason, source). Nothing else in code/datums/rules/ uses an
// om_world_* proc, a vg_* bind or a world constant. Every subscription is a
// /datum/native_watch (its own token): dq_rx_cancel() qdels it, and
// dq_rx_clear() qdels every watch the binding still holds.
//
//   dq_rx_when_threshold(D, node, ch, above, level, edges)  native heat watch
//   dq_rx_when_band(D, node, ch, levels)                     native heat watch
//   dq_rx_on_change(D, node, ch)                             native heat watch (body appears)
//   dq_rx_on_key(D, kind, id, mask) / dq_rx_publish(...)     om_world_on_key / om_world_publish
//   dq_rx_at(D, time)                                        om_world_at
//   dq_rx_rate_linear/read/set_rate/remove, dq_rx_on_rate    om_rate_* / om_world_on_rate
//   dq_rx_cancel(D, token), dq_rx_clear(D), dq_rx_id()       qdel / every watch / om_world_key_id
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
		LAZYADD(world_watches, W)
	return W

/proc/dq_rx_id()
	return om_world_key_id()

/proc/dq_rx_now()
	return world.time

/proc/dq_rx_on_key(datum/rule_binding/D, kind, id, mask)
	return D.keep_watch(om_world_on_key(D, kind, id, mask, TYPE_PROC_REF(/datum/rule_binding, on_world_wake)))

/proc/dq_rx_publish(kind, id, mask)
	om_world_publish(kind, id, mask)

/proc/dq_rx_at(datum/rule_binding/D, time)
	return D.keep_watch(om_world_at(D, time, TYPE_PROC_REF(/datum/rule_binding, on_world_wake)))

/// Every subscription is a watch: cancelling it is deleting it.
/proc/dq_rx_cancel(datum/rule_binding/D, datum/native_watch/token)
	if(istype(D))
		LAZYREMOVE(D.world_watches, token)
	if(istype(token) && !QDELETED(token))
		qdel(token)

/proc/dq_rx_clear(datum/rule_binding/D)
	for(var/datum/native_watch/W as anything in D.world_watches?.Copy())
		dq_rx_cancel(D, W)
	D.world_watches = null

/proc/dq_rx_rate_linear(v0, per_second, lo, hi)
	return om_rate_linear(v0, per_second, lo, hi)

/proc/dq_rx_rate_read(model)
	return om_rate_read(model)

/proc/dq_rx_rate_set_rate(model, per_second)
	om_rate_set_rate(model, per_second)

/proc/dq_rx_rate_remove(model)
	om_rate_remove(model)

/// Wake D when `model` reaches `level` (above) or falls to it; at once if it already has.
/proc/dq_rx_on_rate(datum/rule_binding/D, model, above, level)
	return D.keep_watch(om_world_on_rate(D, model, above ? WORLD_CMP_ABOVE : WORLD_CMP_BELOW, level, TYPE_PROC_REF(/datum/rule_binding, on_world_wake)))

// ---- Heat nodes ----

/// A rule's heat node: an atom's temperature, watched through native heat
/// watches that follow its body (code/modules/heat/heat.dm).
/datum/dq_rx_node
	/// OM handle of the atom.
	var/atom_ref
	/// The node's watches (/datum/native_watch/heat).
	var/list/watches

/datum/dq_rx_node/New(atom/A)
	..()
	atom_ref = om_handle(A)

REF_OWNED_LIST(/datum/dq_rx_node, "watches")

/// Phase 1 (unbind): the node leaves its atom.
/datum/dq_rx_node/lifecycle_unbind()
	. = ..()
	var/atom/A = atom_of()
	if(A?.rx_node == src)
		A.rx_node = null

/datum/dq_rx_node/proc/atom_of()
	var/atom/A = om_resolve(atom_ref)
	return (A && !QDELETED(A)) ? A : null

/// The atom's heat node, if a rule made one.
/atom/var/tmp/datum/dq_rx_node/rx_node

/atom/declared_owned_vars()
	. = ..()
	. = (. || list()) + "rx_node"

/// A node watch fired: wake the rule binding.
/datum/proc/on_rx_node_heat(datum/native_watch/heat/watch, reason, source)
	rule_wake(DQ_RX_REASON_CONDITION, source)

/// A watch that fires whenever its target gets a new heat body (a change
/// watch between two heat nodes: at rest both follow their surroundings).
/datum/native_watch/heat/body_appears

/datum/native_watch/heat/body_appears/register()
	if(QDELETED(target))
		return TRUE
	if(!isnull(target.heat_body) && isnull(vg_heat_body_temperature(target.heat_body)))
		target.heat_body = null
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
				LAZYREMOVE(node.watches, old)
		LAZYADD(node.watches, W)
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
		A.rx_node = new /datum/dq_rx_node(A)
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
	qdel(node)

/// Whether the node's watches are live heat-domain watches right now (tests).
/proc/dq_rx_node_live(datum/dq_rx_node/node)
	for(var/datum/native_watch/heat/W as anything in node?.watches)
		if(W.is_live())
			return TRUE
	return FALSE
