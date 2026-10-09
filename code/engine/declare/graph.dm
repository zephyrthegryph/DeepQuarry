// State graphs (doc/rewrite/final_api.html, section 12 "Construction", foundation X4; section 19 "E1, declarations": "state graphs (the
// per-instance stage, history and ledger)").
//
// One graph form carries construction, deconstruction and deployment: nodes are STAGE_DEF stages, edges are the ops that move between
// them. An instance keeps three things, each with one job: its CURRENT stage (where it is now, what edges leave it), a HISTORY stack of
// the transitions actually taken (which predecessor to undo to; whether a stage is "at or past"), and a LEDGER of what each transition
// took in (what to refund, and built_material()). Undo pops the history, returns to the stage the instance actually came from, and
// refunds exactly that transition's ledger entry.
//
// E1 owns the graph, its validation and the per-instance state. The ops the edges become (construction.build:<stage>,
// construction.undo:<stage>, construction.dismantle) and the resource transactions behind the ledger are E2's: it reads the compiled
// edges from the graph and calls graph_advance() / graph_undo() as the edge's costs are reserved and committed.


/// A stage id and its text key, from the STAGE_DEF lines. The key is "<group>_<name>".
/datum/stage_def/proc/spec()
	return null

GLOBAL_LIST_EMPTY(stage_keys) // stage id -> "group_name"
GLOBAL_LIST_EMPTY(state_graphs) // graph id (or anonymous signature) -> /datum/state_graph
GLOBAL_VAR_INIT(stage_defs_built, FALSE)

/proc/stage_defs_build()
	GLOB.stage_defs_built = TRUE
	for(var/def_type in subtypesof(/datum/stage_def))
		var/datum/stage_def/D = new def_type
		var/list/row = D.spec()
		if(length(row))
			GLOB.stage_keys["[row[1]]"] = "[row[2]]_[row[3]]"

/// The text key of a build stage ("door_wired"), or null for an undeclared id.
/proc/stage_key(stage_id)
	if(!GLOB.stage_defs_built)
		stage_defs_build()
	return GLOB.stage_keys["[stage_id]"]

// ---- the declared forms ----

/// start(STAGE_X): the graph's starting stage.
/proc/start(stage_id)
	return entry_make("graph_start", null, list("stage" = stage_id))

/// at(SPACE_X): the space of the holder an op, or a whole graph, works inside (code/engine/library/spaces.dm). The path from the actor to that
/// space must be open: a blocked op is set aside for another candidate, and refused with the blocking door's reason when nothing else answers.
/proc/at(space_id)
	return entry_make("graph_at", null, list("space" = space_id))

/// dismantle(parts..., ruined(...)): what taking the whole thing apart does; the op compiler (code/engine/parts/graph_ops.dm) reads its parts.
/proc/dismantle(ENTRY_SLOTS)
	return entry_make("graph_dismantle", null, null, entry_flatten(ENTRY_SLOT_LIST))

/// ruined(condition, parts...): inside dismantle(). When the condition holds at the moment of dismantling (a condition of section 9: nameof(var),
/// a stat or capability key id, cond_not/cond_all/cond_any, or a PROC_REF / TYPE_PROC_REF of x(datum/act/A) answering TRUE or FALSE, evaluated
/// like any op condition with the dismantle op's context), the effects of these parts run INSTEAD of the dismantle's own effects
/// (becomes(frame) becomes becomes(scrap)). The ledger refund is not touched by it. Only effect parts belong here.
/proc/ruined(cond, ENTRY_SLOTS)
	return entry_make("graph_ruined", null, list("cond" = cond), entry_flatten(ENTRY_SLOT_LIST))

/// The default of stage()'s undo =: "derive the way back from the input part". An explicit undo = NO_UNDO means no way back.
#define UNDO_DERIVED "\[derived undo]"

/// stage(STAGE_X, parts..., from =, undo =, key =): an edge into a stage. A name (text) first argument is the legacy stage() of a
/// construction ladder (code/datums/capabilities/construction.dm), which keeps its own shape through legacy_stage().
/proc/stage(name, p1, p2, p3, p4, p5, p6, from = null, undo = UNDO_DERIVED, key = null, uses, needs, else_say, undo_needs, undo_else_say, when, undo_when, say, undo_say, desc, icon, anchored, on_enter, on_leave, list/also, refund, priority, quiet, sfx, done_sfx, build)
	if(!isnum(name))
		// The legacy ladder stage: name, build, undo positionally or by name, and its own options (null means "not given").
		var/list/legacy = list("name" = name, "build" = build || p1, "undo" = (undo != UNDO_DERIVED ? undo : p2))
		var/list/given = list("uses" = uses, "needs" = needs, "else_say" = else_say, "undo_needs" = undo_needs, "undo_else_say" = undo_else_say, "when" = when, "undo_when" = undo_when, "say" = say, "undo_say" = undo_say, "desc" = desc, "icon" = icon, "anchored" = anchored, "on_enter" = on_enter, "on_leave" = on_leave, "also" = also, "refund" = refund, "priority" = priority, "quiet" = quiet, "sfx" = sfx, "done_sfx" = done_sfx)
		for(var/option in given)
			if(!isnull(given[option]))
				legacy[option] = given[option]
		return construction_stage_provider().build_legacy(legacy)
	var/list/named = list("stage" = name, "key" = key, "from" = from)
	if(undo != UNDO_DERIVED)
		named["has_undo"] = TRUE
		named["undo"] = undo
	return entry_make("graph_stage", null, named, entry_flatten(list(p1, p2, p3, p4, p5, p6)))

/// The stages of one graph. Read-only after build.
/datum/state_graph
	var/id
	var/start
	/// The space the graph works inside (at(SPACE_X)), or null.
	var/space
	/// list of /datum/graph_edge, in declaration order.
	var/list/edges
	/// The dismantle entry, or null.
	var/datum/entry/dismantle_entry
	/// The entries the graph was compiled from (a deployment re-compiles them under its own op prefix).
	var/list/entries_raw

/// One edge: a way into a stage.
/datum/graph_edge
	var/into
	/// Stages the edge leaves from (a list), or ANY_STAGE.
	var/list/from
	/// The edge's key suffix ("kit" for door_finished.kit), or null.
	var/key
	/// The build op key ("construction.build:door_finished").
	var/op_key
	var/list/parts
	/// TRUE when the graph names an undo for this edge (undo = list(...) or undo = NO_UNDO).
	var/has_undo = FALSE
	var/list/undo_parts
	/// protrudes(...) among the stage's parts: list("space", "because"): while the instance is at this stage its space's door can't close.
	var/list/protrudes

/// Registration rows of STATE_GRAPH: list(graph_id, entries...).
/datum/graph_decl/proc/spec()
	return null

GLOBAL_VAR_INIT(state_graphs_built, FALSE)

/proc/state_graphs_build()
	GLOB.state_graphs_built = TRUE
	for(var/decl_type in subtypesof(/datum/graph_decl))
		var/datum/graph_decl/D = new decl_type
		var/list/row = D.spec()
		if(!length(row))
			continue
		var/id = row[1]
		var/list/entries = row.Copy(2)
		var/datum/state_graph/G = graph_compile(id, entries, "[decl_type]", "construction")
		if(G)
			GLOB.state_graphs["[id]"] = G

/// The graph a GRAPH_X id names (null when none is declared).
/proc/state_graph_of(id)
	RETURN_TYPE(/datum/state_graph)
	if(!GLOB.state_graphs_built)
		state_graphs_build()
	return GLOB.state_graphs["[id]"]

/// Compiles graph entries into a /datum/state_graph, reporting every error found. `prefix` is the op prefix ("construction" or "deployment").
/proc/graph_compile(id, list/entries, origin, prefix)
	RETURN_TYPE(/datum/state_graph)
	var/datum/state_graph/G = new
	G.id = id
	G.edges = list()
	G.entries_raw = entries
	var/previous = null
	var/list/declared = list()
	for(var/datum/entry/E as anything in entry_flatten(entries))
		if(!istype(E))
			declare_report("[origin]: [declare_rule(RULE_GRAPH)] graph [id]: [E] is not a graph entry")
			continue
		switch(E.kind)
			if("graph_start")
				G.start = E.args["stage"]
				previous = G.start
				declared["[G.start]"] = TRUE
				if(isnull(stage_key(G.start)))
					declare_report("[origin]: [declare_rule(RULE_GRAPH)] graph [id]: start names undeclared stage [G.start] -- declare it with STAGE_DEF")
			if("graph_at")
				G.space = E.args["space"]
			if("graph_dismantle")
				G.dismantle_entry = E // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
			if("graph_stage")
				var/datum/graph_edge/edge = new
				edge.into = E.args["stage"]
				if(isnull(stage_key(edge.into)))
					declare_report("[origin]: [declare_rule(RULE_GRAPH)] graph [id]: stage [edge.into] is not declared -- declare it with STAGE_DEF")
				var/from = E.args["from"]
				if(isnull(from))
					edge.from = list(previous)
				else if(islist(from))
					edge.from = from
				else
					edge.from = list(from)
				edge.key = E.args["key"]
				edge.parts = list()
				for(var/child in entry_flatten(E.children))
					var/datum/entry/marker = child
					if(istype(marker) && marker.kind == ENTRY_PROTRUSION)
						edge.protrudes = marker.args
					else
						edge.parts += child
				edge.has_undo = !!E.args["has_undo"]
				edge.undo_parts = E.args["undo"]
				edge.op_key = "[prefix].build:[stage_key(edge.into)]" + (edge.key ? ".[edge.key]" : "")
				for(var/f in edge.from)
					if(f != ANY_STAGE && !declared["[f]"])
						declare_report("[origin]: [declare_rule(RULE_GRAPH)] graph [id]: stage [stage_key(edge.into)] leaves from [f ? (stage_key(f) || f) : "null"], a stage the graph does not declare -- a from names a stage that is the start or has its own stage() line above")
				declared["[edge.into]"] = TRUE
				previous = edge.into
				G.edges += edge // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	if(isnull(G.start))
		declare_report("[origin]: [declare_rule(RULE_GRAPH)] graph [id] has no start(STAGE_X)")
	// A stage reached by different inputs needs one entry per way in, the second and later with key =.
	var/list/seen = list()
	for(var/datum/graph_edge/edge as anything in G.edges)
		var/sig = edge.op_key
		if(seen[sig])
			declare_report("[origin]: [declare_rule(RULE_GRAPH)] graph [id]: two edges into [stage_key(edge.into)] have the same key -- give the second one key =")
		seen[sig] = TRUE
	return G

/// Every edge of G into `to`.
/proc/graph_edges_into(datum/state_graph/G, target_stage)
	. = list()
	for(var/datum/graph_edge/edge as anything in G.edges)
		if(edge.into == target_stage)
			. += edge

/// The edge of G named by its stage and optional key, or null.
/proc/graph_edge_for(datum/state_graph/G, target_stage, key)
	for(var/datum/graph_edge/edge as anything in G.edges)
		if(edge.into == target_stage && edge.key == key)
			return edge
	return null

/// Every simple path of stages from the graph's start to `to`: each a list of stage ids, start first, `to` last.
/proc/graph_paths(datum/state_graph/G, target_stage)
	. = list()
	if(target_stage == G.start)
		return list(list(G.start))
	graph_walk(G, G.start, target_stage, list(G.start), .)

/proc/graph_walk(datum/state_graph/G, at, target_stage, list/trail, list/found)
	for(var/datum/graph_edge/edge as anything in G.edges)
		if(!(at in edge.from) && !(ANY_STAGE in edge.from))
			continue
		if(edge.into in trail)
			continue
		var/list/next = trail + list(edge.into)
		if(edge.into == target_stage)
			if(!(next in found))
				found += list(next)
			continue
		graph_walk(G, edge.into, target_stage, next, found)

// ---- the construction and deployment capabilities ----

CAPABILITY_TYPE(construction_graph, CAP_CONSTRUCTION, /datum/capability/construction, key = NONE, prefix = "construction", start, via)
CAPABILITY_TYPE(deployment_graph, CAP_DEPLOYMENT, /datum/capability/construction/deployment, key = NONE, prefix = "deployment", start, via)

/// A graph capability: the graph its type declares (a GRAPH_X id or inline entries), the stage it starts at and, for a type placed part-built
/// with several ways to that stage, the stages passed on the way (via).
/datum/capability/construction
	/// The compiled graph, or null when the declaration was refused.
	var/datum/state_graph/graph
	/// The stage an instance starts at (configure(CAP_CONSTRUCTION, start = STAGE_X)); null: the graph's start.
	var/start
	/// The stages passed in order between the graph's start and `start`, when several paths lead there.
	var/list/via

/datum/capability/construction/deployment

/// construction(GRAPH_X | start(STAGE_X), stage(...), ..., dismantle(...), at(BAY_X)): a build ladder, a graph with a ledger and an
/// operability contribution (E3 reads req_built_final from the graph's capability).
/proc/construction(ENTRY_SLOTS, p7, p8, p9, p10)
	return graph_capability(CAP_CONSTRUCTION, "construction", list(p1, p2, p3, p4, p5, p6, p7, p8, p9, p10))

/// deployment(...): the same graph under its own key CAP_DEPLOYMENT and prefix, with no operability contribution.
/proc/deployment(ENTRY_SLOTS, p7, p8, p9, p10)
	return graph_capability(CAP_DEPLOYMENT, "deployment", list(p1, p2, p3, p4, p5, p6, p7, p8, p9, p10))

/proc/graph_capability(cap_id, prefix, list/call_args)
	call_args = entry_flatten(call_args)
	var/datum/capability_info/info = capability_info(cap_id)
	var/datum/capability/construction/def = new info.cap_type
	def.cap_id = cap_id
	var/datum/state_graph/G = null
	if(length(call_args) == 1 && isnum(call_args[1]))
		G = state_graph_of(call_args[1])
		if(!G)
			declare_report("[prefix](): graph [call_args[1]] is not declared -- declare it with STATE_GRAPH")
		else if(prefix != "construction")
			G = graph_compile(G.id, G.entries_raw, "[prefix]([call_args[1]])", prefix)
	else
		G = graph_compile("inline", entry_flatten(call_args), "[prefix]() list", prefix)
	def.graph = G // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)
	var/datum/capability/built = cap_build(def, info, list())
	if(built == def)
		return def
	return built

/// An interned definition of a graph capability: its params are the graph (by identity), start and via. The default interning cannot see
/// the graph, so the signature adds it.
/datum/capability/construction/proc/graph_signature()
	return "[graph?.id]:[start]:[via ? jointext(via, ",") : ""]"

/datum/capability/construction/carry_over(datum/capability/construction/copy)
	copy.graph = graph // ALLOW(ownership): an engine record owned by its own end path (a flyweight, or a record the framework tears down)

/datum/capability/construction/validate_in(datum/type_table/T, origin)
	if(!graph || isnull(start) || start == graph.start)
		return
	var/list/paths = graph_paths(graph, start)
	if(!length(paths))
		table_error(T, origin, declare_rule(RULE_GRAPH), "configure(CAP [cap_id], start = [stage_key(start) || start]) names a stage no path of the graph reaches", "check the stage against the graph's stage() lines")
		return
	if(length(via))
		var/found = FALSE
		for(var/list/path in paths)
			// the stages between the start and the placed stage, in order
			var/list/between = path.Copy(2, length(path))
			if(between ~= via)
				found = TRUE
				break
		if(!found)
			table_error(T, origin, declare_rule(RULE_GRAPH), "via = [graph_stages_text(via)] is not a path from the start to [stage_key(start)]", "list the stages passed in order, not including the start and the placed stage")
		return
	if(length(paths) > 1)
		table_error(T, origin, declare_rule(RULE_GRAPH), "stage [stage_key(start)] has [length(paths)] paths from the start and the type names none", "write configure(CAP_CONSTRUCTION, start = STAGE_X, via = list(STAGE_A, STAGE_B)): the stages passed in order")

/proc/graph_stages_text(list/stages)
	var/list/keys = list()
	for(var/s in stages)
		keys += stage_key(s) || "[s]"
	return jointext(keys, ", ")

// ---- the per-instance state ----

/// One instance's state in a graph: where it is, where it has been, what each transition took in.
/datum/cap_data/graph_state
	/// The current stage (a STAGE_* id), or null until the first read (then the capability's start).
	var/current
	/// The transitions taken, oldest first: each list(edge key, from stage, to stage, ledger entry).
	var/list/history
	/// TRUE once the history has been seeded along the path to a part-built start.
	var/seeded = FALSE

/datum/capability/construction/cap_data_type()
	return /datum/cap_data/graph_state

/// The graph state of E for a graph capability, made on first use. `create` makes the activation if E has none yet.
/proc/graph_state(datum/E, cap_id = CAP_CONSTRUCTION, create = TRUE)
	var/datum/activation/A = cap_activation(E, cap_id, null, create)
	if(!A)
		return null
	var/datum/cap_data/graph_state/S = cap_data(A)
	if(S && isnull(S.current))
		var/datum/capability/construction/def = A.def
		S.current = isnull(def.start) ? def.graph?.start : def.start
	return S

/// The stage E is at now, or null when it has no such graph.
/proc/graph_current(datum/E, cap_id = CAP_CONSTRUCTION)
	var/datum/cap_data/graph_state/S = graph_state(E, cap_id, FALSE)
	if(S)
		return S.current
	var/datum/capability/construction/def = cap_of(E, cap_id)
	if(!def)
		return null
	return isnull(def.start) ? def.graph?.start : def.start

/// The history, seeded first when the instance was placed part-built: along the unique path from the graph's start, or the path `via` names.
/// Seeded entries carry empty ledger entries, so undoing past the seed refunds nothing.
/proc/graph_history(datum/E, cap_id = CAP_CONSTRUCTION, create = TRUE)
	var/datum/cap_data/graph_state/S = graph_state(E, cap_id, create)
	if(!S)
		// A read of an instance that has taken no step yet: the seeded path of its placed stage, built without making the activation (a read never grants).
		return create ? list() : graph_seed_rows(cap_of(E, cap_id))
	if(!S.seeded)
		S.seeded = TRUE
		if(!length(S.history))
			S.history = graph_seed_rows(cap_of(E, cap_id))
	return S.history || list()

/// The history rows a part-built start stands for (empty for a start at the graph's own start).
/proc/graph_seed_rows(datum/capability/construction/def)
	. = list()
	if(def?.graph && !isnull(def.start) && def.start != def.graph.start)
		var/list/path = graph_seed_path(def)
		if(length(path))
			var/datum/state_graph/G = def.graph
			for(var/i in 2 to length(path))
				var/datum/graph_edge/edge = graph_first_edge(G, path[i - 1], path[i])
				. += list(list(edge?.key, path[i - 1], path[i], null))

/// The stage path a part-built definition stands for: via, between the start and the placed stage, or the one path there is.
/proc/graph_seed_path(datum/capability/construction/def)
	var/datum/state_graph/G = def.graph
	var/list/paths = graph_paths(G, def.start)
	if(length(def.via))
		for(var/list/path in paths)
			if(path.Copy(2, length(path)) ~= def.via)
				return path
		return null
	return length(paths) == 1 ? paths[1] : null

/proc/graph_first_edge(datum/state_graph/G, from, target_stage)
	for(var/datum/graph_edge/edge as anything in G.edges)
		if(edge.into == target_stage && ((from in edge.from) || (ANY_STAGE in edge.from)))
			return edge
	return null

/**
 * Moves E along an edge into `stage`: pushes the transition on the history with its ledger entry and makes `stage` current. `key`
 * picks the edge when several lead into the stage ("kit"). `ledger` is what the transition took in (a list: "material", "resources",
 * "items", ...), written now so the edge's own effects read it; E2 finalizes it at commit with graph_ledger_finalize(). Returns TRUE, or
 * FALSE with the reason logged when no edge from the current stage leads there.
 */
/proc/graph_advance(datum/E, stage, key = null, list/ledger = null, cap_id = CAP_CONSTRUCTION)
	var/datum/cap_data/graph_state/S = graph_state(E, cap_id, TRUE)
	var/datum/capability/construction/def = cap_of(E, cap_id)
	if(!S || !def?.graph)
		declare_report("graph_advance([E?.type]): it has no graph [cap_id]")
		return FALSE
	graph_history(E, cap_id) // seed first, so this transition lands on top of the seeded path
	var/datum/graph_edge/edge = null
	for(var/datum/graph_edge/candidate as anything in graph_edges_into(def.graph, stage))
		if(candidate.key != key)
			continue
		if((S.current in candidate.from) || (ANY_STAGE in candidate.from))
			edge = candidate
			break
	if(!edge)
		declare_report("graph_advance([E.type]): no edge into [stage_key(stage) || stage][key ? " ([key])" : ""] leaves stage [stage_key(S.current) || S.current]")
		return FALSE
	var/was = S.current
	LAZYADD(S.history, list(list(edge.key, was, stage, ledger || list())))
	S.current = stage
	TEST_REC_DELTA(E, "stage:[cap_id]", was, stage)
	engine_key_changed(E, "graph:[cap_id]")
	return TRUE

/// Merges what the edge finally took into the ledger entry of the transition on top of the history (its costs were reserved when it began).
/proc/graph_ledger_finalize(datum/E, list/more, cap_id = CAP_CONSTRUCTION)
	var/datum/cap_data/graph_state/S = graph_state(E, cap_id, FALSE)
	if(!S || !length(S.history))
		return FALSE
	var/list/top = S.history[length(S.history)]
	var/list/ledger = top[4]
	if(!islist(ledger))
		ledger = list()
		top[4] = ledger
	for(var/name in more)
		ledger[name] = more[name]
	return TRUE

/**
 * Pops the history: E returns to the stage it actually came from, and the ledger entry of the transition being undone is handed back for
 * the refund. Returns list(stage returned to, ledger entry, edge key), or null at the start.
 */
/proc/graph_undo(datum/E, cap_id = CAP_CONSTRUCTION)
	var/datum/cap_data/graph_state/S = graph_state(E, cap_id, TRUE)
	if(!S)
		return null
	graph_history(E, cap_id)
	if(!length(S.history))
		return null
	var/list/top = S.history[length(S.history)]
	S.history.len--
	if(!length(S.history))
		S.history = null
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
	var/was = S.current
#endif
	S.current = top[2]
	TEST_REC_DELTA(E, "stage:[cap_id]", was, S.current)
	engine_key_changed(E, "graph:[cap_id]")
	return list(top[2], top[4], top[1])

/// Everything the instance took in, newest first, for dismantle(): the whole ledger.
/proc/graph_ledger_all(datum/E, cap_id = CAP_CONSTRUCTION)
	. = list()
	var/list/history = graph_history(E, cap_id)
	for(var/i in length(history) to 1 step -1)
		var/list/row = history[i]
		if(length(row[4]))
			. += list(row[4])

/// TRUE when `stage` is the current stage of E's graph, or appears in its history: "at or past" is reachability through the history, so a
/// stage never passed (another branch was taken) is not built.
/proc/built(datum/E, stage)
	READS_FROM(E)
	for(var/cap_id in list(CAP_CONSTRUCTION, CAP_DEPLOYMENT))
		var/datum/capability/construction/def = cap_of(E, cap_id)
		if(!def?.graph)
			continue
		var/current = graph_current(E, cap_id)
		if(current == stage)
			return TRUE
		if(def.graph.start == stage && graph_declares(def.graph, stage))
			return TRUE
		for(var/list/row as anything in graph_history(E, cap_id, FALSE))
			if(row[3] == stage || row[2] == stage)
				return TRUE
	return FALSE

/// Whether `stage` is a node of the graph (its start or an edge target).
/proc/graph_declares(datum/state_graph/G, stage)
	if(G.start == stage)
		return TRUE
	for(var/datum/graph_edge/edge as anything in G.edges)
		if(edge.into == stage)
			return TRUE
	return FALSE

/// The material actually used at `stage`, from the ledger entry of the transition into it that is on the path; null if it took none.
/proc/built_material(datum/E, stage)
	READS_FROM(E)
	for(var/cap_id in list(CAP_CONSTRUCTION, CAP_DEPLOYMENT))
		var/datum/capability/construction/def = cap_of(E, cap_id)
		if(!def?.graph)
			continue
		var/list/history = graph_history(E, cap_id, FALSE)
		for(var/i in length(history) to 1 step -1)
			var/list/row = history[i]
			if(row[3] == stage)
				var/list/ledger = row[4]
				return ledger?["material"]
	return null
