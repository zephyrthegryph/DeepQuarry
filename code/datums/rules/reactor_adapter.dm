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
// Heat nodes. Objects have no node in a Rust heat domain yet, and the only
// watchable domain is S1's probe (REACT_PROBE_CELLS cells, DM-written). So an
// object's heat node is DM-mirrored, and borrows a probe cell only while it is
// away from ambient (dq_rx_node_write promotes it, dq_rx_node_idle returns the
// cell). While it holds a cell its watches are real REACT_WHEN watches in
// Rust. At rest they exist only here, so a resting object costs SSreactor
// nothing (and round-trips materialize/dematerialize); if every cell is taken,
// a write wakes the watchers directly and the rule re-checks its predicate. When items get heat nodes in the heat domain,
// dq_rx_node_* become thin wrappers over that domain's handles and the pool
// and the fallback go away.

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

/proc/dq_rx_when_threshold(datum/D, node, ch, above, level, edges)
	return dq_rx_nodes().watch(D, node, ch, RULE_TRIGGER_THRESHOLD, list(above, level, edges))

/proc/dq_rx_when_band(datum/D, node, ch, list/levels)
	return dq_rx_nodes().watch(D, node, ch, RULE_TRIGGER_BAND, levels.Copy())

/proc/dq_rx_on_change(datum/D, node, ch)
	return dq_rx_nodes().watch(D, node, ch, RULE_TRIGGER_DIFFERENCE, null)

/proc/dq_rx_node_new(list/start)
	return dq_rx_nodes().create(start)

/proc/dq_rx_node_write(node, ch, value)
	dq_rx_nodes().set_value(node, ch, value)

/proc/dq_rx_node_read(node, ch)
	return dq_rx_nodes().value_of(node, ch)

/// The node is back at rest: give its probe cell back.
/proc/dq_rx_node_idle(node)
	dq_rx_nodes().demote(node)

/proc/dq_rx_node_free(node)
	dq_rx_nodes().destroy_node(node)

/// Whether the node's watches are live Rust watches right now (tests).
/proc/dq_rx_node_in_rust(node)
	var/datum/dq_rx_nodes/nodes = dq_rx_nodes()
	return !isnull(nodes.cells["[node]"])

/proc/dq_rx_nodes()
	var/static/datum/dq_rx_nodes/nodes
	if(!nodes)
		nodes = new
	return nodes

/// Probe cells rules may borrow. S1's own tests use cells below 64.
#define DQ_RX_FIRST_CELL 128
/// Pressure written with a borrowed cell's temperature.
#define DQ_RX_NODE_KPA 101.325

/datum/dq_rx_nodes
	var/next_node = 1
	var/next_watch = 1
	/// "[node]" -> list("[ch]" -> value). The DM mirror, always current.
	var/list/values = list()
	/// "[node]" -> borrowed probe cell.
	var/list/cells = list()
	var/list/free_cells
	/// "[node]" -> its watch tokens.
	var/list/node_watches = list()
	/// token -> list(D, node, ch, kind, params, live token).
	var/list/watches = list()

/datum/dq_rx_nodes/New()
	..()
	free_cells = list()
	for(var/cell in REACT_PROBE_CELLS - 1 to DQ_RX_FIRST_CELL step -1)
		free_cells += cell

/datum/dq_rx_nodes/proc/create(list/start)
	var/node = next_node++
	values["[node]"] = start ? start.Copy() : list()
	return node

/datum/dq_rx_nodes/proc/value_of(node, ch)
	var/list/node_values = values["[node]"]
	return node_values ? node_values["[ch]"] : null

/datum/dq_rx_nodes/proc/set_value(node, ch, value)
	var/list/node_values = values["[node]"]
	if(!node_values || node_values["[ch]"] == value)
		return
	node_values["[ch]"] = value
	var/cell = cells["[node]"]
	if(isnull(cell) && length(node_watches["[node]"]) && length(free_cells))
		promote(node)
		return
	if(isnull(cell))
		wake_all(node)
	else
		set_cell(cell, node_values)

/datum/dq_rx_nodes/proc/set_cell(cell, list/node_values)
	var/kelvin = node_values["[DQ_RX_CH_TEMPERATURE]"]
	vg_react_probe_set(cell, DQ_RX_NODE_KPA, isnull(kelvin) ? T20C : kelvin)

/// Borrow a probe cell and move the node's watches onto it. A watch whose
/// condition already holds fires on its first evaluation.
/datum/dq_rx_nodes/proc/promote(node)
	var/cell = free_cells[length(free_cells)]
	free_cells.len--
	cells["[node]"] = cell
	set_cell(cell, values["[node]"])
	for(var/token in node_watches["[node]"])
		relink(token)

/// Give the cell back; the node's watches fall back to its key.
/datum/dq_rx_nodes/proc/demote(node)
	var/cell = cells["[node]"]
	if(isnull(cell))
		return
	cells -= "[node]"
	for(var/token in node_watches["[node]"])
		relink(token)
	free_cells += cell

/datum/dq_rx_nodes/proc/destroy_node(node)
	var/list/tokens = node_watches["[node]"]
	if(tokens)
		for(var/token in tokens.Copy())
			unwatch(token)
	demote(node)
	values -= "[node]"
	node_watches -= "[node]"

/datum/dq_rx_nodes/proc/watch(datum/D, node, ch, kind, params)
	var/token = "n[next_watch++]"
	watches[token] = list(D, node, ch, kind, params, null)
	LAZYADD(node_watches["[node]"], token)
	relink(token)
	return token

/// (Re)register a node watch on the node's current backing: a Rust watch on
/// its probe cell, or its DM key.
/datum/dq_rx_nodes/proc/relink(token)
	var/list/entry = watches[token]
	var/datum/D = entry[1]
	if(!isnull(entry[6]))
		REACT_CANCEL(D, entry[6])
		entry[6] = null
	if(QDELETED(D))
		return
	var/node = entry[2]
	var/cell = cells["[node]"]
	if(isnull(cell))
		return // at rest: DM-only, woken directly by write()
	var/handle = REACT_HANDLE(REACT_DOMAIN_PROBE, cell)
	var/ch = entry[3] == DQ_RX_CH_TEMPERATURE ? CH_PROBE_TEMPERATURE : entry[3]
	var/list/params = entry[5]
	switch(entry[4])
		if(RULE_TRIGGER_THRESHOLD)
			entry[6] = REACT_WHEN(D, list(REACT_COND_THRESHOLD, handle, ch, params[1] ? REACT_CMP_ABOVE : REACT_CMP_BELOW, params[2], -1, params[3] ? TRUE : FALSE))
		if(RULE_TRIGGER_BAND)
			entry[6] = REACT_WHEN(D, COND_BAND(handle, ch, params))
		else
			entry[6] = REACT_ON(D, handle, CH_BIT(ch))

/// No cell (every cell taken): wake the node's watchers directly.
/datum/dq_rx_nodes/proc/wake_all(node)
	var/list/tokens = node_watches["[node]"]
	if(!tokens)
		return
	for(var/token in tokens.Copy())
		var/list/entry = watches[token]
		var/datum/D = entry ? entry[1] : null
		if(D && !QDELETED(D))
			D.rule_wake(DQ_RX_REASON_CONDITION, node)

/datum/dq_rx_nodes/proc/unwatch(token)
	var/list/entry = watches[token]
	if(!entry)
		return
	if(!isnull(entry[6]))
		REACT_CANCEL(entry[1], entry[6])
	watches -= token
	LAZYREMOVE(node_watches["[entry[2]]"], token)

#undef DQ_RX_FIRST_CELL
#undef DQ_RX_NODE_KPA
