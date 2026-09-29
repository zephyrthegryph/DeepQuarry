/**
 * Construction (doc/rewrite/dx_conventions.md §2; the model is doc/rewrite/systems.md section 21).
 *
 * A type adds the construction capability in capabilities(), with a ladder of named stages:
 *
 *	/obj/item/camera_assembly/capabilities()
 *		. = ..()
 *		. += cap_construction(
 *			stage("loose", desc = "It is lying loose."),
 *			stage("secured", build = with_tool(TOOL_WRENCH), undo = with_tool(TOOL_WRENCH), anchored = TRUE),
 *			stage("wired", build = using(/obj/item/stack/cable_coil, amount = 2), undo = with_tool(TOOL_WIRECUTTER)),
 *			stage("finished", build = with_tool(TOOL_SCREWDRIVER), on_enter = PROC_REF(finish)),
 *		)
 *
 * Order is the graph: a stage's `build` moves the holder from the stage before it into this one, its
 * `undo` moves it back (giving back what the build took); `also` and ladder_options(anywhere = ...)
 * add branches. The ladder is built once per capability into a /datum/construction_ladder of shared
 * steps, each a capability entry (/datum/interaction/capability/construction_step): the resolver
 * offers the steps leaving the holder's stage, examine explains them ("Next: wrench it into place
 * (needs a wrench)"), use_tool() pays for them, the dispatch fingerprints, logs and marks the holder
 * changed, and messages come from a per-tool verb table unless a step says its own.
 *
 * The holder's stage lives in the capability's data (cap_data()), or in a holder var named by
 * ladder_options(state_var = NAMEOF(src, x)), or behind holder procs (ladder_options(state =, store =)).
 */

/// The construction capability: one per type's capabilities() list, shared by its instances.
/datum/capability/construction
	data_type = /datum/ladder_progress
	/// What construction() was given: stage(), branch() and ladder_options() values.
	var/list/declaration
	/// The ladder, built on first use.
	var/tmp/datum/construction_ladder/ladder

/// Per-instance construction state.
/datum/ladder_progress
	/// The holder's stage name; null until first read (then the ladder's start).
	var/stage

/**
 * The construction capability: cap_construction(stage(...), ..., ladder_options(...)). The gating
 * keywords are named args of ladder_options() only where they differ per step; the capability's
 * own `needs` / `else_say` / `behind` / `locked_by` gate every step.
 */
/proc/cap_construction(...)
	var/datum/capability/construction/made = new
	made.declaration = args.Copy()
	return made

/// The ladder of this capability, built from its declaration by the first holder asking.
/datum/capability/construction/proc/ladder_for(atom/holder)
	if(!ladder)
		ladder = new /datum/construction_ladder(src, holder.type, declaration)
	return ladder

/datum/capability/construction/interactions(atom/holder)
	var/datum/construction_ladder/built = ladder_for(holder)
	return built.edges.Copy()

/datum/capability/construction/examine(atom/holder, mob/user)
	return ladder_examine_lines(user, holder)

/// The construction ladder `target` follows, or null.
/proc/ladder_of(atom/target)
	if(!target)
		return null
	var/datum/capability/construction/C = cap_of(target, /datum/capability/construction)
	return C?.ladder_for(target)

/**
 * Puts `target` on stage `node` from outside its steps: taking a part back out by hand, a machine
 * handing back its assembly. Steps are the ladder's; this is only for the few ways a holder moves
 * that are not a step. Returns FALSE when the target has no ladder.
 */
/proc/ladder_set_stage(atom/target, node)
	var/datum/construction_ladder/ladder = ladder_of(target)
	if(!ladder)
		return FALSE
	ladder.set_state(target, node)
	changed(target, CHANGE_CAPABILITY)
	return TRUE

/// The position of `target`'s stage in its ladder (1 for the first), or 0: for sprites numbered by stage.
/proc/ladder_stage_index(atom/target)
	var/datum/construction_ladder/ladder = ladder_of(target)
	return ladder ? ladder.states.Find(ladder.state_of(target)) : 0

/// The steps leaving `target`'s stage.
/proc/ladder_steps_for(atom/target)
	var/datum/construction_ladder/ladder = ladder_of(target)
	return ladder ? ladder.edges_for(target) : list()

/// Whether `holder_type` (or an ancestor) defines a proc named `proc_name`.
/proc/ladder_holder_has_proc(holder_type, proc_name)
	for(var/path = holder_type; path; path = type2parent(path))
		if(text2path("[path]/proc/[proc_name]"))
			return TRUE
	return FALSE

// ---------------------------------------------------------------------------
// The declaration vocabulary. Plain procs: named arguments are compile-checked.

/// What a step takes. Made by with_tool(), using(), inserting(), holding() and empty_hand().
/datum/ladder_cost
	var/kind
	/// TOOL_* for tool().
	var/quality
	/// The item type (or list of types) for use(), insert() and hold().
	var/item_type
	var/amount = 0
	/// Deciseconds, or the name of a holder proc `x(actor, held)` that returns them.
	var/delay = 0
	/// Whether a tool's speed scales the wait.
	var/scaled = TRUE
	/// Welder fuel (or other tool resource) used.
	var/fuel = 0
	/// Volume of the tool's own sound; null for the default, 0 for none.
	var/volume
	/// Items standing in for the tool, with holder procs for their wait and sound.
	var/list/alt
	var/alt_delay
	var/alt_sound
	/// Holder proc `x(held)`: a finer item test.
	var/match
	/// How reasons name the item.
	var/name
	/// Sound sets played when the step starts and when it is done: list(id[, volume multiplier]).
	var/list/sfx
	var/list/done_sfx
	/// From a framework entry: its needs / else_say, as ladder_need() pairs.
	var/list/needs

/datum/ladder_cost/New(kind, quality, item_type, amount, delay, scaled, fuel, volume, list/alt, alt_delay, alt_sound, match, name, sfx, done_sfx)
	src.kind = kind
	src.quality = quality
	src.item_type = item_type
	src.amount = amount || 0
	src.delay = delay || 0
	src.scaled = isnull(scaled) ? TRUE : scaled
	src.fuel = fuel || 0
	src.volume = volume
	src.alt = alt
	src.alt_delay = alt_delay
	src.alt_sound = alt_sound
	src.match = match
	src.name = name
	if(sfx)
		src.sfx = islist(sfx) ? sfx : list(sfx)
	if(done_sfx)
		src.done_sfx = islist(done_sfx) ? done_sfx : list(done_sfx)

/// A sound set and its volume multiplier, as a cost stores them.
/proc/ladder_sfx(id, volume)
	if(!id)
		return null
	return isnull(volume) ? list(id) : list(id, volume)

/// A tool of `quality`: its sound, its speed scaling `delay`, `fuel` burned. `alt` items stand in for it.
/// `sfx` / `done_sfx` are sound sets played when the step starts and when it is done, at
/// `sfx_volume` / `done_volume` times their volume.
/proc/with_tool(quality, delay, fuel, volume, scaled, list/alt, alt_delay, alt_sound, sfx, done_sfx, sfx_volume, done_volume)
	return new /datum/ladder_cost(LADDER_COST_TOOL, quality, null, 0, delay, scaled, fuel, volume, alt, alt_delay, alt_sound, null, null, ladder_sfx(sfx, sfx_volume), ladder_sfx(done_sfx, done_volume))

/// `amount` units of a stack, or a part that is used up. Undoing the stage gives them back.
/proc/using(item_type, amount = 1, delay, match, name, sfx, done_sfx, sfx_volume, done_volume)
	return new /datum/ladder_cost(LADDER_COST_USE, null, item_type, amount, delay, TRUE, 0, null, null, null, null, match, name, ladder_sfx(sfx, sfx_volume), ladder_sfx(done_sfx, done_volume))

/// A part that goes into the holder. Undoing the stage takes it back out.
/proc/inserting(item_type, delay, match, name, sfx, done_sfx, sfx_volume, done_volume)
	return new /datum/ladder_cost(LADDER_COST_INSERT, null, item_type, 0, delay, TRUE, 0, null, null, null, null, match, name, ladder_sfx(sfx, sfx_volume), ladder_sfx(done_sfx, done_volume))

/// An item that is only checked (tape): it stays in hand.
/proc/holding(item_type, delay, match, name, sfx, done_sfx, sfx_volume, done_volume)
	return new /datum/ladder_cost(LADDER_COST_HOLD, null, item_type, 0, delay, TRUE, 0, null, null, null, null, match, name, ladder_sfx(sfx, sfx_volume), ladder_sfx(done_sfx, done_volume))

/// An empty hand.
/proc/empty_hand(delay, sfx, done_sfx, sfx_volume, done_volume)
	return new /datum/ladder_cost(LADDER_COST_HAND, null, null, 0, delay, TRUE, 0, null, null, null, null, null, null, ladder_sfx(sfx, sfx_volume), ladder_sfx(done_sfx, done_volume))

/**
 * A framework entry used as a cost: cap_tool("", TOOL_WRENCH, delay = 2 SECONDS), cap_hand(""),
 * cap_insert("", /obj/item/cell) or cap_use_on("", /obj/item/tape) with no handler (the ladder is the
 * handler). Its needs / else_say join the step's. For stack amounts, sounds, fuel or stand-in items,
 * use the ladder's own with_tool() / using() / inserting() / holding() / empty_hand().
 */
/proc/ladder_cost_from_entry(datum/capability/entry/C, datum/construction_ladder/owner, from, destination)
	var/datum/interaction/capability/E = C.entry
	if(!E)
		return null
	if(E.handler)
		LAZYADD(owner.row_errors, "[owner.id]: the cost of the step from [from] to [destination] has a handler; a ladder step's cost takes none")
	var/datum/ladder_cost/cost
	if(E.tool)
		cost = with_tool(E.tool, E.duration)
	else if(E.category == INTERACTION_CAT_INSERT)
		cost = inserting(E.held_type)
	else if(E.held_type)
		cost = holding(E.held_type)
	else
		cost = empty_hand()
	cost.needs = ladder_need(E.needs, E.else_say)
	return cost

/// A condition on a step: holder proc `needs(actor, held)` and what the actor is told when it fails.
/// The proc returns TRUE to allow; FALSE or null refuses with `else_say`; text refuses with that text.
/proc/ladder_need(needs, else_say)
	return needs ? list(list(needs, else_say)) : null

/// A branch: a step to `destination` (a stage name or LADDER_DONE; with `next`, the list of stages
/// `next` may pick). `become` (with `amount`, for a stack) replaces the holder; `on_enter` runs after
/// the stages' hooks.
/datum/ladder_branch
	var/to_stage
	var/datum/ladder_cost/cost
	var/say
	var/list/needs
	var/when
	var/on_enter
	var/list/become
	var/next
	var/priority
	var/quiet = FALSE

/// A step leaving a stage that isn't the ladder's next or previous one.
/proc/branch(destination, datum/ladder_cost/cost, say, needs, else_say, when, on_enter, become, amount, next, priority, quiet)
	var/datum/ladder_branch/made = new
	made.to_stage = destination
	made.cost = cost
	made.say = say
	made.needs = ladder_need(needs, else_say)
	made.when = when
	made.on_enter = on_enter
	if(become)
		made.become = isnull(amount) ? list(become) : list(become, amount)
	made.next = next
	made.priority = priority
	made.quiet = quiet
	return made

/// One stage of the ladder. See doc/rewrite/systems.md section 21.
/datum/ladder_stage
	var/name
	var/datum/ladder_cost/build
	var/datum/ladder_cost/undo
	var/list/needs
	var/list/undo_needs
	var/when
	var/undo_when
	var/say
	var/undo_say
	var/desc
	var/icon
	var/anchored
	var/on_enter
	var/on_leave
	var/list/also
	var/refund = TRUE
	var/priority
	var/quiet = FALSE

/proc/stage(name, datum/ladder_cost/build, datum/ladder_cost/undo, needs, else_say, undo_needs, undo_else_say, when, undo_when, say, undo_say, desc, icon, anchored, on_enter, on_leave, list/also, refund = TRUE, priority, quiet)
	var/datum/ladder_stage/made = new
	made.name = name
	made.build = build
	made.undo = undo
	made.needs = ladder_need(needs, else_say)
	made.undo_needs = ladder_need(undo_needs, undo_else_say)
	made.when = when
	made.undo_when = undo_when
	made.say = say
	made.undo_say = undo_say
	made.desc = desc
	made.icon = icon
	made.anchored = anchored
	made.on_enter = on_enter
	made.on_leave = on_leave
	made.also = also
	made.refund = refund
	made.priority = priority
	made.quiet = quiet
	return made

/// Graph-wide options (any element of the returned list).
/datum/ladder_settings
	var/state_var
	var/state
	var/set_proc
	var/list/anywhere
	var/on_step
	var/on_start
	var/list/starts
	var/start
	var/list/defaults

/// `start`: the stage a new holder is in (default the first).
/// `state_var`: a holder var holding the stage name, as NAMEOF(src, var) (default: the capability keeps it). `state` /
/// `store`: holder procs that derive and store the stage instead. `anywhere`: branches leaving every
/// stage. `on_step(actor, from, to)` after any step; `on_start(actor, held)` before a step's cost
/// (FALSE stops it). `starts`: stages a holder can be made in besides the first (a mapped
/// reinforced wall). `stance`, `category` and `needs` / `else_say` apply to every step.
/// The holder is marked changed after every step (its appearance refreshes); `on_step` is for other work.
/proc/ladder_options(start, state_var, state, store, list/anywhere, on_step, on_start, list/starts, stance, category, needs, else_say)
	var/datum/ladder_settings/made = new
	made.start = start
	made.starts = starts
	made.state_var = state_var
	made.state = state
	made.set_proc = store
	made.anywhere = anywhere
	made.on_step = on_step
	made.on_start = on_start
	made.defaults = list("stance" = stance, "category" = category, "needs" = ladder_need(needs, else_say))
	return made

// ---------------------------------------------------------------------------
// The graph

/datum/construction_ladder
	/// Stable id (the declaring type); step ids start with it.
	var/id
	/// The declaring type.
	var/declared_on
	/// Every stage name, in ladder order.
	var/list/states
	/// Stage name -> its /datum/ladder_stage.
	var/list/stage_by_name
	/// Stage name -> effective anchoring (TRUE/FALSE), when any stage sets it.
	var/list/anchoring
	/// The construction capability this ladder belongs to (its data holds the stage).
	var/tmp/datum/capability/construction/cap
	/// A holder var holding the stage name instead of the capability's data (ladder_options(state_var = NAMEOF(...))).
	var/state_var
	/// The stage a new holder is in, when not the first (ladder_options(start = ...)).
	var/start
	/// Holder procs deriving and storing the stage (ladder_options(state, store)).
	var/state_get
	var/state_set
	/// Holder procs run after any step and before a step's cost.
	var/after_proc
	var/start_proc
	/// Settings every step starts from: stance, category, needs.
	var/list/defaults
	/// Stages a holder can be made in besides the first.
	var/list/starts
	/// All steps, as shared singletons.
	var/tmp/list/edges
	/// "[stage]" -> the steps leaving it.
	var/tmp/list/edges_by_state
	/// Steps leaving every stage.
	var/tmp/list/wildcard_edges
	/// Step id -> step.
	var/tmp/list/edges_by_id
	/// Problems found while reading the declaration (validate() reports them).
	var/tmp/list/row_errors

/datum/construction_ladder/New(datum/capability/construction/owner, declared_on, list/declaration)
	..()
	cap = owner
	src.declared_on = declared_on
	id = "[declared_on]:construction"
	states = list()
	stage_by_name = list()
	edges = list()
	edges_by_state = list()
	wildcard_edges = list()
	edges_by_id = list()
	defaults = list()
	if(!islist(declaration))
		LAZYADD(row_errors, "[id]: construction() has no stages")
		return
	var/list/datum/ladder_stage/ladder = list()
	var/list/anywhere = list()
	for(var/entry in declaration)
		if(istype(entry, /datum/ladder_settings))
			var/datum/ladder_settings/options = entry
			if(options.state_var)
				state_var = options.state_var
			if(options.state)
				state_var = null
				state_get = options.state
				state_set = options.set_proc
			if(options.on_step)
				after_proc = options.on_step
			if(options.on_start)
				start_proc = options.on_start
			if(options.anywhere)
				anywhere += options.anywhere
			if(options.starts)
				starts = options.starts
			if(options.start)
				start = options.start
				starts = (starts || list()) | list(options.start)
			for(var/key in options.defaults)
				if(!isnull(options.defaults[key]))
					defaults[key] = options.defaults[key]
		else if(istype(entry, /datum/ladder_stage))
			var/datum/ladder_stage/stage = entry
			if(stage_by_name[stage.name])
				LAZYADD(row_errors, "[id]: stage [stage.name] declared twice")
				continue
			ladder += stage
			states += stage.name
			stage_by_name[stage.name] = stage
		else
			LAZYADD(row_errors, "[id]: [entry] is not a stage or ladder_options()")
	if(!length(ladder))
		LAZYADD(row_errors, "[id]: no stages")
		return
	compute_anchoring(ladder)
	for(var/i in 1 to length(ladder))
		var/datum/ladder_stage/stage = ladder[i]
		var/datum/ladder_stage/before = (i > 1) ? ladder[i - 1] : null
		if(before && stage.build)
			add_edge(new /datum/interaction/capability/construction_step(src, before.name, stage.name, stage.build, stage.say, stage.needs, stage.when, null, null, null, stage.priority, stage.quiet, TRUE, null, null))
		if(before && stage.undo)
			add_edge(new /datum/interaction/capability/construction_step(src, stage.name, before.name, stage.undo, stage.undo_say, stage.undo_needs, stage.undo_when, null, null, null, stage.priority, stage.quiet, FALSE, stage.refund ? stage.build : null, null))
		for(var/datum/ladder_branch/extra as anything in stage.also)
			add_edge(branch_edge(stage.name, extra))
	for(var/datum/ladder_branch/extra as anything in anywhere)
		add_edge(branch_edge(LADDER_ANY, extra))

/// The step a branch() declares.
/datum/construction_ladder/proc/branch_edge(from, datum/ladder_branch/extra)
	var/list/reaches = extra.next ? (islist(extra.to_stage) ? extra.to_stage : list(extra.to_stage)) : null
	var/to_stage = extra.next ? null : extra.to_stage
	return new /datum/interaction/capability/construction_step(src, from, to_stage, extra.cost, extra.say, extra.needs, extra.when, extra.on_enter, extra.become, extra.next, extra.priority, extra.quiet, TRUE, null, reaches)

/// Each stage's anchoring: the last `anchored` set at or before it; stages before the first get its opposite.
/datum/construction_ladder/proc/compute_anchoring(list/datum/ladder_stage/ladder)
	var/first_set
	for(var/datum/ladder_stage/stage as anything in ladder)
		if(!isnull(stage.anchored))
			first_set = stage.anchored
			break
	if(isnull(first_set))
		return
	anchoring = list()
	var/current = !first_set
	for(var/datum/ladder_stage/stage as anything in ladder)
		if(!isnull(stage.anchored))
			current = stage.anchored
		anchoring[stage.name] = current

/// Registers a step and gives it an id.
/datum/construction_ladder/proc/add_edge(datum/interaction/capability/construction_step/edge)
	var/base_id = "[id]:[edge.from_state]>[isnull(edge.to_state) ? "?" : edge.to_state]:[edge.tool || edge.item_key()]"
	edge.id = base_id
	var/n = 1
	while(edges_by_id[edge.id])
		n++
		edge.id = "[base_id]#[n]"
	edges += edge
	edges_by_id[edge.id] = edge
	if(edge.from_state == LADDER_ANY)
		wildcard_edges += edge
	else
		LAZYADD(edges_by_state[edge.from_state], edge)
	return edge

/// The holder's stage, or null when it isn't on this graph right now.
/datum/construction_ladder/proc/state_of(atom/target)
	if(state_get)
		return call(target, state_get)()
	if(state_var)
		return target.vars[state_var]
	var/datum/ladder_progress/progress = cap_data(target, cap)
	if(isnull(progress.stage))
		progress.stage = start || states[1]
	return progress.stage

/// Stores the stage on the holder.
/datum/construction_ladder/proc/set_state(atom/target, state)
	if(state == LADDER_DONE || QDELETED(target))
		return
	if(state_get)
		if(state_set)
			call(target, state_set)(state)
		return
	if(state_var)
		target.vars[state_var] = state // ALLOW(api): a ladder names the var holding its stage
	else
		var/datum/ladder_progress/progress = cap_data(target, cap)
		progress.stage = state

/// The steps leaving `state`.
/datum/construction_ladder/proc/edges_leaving(state)
	if(isnull(state))
		return list()
	var/list/fixed = edges_by_state["[state]"]
	if(!length(wildcard_edges))
		return fixed || list()
	return (fixed || list()) + wildcard_edges

/// The steps leaving the holder's stage.
/datum/construction_ladder/proc/edges_for(atom/target)
	return edges_leaving(state_of(target))

/// The examine line for the holder's stage, or null.
/datum/construction_ladder/proc/node_desc(atom/target)
	var/datum/ladder_stage/stage = stage_by_name["[state_of(target)]"]
	return stage?.desc

/**
 * Problems with this graph, as text; empty when it is valid: stages declared twice, steps that take
 * nothing or lead nowhere, requirements that don't compile, holder procs the declaration names that
 * the declaring type doesn't have, stages no step reaches from the first stage or a declared start.
 * Unit tests call this for every graph.
 */
/datum/construction_ladder/proc/validate()
	. = list()
	if(row_errors)
		. += row_errors
	if(!length(states))
		return
	for(var/proc_name in list(state_get, state_set, after_proc, start_proc))
		if(proc_name && !ladder_holder_has_proc(declared_on, proc_name))
			. += "[id]: [declared_on] has no proc [proc_name]"
	for(var/name in stage_by_name)
		var/datum/ladder_stage/stage = stage_by_name[name]
		for(var/proc_name in list(stage.on_enter, stage.on_leave, stage.when, stage.undo_when))
			if(proc_name && !ladder_holder_has_proc(declared_on, proc_name))
				. += "[id]: stage [name]: [declared_on] has no proc [proc_name]"
	for(var/datum/interaction/capability/construction_step/edge as anything in edges)
		if(!edge.phrase)
			. += "[edge.id]: no phrase"
		if(!edge.tool && !edge.item_type && !edge.by_hand)
			. += "[edge.id]: takes nothing"
		if(!isnull(edge.to_state) && edge.to_state != LADDER_DONE && !stage_by_name["[edge.to_state]"])
			. += "[edge.id]: leads to unknown stage [edge.to_state]"
		for(var/next in edge.reaches)
			if(next != LADDER_DONE && !stage_by_name["[next]"])
				. += "[edge.id]: may lead to unknown stage [next]"
		if(isnull(edge.to_state) && !edge.next_proc)
			. += "[edge.id]: leads nowhere"
		if(edge.become && edge.to_state != LADDER_DONE)
			. += "[edge.id]: replaces the holder but doesn't leave the graph"
		var/datum/predicate/pred = edge.predicate()
		if(pred?.errors)
			. += "[edge.id]: requirements don't compile: [jointext(pred.errors, "; ")]"
		for(var/proc_name in edge.holder_procs())
			if(!ladder_holder_has_proc(declared_on, proc_name))
				. += "[edge.id]: [declared_on] has no proc [proc_name]"
	// Every stage is reachable from the first one or a listed start.
	var/list/reached = list()
	var/list/queue = list(states[1])
	reached["[states[1]]"] = TRUE
	for(var/start in starts)
		if(!reached["[start]"])
			reached["[start]"] = TRUE
			queue += list(start)
	while(length(queue))
		var/state = queue[1]
		queue.Cut(1, 2)
		for(var/datum/interaction/capability/construction_step/edge as anything in edges_leaving(state))
			var/list/nexts = edge.next_proc ? edge.reaches : list(edge.to_state)
			for(var/next in nexts)
				if(next == LADDER_DONE || !stage_by_name["[next]"] || reached["[next]"])
					continue
				reached["[next]"] = TRUE
				queue += list(next)
	for(var/state in states)
		if(!reached["[state]"])
			. += "[id]: stage [state] is unreachable"

// ---------------------------------------------------------------------------
// Steps: one shared interaction per step.

/datum/interaction/capability/construction_step
	category = INTERACTION_CAT_MAINTAIN
	default_action = INPUT_ACTION_USE
	priority = 10
	requires = list(REQ_REACH_ADJACENT)
	works_broken = TRUE
	works_unpowered = TRUE
	/// The graph this step belongs to.
	var/tmp/datum/construction_ladder/graph
	/// The stage it leaves, or LADDER_ANY.
	var/from_state
	/// The stage it reaches, LADDER_DONE when the holder becomes something else; null with next_proc.
	var/to_state
	/// Holder proc picking the next stage, and the stages it may pick.
	var/next_proc
	var/list/reaches
	/// What the step does, with %T% (the holder) and %I% (the item): "wrench %T% into place".
	var/phrase
	/// Whether it builds (TRUE) or undoes (FALSE): which verb the tool table gives.
	var/forward = TRUE
	/// A held item this step needs instead of a tool: a type or a list of types.
	var/item_type
	/// For a stack, how many units it needs.
	var/item_amount = 0
	/// LADDER_ITEM_*: what happens to the held item.
	var/item_use = LADDER_ITEM_KEEP
	/// How reasons name the item.
	var/item_name
	/// list(list(holder proc, refusal text), ...): the step's own conditions (the capability's
	/// `needs` / `else_say` gate every step through cap_gate_reason()).
	var/list/step_needs
	/// Holder procs: a finer item test, the wait, whether the step is offered, the step's own hook.
	var/match_proc
	var/delay_proc
	var/when_proc
	var/step_hook
	/// Items standing in for `tool`, and holder procs for their wait and sound.
	var/list/alt_item_types
	var/alt_delay_proc
	var/alt_sound_proc
	/// Whether the wait scales with the tool's speed.
	var/tool_scaled = TRUE
	/// Done with an empty hand: meant only when the actor holds nothing.
	var/by_hand = FALSE
	/// Sound sets when the step starts and when it is done: list(id[, volume multiplier]).
	var/list/start_sfx
	var/list/done_sfx
	/// The build cost undone by this step: what comes back (stack units, a new part, the inserted part).
	var/datum/ladder_cost/refund
	/// list(type, args...) the holder is replaced by.
	var/list/become
	/// No generated messages (the hook says it).
	var/quiet = FALSE
	/// The compiled predicate without the tool clause, for alt items.
	var/tmp/datum/predicate/compiled_alt

/datum/interaction/capability/construction_step/New(datum/construction_ladder/owner, from, destination, datum/ladder_cost/cost, say, list/step_needs, when, on_enter, list/become, next, step_priority, quiet, forward, datum/ladder_cost/refund, list/reaches)
	graph = owner
	from_state = from
	to_state = destination
	src.forward = forward
	src.refund = refund
	src.become = become
	src.quiet = quiet
	src.reaches = reaches
	next_proc = next
	when_proc = when
	step_hook = on_enter
	tags = list(INTERACTION_TAG_CONSTRUCTION)
	if(become && isnull(to_state))
		to_state = LADDER_DONE
	if(!isnull(step_priority))
		priority = step_priority
	var/list/defaults = owner.defaults
	if(defaults["stance"])
		stance = defaults["stance"]
	if(defaults["category"])
		category = defaults["category"]
	if(length(defaults["needs"]))
		src.step_needs = defaults["needs"]
	if(length(step_needs))
		src.step_needs = length(src.step_needs) ? src.step_needs + step_needs : step_needs
	cap = owner.cap
	if(cap)
		behind = cap.behind
		locked_by = cap.locked_by
		needs = cap.needs
		else_say = cap.else_say
		log = cap.log
	if(istype(cost, /datum/capability/entry))
		cost = ladder_cost_from_entry(cost, owner, from, destination)
	if(cost)
		read_cost(cost)
	else
		LAZYADD(owner.row_errors, "[owner.id]: a step from [from] to [destination] has no cost")
	phrase = say || generated_phrase()
	name = capitalize(next_text())
	..()

/// Copies what a cost takes onto the step.
/datum/interaction/capability/construction_step/proc/read_cost(datum/ladder_cost/cost)
	switch(cost.kind)
		if(LADDER_COST_TOOL)
			tool = cost.quality
			tool_amount = cost.fuel
			alt_item_types = cost.alt
			alt_delay_proc = cost.alt_delay
			alt_sound_proc = cost.alt_sound
		if(LADDER_COST_USE)
			item_type = cost.item_type
			var/first = islist(item_type) ? item_type[1] : item_type
			if(ispath(first, /obj/item/stack))
				item_amount = cost.amount
				item_use = LADDER_ITEM_USE
			else
				item_use = LADDER_ITEM_DELETE
		if(LADDER_COST_INSERT)
			item_type = cost.item_type
			item_use = LADDER_ITEM_INSERT
		if(LADDER_COST_HOLD)
			item_type = cost.item_type
		if(LADDER_COST_HAND)
			by_hand = TRUE
			offered_when = list(REQ_EMPTY_HANDED)
	if(istext(cost.delay))
		delay_proc = cost.delay
	else
		duration = cost.delay
	tool_scaled = cost.scaled
	if(!isnull(cost.volume))
		tool_volume = cost.volume
	if(length(cost.needs))
		step_needs = length(step_needs) ? step_needs + cost.needs : cost.needs
	match_proc = cost.match
	item_name = cost.name
	start_sfx = cost.sfx
	done_sfx = cost.done_sfx
	// An item step is meant only with that kind of item in hand, as a tool step is with the tool.
	if(item_type)
		held_type = item_type

/// Every holder proc this step names, for validate().
/datum/interaction/capability/construction_step/proc/holder_procs()
	. = list()
	for(var/proc_name in list(next_proc, match_proc, alt_delay_proc, alt_sound_proc, when_proc, delay_proc, step_hook))
		if(proc_name)
			. += proc_name
	for(var/list/need as anything in step_needs)
		. += need[1]

// ---- Generated text ----

/// The phrase the verb table gives this step's cost and direction.
/datum/interaction/capability/construction_step/proc/generated_phrase()
	if(tool)
		return ladder_tool_phrase(tool, forward)
	if(by_hand)
		return refund ? "take [refund_noun()] out of %T%" : "work on %T% by hand"
	switch(item_use)
		if(LADDER_ITEM_INSERT)
			return "put %I% into %T%"
		if(LADDER_ITEM_USE, LADDER_ITEM_DELETE)
			return "add %I% to %T%"
	return "use %I% on %T%"

/// The examine "Next:" text: the phrase with "it" for the holder and the item's name for %I%.
/datum/interaction/capability/construction_step/proc/next_text()
	var/text = replacetext(phrase, "%T%", "it")
	return replacetext(text, "%I%", item_type ? item_text() : "it")

/// What undoing gives back, as a noun ("the cable coil").
/datum/interaction/capability/construction_step/proc/refund_noun()
	var/obj/item/path = islist(refund?.item_type) ? refund.item_type[1] : refund?.item_type
	return path ? "the [initial(path.name)]" : "the part"

/// "You wrench the camera assembly into place." / "Bob wrenches ...", with %T%/%I% tokens.
/datum/interaction/capability/construction_step/proc/done_lines()
	if(quiet)
		return null
	return list("You [phrase].", "%U% [ladder_third_person(phrase)].")

/datum/interaction/capability/construction_step/start_lines(mob/actor, atom/target, obj/item/held)
	if(quiet)
		return null
	return list("You start to [phrase].", "%U% starts to [phrase].")

/// Offered when the holder is in a stage this step leaves, and its `when` agrees.
/datum/interaction/capability/construction_step/applies_to(atom/target)
	var/state = graph.state_of(target)
	if(isnull(state))
		return FALSE
	if(from_state != LADDER_ANY && "[state]" != "[from_state]")
		return FALSE
	return when_proc ? call(target, when_proc)() : TRUE

/// Steps are instances: key the shared predicates by step id.
/datum/interaction/capability/construction_step/predicate_key()
	return "ladder:[id]"

/datum/interaction/capability/construction_step/why_not(mob/actor, atom/target, obj/item/held)
	// Re-checked after the wait: the holder may have moved on to another stage.
	if(!applies_to(target))
		return "it has changed"
	if(is_alt_item(held))
		var/datum/predicate/pred = alt_predicate()
		. = pred?.why_not(actor, target, held)
	else
		. = ..()
	if(.)
		return
	for(var/list/need as anything in step_needs)
		var/answer = call(target, need[1])(actor, held)
		if(istext(answer))
			return answer
		if(!answer)
			return need[2] || "you can't do that right now"
	if(item_type)
		return item_failure(target, held)

/// The requirements without the tool clause, for alt items.
/datum/interaction/capability/construction_step/proc/alt_predicate()
	if(compiled_alt || !length(requires))
		return compiled_alt
	compiled_alt = dq_predicate_for("ladder-alt:[id]", requires, "construction step [id] (alt item)")
	return compiled_alt

/// Whether `held` is one of the items standing in for the tool.
/datum/interaction/capability/construction_step/proc/is_alt_item(obj/item/held)
	if(!held || !length(alt_item_types))
		return FALSE
	for(var/path in alt_item_types)
		if(istype(held, path))
			return TRUE
	return FALSE

/// The unscaled wait for an alt item (use_tool() scales it by the item's toolspeed).
/datum/interaction/capability/construction_step/proc/alt_wait(mob/actor, atom/target, obj/item/held)
	return alt_delay_proc ? call(target, alt_delay_proc)(actor, held) : base_duration(actor, target)

/datum/interaction/capability/construction_step/base_duration(mob/actor, atom/target)
	return delay_proc ? call(target, delay_proc)(actor, null) : duration

/datum/interaction/capability/construction_step/duration_for(mob/actor, atom/target, obj/item/held)
#ifdef UNIT_TESTS
	if(GLOB.dq_ladder_instant)
		return 0
#endif
	var/wait = delay_proc ? call(target, delay_proc)(actor, held) : duration
	if(tool && tool_scaled)
		return tool_delay(actor, held, wait, tool)
	return wait

/datum/interaction/capability/construction_step/pay_cost(mob/actor, atom/target, obj/item/held)
	if(graph.start_proc)
		// FALSE (not null) stops the step before its cost: a shock, a refusal only known now.
		var/started = call(target, graph.start_proc)(actor, held)
		if(!isnull(started) && !started)
			return FALSE
	if(start_sfx)
		play_sfx(target, start_sfx[1], length(start_sfx) > 1 ? start_sfx[2] : 1)
	if(!is_alt_item(held))
		return ..()
	var/sound = alt_sound_proc ? call(target, alt_sound_proc)(held) : held.usesound
	if(sound && tool_volume)
		playsound(target, sound, tool_volume, TRUE)
	var/wait = alt_wait(actor, target, held)
#ifdef UNIT_TESTS
	if(GLOB.dq_ladder_instant)
		wait = 0
#endif
	var/list/lines = start_lines(actor, target, held)
	return use_tool(actor, held, target, delay = wait, volume = 0,
		start_self = lines?[1], start_others = lines?[2],
		receiver = src, job_type = /datum/om/task/timed/tool_job/interaction, job_params = list("held" = held))

/// Why `held` won't do for this step's item, or null.
/datum/interaction/capability/construction_step/proc/item_failure(atom/target, obj/item/held)
	if(!held || !item_matches(target, held))
		return "needs [item_text()]"
	if(item_amount && istype(held, /obj/item/stack))
		var/obj/item/stack/stack = held
		if(stack.get_amount() < item_amount)
			return "needs [item_text()]"
	return null

/// Whether `held` is the kind of item this step takes.
/datum/interaction/capability/construction_step/proc/item_matches(atom/target, obj/item/held)
	var/typed = FALSE
	if(islist(item_type))
		for(var/path in item_type)
			if(istype(held, path))
				typed = TRUE
				break
	else
		typed = istype(held, item_type)
	if(!typed)
		return FALSE
	return match_proc ? call(target, match_proc)(held) : TRUE

/// "5 steel sheets", "a cell".
/datum/interaction/capability/construction_step/proc/item_text()
	var/noun = item_name
	if(!noun)
		var/obj/item/path = islist(item_type) ? item_type[1] : item_type
		noun = initial(path.name)
	if(item_amount > 1)
		return "[item_amount] [noun]"
	return dq_pred_article(noun)

/// Short key for generated ids: the item's type name.
/datum/interaction/capability/construction_step/proc/item_key()
	if(by_hand)
		return "hand"
	var/path = islist(item_type) ? item_type[1] : item_type
	if(!path)
		return "none"
	var/text = "[path]"
	var/slash = findlasttext(text, "/")
	return slash ? copytext(text, slash + 1) : text

/// "needs a welder", "needs 5 steel sheets".
/datum/interaction/capability/construction_step/proc/requirement_text()
	var/list/parts = list()
	if(tool)
		parts += dq_pred_article(dq_pred_tool_name(tool))
	if(item_type)
		parts += item_text()
	if(by_hand)
		parts += "an empty hand"
	return length(parts) ? "needs [jointext(parts, " and ")]" : null

/// The stage this step reaches from `state` on `target`.
/datum/interaction/capability/construction_step/proc/next_state(atom/target, state)
	if(next_proc)
		return call(target, next_proc)(state)
	return to_state

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
/// Unit tests set this to run construction steps with no wait.
GLOBAL_VAR_INIT(dq_ladder_instant, FALSE)
#endif

/**
 * Runs the step on `target` after its cost is paid: the item, the stage stored, anchoring, what
 * an undo gives back, the stages' on_leave/on_enter and the step's own hook, the icon, the
 * replacement, the message and sound, then the graph's on_step.
 */
/datum/interaction/capability/construction_step/proc/traverse(atom/target, mob/actor, obj/item/held)
	var/turf/where = get_turf(target)
	var/before = graph.state_of(target)
	var/after = next_state(target, before)
	if(isnull(after))
		return FALSE
	if(item_type && item_use == LADDER_ITEM_USE && item_amount)
		var/obj/item/stack/stack = held
		if(!istype(stack) || !stack.use(item_amount))
			to_chat(actor, span_warning("You need [item_text()] for this."))
			return FALSE
	if(item_type && item_use == LADDER_ITEM_INSERT && held)
		actor.drop_from_inventory(held)
		held.forceMove(target)
	var/datum/ladder_stage/left = graph.stage_by_name["[before]"]
	var/datum/ladder_stage/entered = graph.stage_by_name["[after]"]
	// on_leave runs while the holder is still in the stage it leaves; FALSE (not null) refuses.
	if(left?.on_leave && left != entered)
		var/leaving = call(target, left.on_leave)(actor, held, after)
		if(QDELETED(target) || (!isnull(leaving) && !leaving))
			return FALSE
	var/was_anchored
	if(ismovable(target))
		var/atom/movable/movable = target
		was_anchored = movable.anchored
	graph.set_state(target, after)
	apply_anchoring(target, after)
	if(refund)
		give_back(target, where)
	var/list/hooks = list()
	if(entered?.on_enter && left != entered)
		hooks += entered.on_enter
	if(step_hook)
		hooks += step_hook
	for(var/hook in hooks)
		if(QDELETED(target))
			break
		// FALSE (not null: a plain helper returns null) refuses: the stage and anchoring go back.
		var/result = call(target, hook)(actor, held, before)
		if(!isnull(result) && !result)
			if(!QDELETED(target))
				graph.set_state(target, before)
				if(!isnull(was_anchored))
					var/atom/movable/movable = target
					movable.set_anchored(was_anchored)
			return FALSE
	if(item_type && item_use == LADDER_ITEM_DELETE && !QDELETED(held))
		consume(held, actor)
	if(entered?.icon && !QDELETED(target))
		target.icon_state = entered.icon
	var/list/lines = done_lines()
	if(lines)
		act_message(actor, target, msg_span(lines[1], "notice"), msg_span(lines[2], "notice"), item = held)
	if(done_sfx)
		play_sfx(where || target, done_sfx[1], length(done_sfx) > 1 ? done_sfx[2] : 1)
	if(become && !QDELETED(target) && ismovable(target))
		var/list/replace_args = list(target) + become
		replace_with(arglist(replace_args))
	// A turf that changed into something else (a cut-open wall) no longer has the graph's procs.
	if(graph.after_proc && !QDELETED(target) && hascall(target, graph.after_proc))
		call(target, graph.after_proc)(actor, before, after)
	return TRUE

/// Sets the holder's anchoring for `stage`, when the ladder says it.
/datum/interaction/capability/construction_step/proc/apply_anchoring(atom/target, stage)
	if(!graph.anchoring || !ismovable(target))
		return
	var/value = graph.anchoring["[stage]"]
	if(isnull(value))
		return
	var/atom/movable/movable = target
	if(movable.anchored != value)
		movable.set_anchored(value)

/// Gives back what the undone stage's build took: the stack units, a new part, or the inserted part.
/datum/interaction/capability/construction_step/proc/give_back(atom/target, turf/where)
	if(!where)
		return
	var/path = islist(refund.item_type) ? refund.item_type[1] : refund.item_type
	if(!path)
		return
	switch(refund.kind)
		if(LADDER_COST_USE)
			if(ispath(path, /obj/item/stack))
				new path(where, max(refund.amount, 1))
			else
				new path(where)
		if(LADDER_COST_INSERT)
			var/obj/item/part
			if(islist(refund.item_type))
				for(var/part_type in refund.item_type)
					part = locate_within(target, part_type)
					if(part)
						break
			else
				part = locate_within(target, path)
			part?.forceMove(where)

/**
 * Runs the step leaving `target`'s stage that `held` stands in a tool for (a plasma cutter on a
 * wall): items without the step's tool quality never reach the resolver's tool path. TRUE if one was found.
 */
/proc/try_ladder_alt(mob/user, atom/target, obj/item/held)
	for(var/datum/interaction/capability/construction_step/edge as anything in ladder_steps_for(target))
		if(edge.is_alt_item(held) && edge.applies_to(target))
			edge.perform(user, target, held)
			return TRUE
	return FALSE

/// Construction steps run through the central dispatch (fingerprint, log, changed()) like every entry.
/datum/interaction/capability/construction_step/run_effect(mob/actor, atom/target, obj/item/held)
	var/datum/dispatch_context/ctx = new(actor, target, held, src)
	. = dispatch_call(ctx, target, TYPE_PROC_REF(/atom, traverse_ladder_step), list("user" = actor, "held" = held, "step" = src), name, log)
	if(isnull(.))
		. = TRUE

/// The handler every construction step dispatches to.
/atom/proc/traverse_ladder_step(mob/user, obj/item/held, datum/interaction/capability/construction_step/step)
	return step.traverse(src, user, held)

// ---------------------------------------------------------------------------
// The verb table

/// The phrase a tool gives a step: building (`forward`) or undoing.
/proc/ladder_tool_phrase(quality, forward)
	switch(quality)
		if(TOOL_WRENCH)
			return forward ? "wrench %T% into place" : "unwrench %T%"
		if(TOOL_SCREWDRIVER)
			return forward ? "screw %T% shut" : "unscrew %T%"
		if(TOOL_WELDER)
			return forward ? "weld %T% in place" : "cut %T% free"
		if(TOOL_WIRECUTTER)
			return forward ? "trim the wires of %T%" : "cut the wires out of %T%"
		if(TOOL_CROWBAR)
			return forward ? "pry %T% into place" : "pry %T% open"
		if(TOOL_MULTITOOL)
			return forward ? "configure %T%" : "reset %T%"
	return forward ? "work on %T% with %I%" : "take %T% apart with %I%"

/// "wrench %T% into place" -> "wrenches %T% into place": the first word in the third person.
/proc/ladder_third_person(phrase)
	var/space = findtext(phrase, " ")
	var/verb = space ? copytext(phrase, 1, space) : phrase
	var/rest = space ? copytext(phrase, space) : ""
	var/last = copytext(verb, -1)
	var/last_two = copytext(verb, -2)
	if(last == "y" && !(copytext(verb, -2, -1) in list("a", "e", "i", "o", "u")))
		verb = copytext(verb, 1, -1) + "ies"
	else if((last in list("s", "x", "z", "o")) || (last_two in list("sh", "ch")))
		verb += "es"
	else
		verb += "s"
	return verb + rest

// ---------------------------------------------------------------------------
// Examine

/// The stage's line, then "Next: wrench it into place (needs a wrench)" per step offered now. Null if none.
/proc/ladder_examine_lines(mob/user, atom/target)
	var/datum/construction_ladder/graph = ladder_of(target)
	if(!graph)
		return null
	var/list/lines = list()
	var/desc = graph.node_desc(target)
	if(desc)
		lines += span_notice(desc)
	for(var/datum/interaction/capability/construction_step/edge as anything in graph.edges_for(target))
		if(!edge.applies_to(target))
			continue
		var/needs = edge.requirement_text()
		lines += span_notice("Next: [edge.next_text()][needs ? " ([needs])" : ""]")
	return length(lines) ? lines : null

/// "Wrench it into place (needs a wrench)." per step the holder offers now, unstyled (description panels).
/proc/ladder_step_lines(atom/target)
	. = list()
	var/datum/construction_ladder/graph = ladder_of(target)
	if(!graph)
		return
	for(var/datum/interaction/capability/construction_step/edge as anything in graph.edges_for(target))
		if(!edge.applies_to(target))
			continue
		var/needs = edge.requirement_text()
		. += "[capitalize(edge.next_text())][needs ? " ([needs])" : ""]."


