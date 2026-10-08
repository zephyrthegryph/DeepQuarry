// Turf edges: how a turf hears its neighbour turfs (doc/rewrite/framework_gaps.md KD90, doc/rewrite/final_api.html section 13).
//
// A floor's look blends with the floors around it (edges, outer and inner corners, the edge of a stronger neighbour spilling onto it, the open space
// above); a rock wall's look needs to know which of its neighbours are open. None of that is the turf's own state, so its draw() must not read the
// neighbours. The adjacency index does: every simulated turf is a member of ADJ_KIND_TURF_EDGE, and when a member (or a neighbour of it) is placed,
// moved or removed, or when a turf reports that something an edge reads changed (edge_inputs_changed(): the flooring, the state it draws, its
// density), the index recomputes the members around it and each one's edges_changed() writes its own TRACKED masks through their setters:
//
//   edge_mask   (floor)     the cardinal borders (NORTH|SOUTH|EAST|WEST bits) and the inner corners (one bit per GLOB.cornerdirs entry, shifted
//                           left by four) the flooring draws, from flooring.test_link() against each of the eight neighbours
//   edge_spill  (floor)     the edge overlays a stronger neighbour spills onto this turf (outdoor ground, water, lava...)
//   no_ceiling  (floor)     the turf above is open space and this one is not outdoors
//   open_mask   (solid rock) the cardinal neighbours that are not dense
//
// The draw reads those and the turf's own tracked state, and nothing else. A neighbour's state reaches a draw only through its mask.
//
// A turf that is replaced (ChangeTurf) or a structure that forbids edges coming or going (a cliff) is not a state the index sees by itself:
// turf_edges_refresh() asks the members around it to recompute.

// (The membership is declared with the rest of /turf/simulated's CAPABILITIES block, code/modules/lighting/sunlight_handler.dm.)

/// The key of the edge-relevant state this turf last told its neighbours (edge_key()); null until the index first computed its masks.
/turf/simulated/var/tmp/edge_key_sent

/// adjacency() changed: the index placed, moved or removed this turf or a neighbour, or a neighbour told it something changed. A turf whose look
/// reads edges overrides this to write its masks; the base records the state its neighbours first read.
/turf/simulated/proc/edges_changed(mask)
	if(isnull(edge_key_sent))
		edge_key_sent = edge_key()

/// Everything a neighbour's edges read of this turf, as text: equal keys mean the neighbours need not recompute.
/turf/simulated/proc/edge_key()
	return "[density]"

/// The icon_state this turf draws, as a function of its tracked state: what a neighbour compares against its own and what spills onto it.
/turf/simulated/proc/edge_look_state()
	return icon_state

/// The state an edge spilling from this turf onto a weaker neighbour is named after (the file holds "<state>-edge").
/turf/simulated/proc/get_edge_icon_state()
	return edge_look_state()

/// Tests if we shouldn't apply a turf edge. Returns the blocker if one exists.
/turf/simulated/proc/forbid_turf_edge()
	for(var/obj/structure/S in contents)
		if(S.block_turf_edges)
			return S
	return null

/// Something an edge reads changed on this turf (its flooring, the state it draws, its density): when its key moved, it and its neighbours
/// recompute their masks. A turf in a map load waits for the batch like any other member.
/turf/simulated/proc/edge_inputs_changed(datum/act/A)
	var/key = edge_key()
	if(key == edge_key_sent)
		return
	edge_key_sent = key
	log_edge_trace("[type] at [x],[y],[z] changed what its edges read: [key]")
	if(materialization_host().batch_defer(BATCH_WORK_ADJACENCY, src))
		return
	adjacency_refresh(src, TRUE)

/// This turf's masks again (the turf above or a blocker of edges changed).
/turf/simulated/proc/edges_refresh()
	if(materialization_host().batch_defer(BATCH_WORK_ADJACENCY, src))
		return
	adjacency_refresh(src)

/// The simulated turfs in the 3x3 around `center` (and `center` itself) read their edges again: `center` was replaced, or a blocker of edges came or
/// went on it. The index sees a member being placed or removed; this covers the turf that is not one (space, an unsimulated tile) and the moment
/// the replacement exists.
/proc/turf_edges_refresh(turf/center)
	if(!center)
		return
	for(var/turf/simulated/S in RANGE_TURFS(1, center)) // `in`, not `as anything`: the filter keeps space and unsimulated tiles out
		S.edges_refresh()

/// Tracing for the edge masks (a mask that is wrong is hard to see): written to the world log when GLOB.turf_edge_tracing is on.
GLOBAL_VAR_INIT(turf_edge_tracing, FALSE)

/proc/log_edge_trace(message)
	if(GLOB.turf_edge_tracing)
		log_world("turf edges: [message]")
