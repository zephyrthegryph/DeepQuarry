// The one coupling point between rules and SSreactor (doc/rewrite/reactor.md §1).
//
// Rules call only the dq_rx_* procs below and receive wakes as
// rule_wake(reason, source). Nothing else in code/datums/rules/ uses a
// REACT_* macro, a vg_* bind or a reactor constant.
//
//   dq_rx_when_threshold(D, node, ch, above, level, edges)  REACT_WHEN(D, COND_ABOVE/BELOW)
//   dq_rx_when_band(D, node, ch, levels)                     REACT_WHEN(D, COND_BAND)
//   dq_rx_on_change(D, node, ch)                             REACT_ON(D, handle, CH_BIT(ch))
//   dq_rx_on_key(D, kind, id, mask) / dq_rx_publish(...)     REACT_ON_KEY / REACT_PUBLISH
//   dq_rx_at(D, time)                                        REACT_AT
//   dq_rx_rate_linear/read/set_rate/remove, dq_rx_on_rate    RATE_LINEAR ... / REACT_RATE
//   dq_rx_cancel(D, token), dq_rx_clear(D), dq_rx_id(D)      REACT_CANCEL / REACT_CLEAR / REACT_ID
//
// Heat nodes (H3). An object's heat node is its heat body in the heat domain
// (M4, code/modules/heat/heat.dm). A body exists only while the object
// diverges from its surroundings: add_heat() creates it, and Rust releases it
// at equilibrium (dropping its watches). A node's watches are kept here and
// registered as Threshold/Band watches on the body whenever the object has
// one (dq_rx_heat_body_created() relinks them when a body is made). At rest
// the object reads its surroundings' temperature and costs nothing.

/// A rule_binding receives SSreactor wakes here.
/datum/rule_binding/on_react(reason, source, source_kind)
	rule_wake(reason, source)

/// Called with the merged reasons of a wake. Read the current state; never count wakes.
/datum/proc/rule_wake(reason, source)
	return

/proc/dq_rx_id(datum/D)
	return REACT_ID(D)

/proc/dq_rx_now()
	return world.time

/proc/dq_rx_on_key(datum/D, kind, id, mask)
	return REACT_ON_KEY(D, kind, id, mask)

/proc/dq_rx_publish(kind, id, mask)
	REACT_PUBLISH(kind, id, mask)

/proc/dq_rx_at(datum/D, time)
	return REACT_AT(D, time)

/// Node watches have text tokens ("n12"); the rest are SSreactor's numbers.
/proc/dq_rx_cancel(datum/D, token)
	if(istext(token))
		dq_rx_nodes().unwatch(token)
		return
	REACT_CANCEL(D, token)

/proc/dq_rx_clear(datum/D)
	REACT_CLEAR(D)
	D.heat_unsubscribe()

/proc/dq_rx_rate_linear(v0, per_second, lo, hi)
	return RATE_LINEAR(v0, per_second, lo, hi)

/proc/dq_rx_rate_read(model)
	return RATE_READ(model)

/proc/dq_rx_rate_set_rate(model, per_second)
	RATE_SET_RATE(model, per_second)

/proc/dq_rx_rate_remove(model)
	RATE_REMOVE(model)

/// Wake D when `model` reaches `level` (above) or falls to it; at once if it already has.
/proc/dq_rx_on_rate(datum/D, model, above, level)
	return REACT_RATE(D, model, above ? REACT_CMP_ABOVE : REACT_CMP_BELOW, level)

// ---- Heat nodes ----

#define DQ_RX_WATCH_OWNER 1
#define DQ_RX_WATCH_NODE 2
#define DQ_RX_WATCH_KIND 3
#define DQ_RX_WATCH_PARAMS 4
#define DQ_RX_WATCH_LIVE 5
#define DQ_RX_WATCH_BODY 6


/// A heat watch fired on a node's body.
/datum/rule_binding/on_heat_wake(watch, reason, source)
	rule_wake(DQ_RX_REASON_CONDITION, source)

/proc/dq_rx_when_threshold(datum/D, node, ch, above, level, edges)
	return dq_rx_nodes().watch(D, node, ch, RULE_TRIGGER_THRESHOLD, list(above, level, edges))

/proc/dq_rx_when_band(datum/D, node, ch, list/levels)
	return dq_rx_nodes().watch(D, node, ch, RULE_TRIGGER_BAND, levels.Copy())

/proc/dq_rx_on_change(datum/D, node, ch)
	return dq_rx_nodes().watch(D, node, ch, RULE_TRIGGER_DIFFERENCE, null)

/// A heat node for atom `A`.
/proc/dq_rx_node_new(atom/A)
	return dq_rx_nodes().create(A)

/// Sets the node's temperature (tests and DM authority): the atom gets a body
/// at `value`, isolated from its surroundings so the value holds.
/proc/dq_rx_node_write(node, ch, value)
	dq_rx_nodes().set_value(node, value)
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	// Deterministic flush (doc/testing.md flaky notes): every current caller
	// of dq_rx_node_write() is test code (property_provider/domain/test_write()
	// and direct calls like dq_rule_hold_and_band), and a write alone doesn't
	// run a heat frame or step SSreactor -- an assertion right after it was
	// racing the Master controller's own schedule, which is exactly the
	// "did not subscribe" / hold-and-band class of flake. Flushing here once
	// means callers don't each need their own dq_rx_flush(). Guarded because
	// dq_rx_flush() (code/modules/unit_tests/) only exists in a test/lint
	// build, and because it runs a blocking unit-tests-only Rust debug proc
	// that must never fire from real "DM authority" use in production.
	dq_rx_flush()
#endif

/proc/dq_rx_node_read(node, ch)
	return dq_rx_nodes().value_of(node)

/proc/dq_rx_node_free(node)
	dq_rx_nodes().destroy_node(node)

/// Whether the node's watches are live heat-domain watches right now (tests).
/proc/dq_rx_node_live(node)
	var/datum/dq_rx_nodes/nodes = dq_rx_nodes()
	for(var/token in nodes.node_watches["[node]"])
		var/list/entry = nodes.watches[token]
		if(entry && !isnull(entry[DQ_RX_WATCH_LIVE]))
			return TRUE
	return FALSE

/// `A` just got a heat body: move its node's watches onto it.
/proc/dq_rx_heat_body_created(atom/A)
	var/datum/dq_rx_nodes/nodes = dq_rx_nodes()
	var/node = nodes.by_atom[REF(A)]
	if(isnull(node))
		return
	for(var/token in nodes.node_watches["[node]"])
		nodes.relink(token)

/proc/dq_rx_nodes()
	var/static/datum/dq_rx_nodes/nodes
	if(!nodes)
		nodes = new
	return nodes

/datum/dq_rx_nodes
	var/next_node = 1
	var/next_watch = 1
	/// "[node]" -> weakref to its atom.
	var/list/owners = list()
	/// REF(atom) -> node, and back.
	var/list/by_atom = list()
	var/list/keys = list()
	/// "[node]" -> its watch tokens.
	var/list/node_watches = list()
	/// token -> list(D, node, kind, params, live heat watch, body it is on).
	var/list/watches = list()

/datum/dq_rx_nodes/proc/create(atom/A)
	var/key = REF(A)
	if(!isnull(by_atom[key]))
		return by_atom[key]
	var/node = next_node++
	owners["[node]"] = WEAKREF(A)
	by_atom[key] = node
	keys["[node]"] = key
	return node

/datum/dq_rx_nodes/proc/atom_of(node)
	var/datum/weakref/ref = owners["[node]"]
	var/atom/A = ref?.resolve()
	return (A && !QDELETED(A)) ? A : null

/datum/dq_rx_nodes/proc/value_of(node)
	var/atom/A = atom_of(node)
	return A ? A.get_temperature() : null

/datum/dq_rx_nodes/proc/set_value(node, value)
	var/atom/A = atom_of(node)
	if(!A || !A.create_heat_body())
		return
	vg_heat_body_couple(A.heat_body, 0, HEAT_TARGET_NONE, 0, 0)
	vg_heat_body_set_temperature(A.heat_body, value)
	dq_rx_heat_body_created(A)

/datum/dq_rx_nodes/proc/destroy_node(node)
	var/list/tokens = node_watches["[node]"]
	if(tokens)
		for(var/token in tokens.Copy())
			unwatch(token)
	by_atom -= keys["[node]"]
	keys -= "[node]"
	owners -= "[node]"
	node_watches -= "[node]"

/datum/dq_rx_nodes/proc/watch(datum/D, node, ch, kind, params)
	var/token = "n[next_watch++]"
	watches[token] = list(D, node, kind, params, null, null)
	LAZYADD(node_watches["[node]"], token)
	relink(token)
	return token

/// (Re)register a node watch on the atom's current heat body, if it has one
/// and the watch is not already on it.
/datum/dq_rx_nodes/proc/relink(token)
	var/list/entry = watches[token]
	var/datum/D = entry[DQ_RX_WATCH_OWNER]
	var/atom/A = atom_of(entry[DQ_RX_WATCH_NODE])
	var/body = A?.heat_body
	if(!isnull(body) && isnull(vg_heat_body_temperature(body)))
		A.heat_body = null
		body = null
	if(!isnull(entry[DQ_RX_WATCH_LIVE]))
		if(entry[DQ_RX_WATCH_BODY] == body)
			return
		var/list/old_live = entry[DQ_RX_WATCH_LIVE]
		vg_heat_unwatch(TRUE, old_live[1], old_live[2])
		entry[DQ_RX_WATCH_LIVE] = null
		entry[DQ_RX_WATCH_BODY] = null
	if(isnull(body) || QDELETED(D))
		return // at rest: the object reads its surroundings
	var/list/params = entry[DQ_RX_WATCH_PARAMS]
	var/list/live
	switch(entry[DQ_RX_WATCH_KIND])
		if(RULE_TRIGGER_THRESHOLD)
			live = vg_heat_watch(TRUE, body, D.heat_subscriber_index(), HEAT_LANE_NORMAL, params[1] ? HEAT_WATCH_ABOVE : HEAT_WATCH_BELOW, params[2], params[3] ? TRUE : FALSE)
		if(RULE_TRIGGER_BAND)
			live = vg_heat_watch(TRUE, body, D.heat_subscriber_index(), HEAT_LANE_NORMAL, HEAT_WATCH_BAND, params, FALSE)
		else
			// A change watch between two heat nodes: woken when either gets a body.
			D.rule_wake(DQ_RX_REASON_CONDITION, entry[DQ_RX_WATCH_NODE])
			return
	entry[DQ_RX_WATCH_LIVE] = live
	entry[DQ_RX_WATCH_BODY] = body

/datum/dq_rx_nodes/proc/unwatch(token)
	var/list/entry = watches[token]
	if(!entry)
		return
	if(!isnull(entry[DQ_RX_WATCH_LIVE]))
		var/list/live = entry[DQ_RX_WATCH_LIVE]
		vg_heat_unwatch(TRUE, live[1], live[2])
	watches -= token
	LAZYREMOVE(node_watches["[entry[DQ_RX_WATCH_NODE]]"], token)

#undef DQ_RX_WATCH_OWNER
#undef DQ_RX_WATCH_NODE
#undef DQ_RX_WATCH_KIND
#undef DQ_RX_WATCH_PARAMS
#undef DQ_RX_WATCH_LIVE
#undef DQ_RX_WATCH_BODY
