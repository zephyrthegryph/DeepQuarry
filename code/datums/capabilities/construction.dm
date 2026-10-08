/**
 * Construction (doc/rewrite/dx_conventions.md §2; the model is doc/rewrite/systems.md section 21).
 *
 * A type adds the construction capability in capabilities(), with a ladder of named stages:
 *
 *	/obj/item/camera_assembly/capabilities()
 *		. = ..()
 *		. += cap_construction(
 *			stage("loose", desc = "It is lying loose."),
 *			stage("secured", build = cap_tool(quality = TOOL_WRENCH), undo = cap_tool(quality = TOOL_WRENCH), anchored = TRUE),
 *			stage("wired", build = cap_use_on(held_type = /obj/item/stack/cable_coil), uses = 2, undo = cap_tool(quality = TOOL_WIRECUTTER)),
 *			stage("finished", build = cap_tool(quality = TOOL_SCREWDRIVER), icon = "camera_done", on_enter = PROC_REF(finish)),
 *		)
 *
 * Order is the graph: a stage's `build` moves the holder from the stage before it into this one, its
 * `undo` moves it back (giving back what the build took); `also` and ladder_options(anywhere = ...)
 * add branches.
 *
 * Costs are the framework's own entries with no handler (the ladder is the handler):
 *	cap_tool(quality =, delay =, fuel =, volume =)	a tool; fuel is welder fuel, volume its sound
 *	cap_insert(held_type =, delay =)				a part that goes into the holder (undo takes it back out)
 *	cap_use_on(held_type =, delay =)				an item only checked; with the stage's `uses = N`, N
 *													stack units (or the part itself) are used up and
 *													undoing gives them back
 *	cap_hand(delay =)								an empty hand
 * The entry's needs / else_say join the step's; its name, when given, names the item in reasons
 * ("needs 2 glass sheets"). Sounds are the stage's / branch's `sfx` (on start) and `done_sfx`.
 *
 * The ladder is built once per capability into a /datum/construction_ladder of shared steps, each a
 * capability entry (/datum/interaction/capability/construction_step): the resolver offers the steps
 * leaving the holder's stage, examine explains them ("Next: wrench it into place (needs a wrench)"),
 * use_tool() pays for them, dispatch_call() fingerprints, logs and marks the holder changed, and
 * messages come from a per-tool verb table unless a step says its own. A stage's `icon` is drawn
 * through draw(look) (look.state()), never written to icon_state.
 *
 * The holder's stage lives in the capability's data (cap_data(), made by legacy_holder_init()), or in a
 * holder var named by ladder_options(state_var = nameof(src.x)), or behind holder procs
 * (ladder_options(state =, store =)).
 *
 * Naming: the internal ladder_* procs, LADDER_* defines and /datum/construction_ladder keep their
 * temporary names until the old /datum/construction_graph system is deleted at migration; then they
 * take the construction_* names.
 */

/// The construction capability: one per type's capabilities() list, shared by its instances.
/datum/capability/construction
	data_type = /datum/ladder_progress
	/// What cap_construction() was given: stage() and ladder_options() values. These are plain
	/// declaration values holding no entity (costs are read into LCOST_* specs when declared), so the
	/// type_list rebuilds and capability interning can drop copies of them without teardown.
	var/list/declaration
	/// The ladder, built on first use.
	var/tmp/datum/construction_ladder/ladder

CAPABILITIES(/datum/capability/construction)
	owns_one(nameof(ladder), /datum/construction_ladder)

/// Per-instance construction state.
/datum/ladder_progress
	/// The holder's stage name.
	var/stage

/**
 * The construction capability: cap_construction(stage(...), ..., ladder_options(...)). The standard
 * gating arguments (needs, with state gates as req_set / req_clear; else_say, works_broken, works_unpowered,
 * log) are ladder_options() arguments: they gate every step.
 */
/proc/cap_construction(...)
	var/datum/capability/construction/made = new
	made.declaration = ladder_flatten_declaration(args)
	made.works_broken = TRUE
	made.works_unpowered = TRUE
	for(var/datum/ladder_settings/options in made.declaration)
		cap_gating(made, needs = options.needs, else_say = options.else_say, works_broken = options.works_broken,
			works_unpowered = options.works_unpowered, log = options.log)
		made.behind |= options.behind
		made.blocked_by |= options.blocked_by
		made.locked_by |= options.locked_by
	return made

/// The ladder of this capability, built from its declaration by the first holder asking. The ladder
/// and its steps are the capability's only owned entities: built once, on the kept (interned) capability.
/datum/capability/construction/proc/ladder_for(atom/holder)
	if(!ladder)
		rel_set(src, nameof(src.ladder), new /datum/construction_ladder(src, holder.type))
	return ladder

/datum/capability/construction/interactions(atom/holder)
	var/datum/construction_ladder/built = ladder_for(holder)
	return built.edges.Copy()

/datum/capability/construction/examine(atom/holder, mob/user)
	return ladder_examine_lines(user, holder)

/// A new holder starts on the ladder's start stage (kept in the capability's data).
/datum/capability/construction/legacy_holder_init(atom/holder, mapload)
	var/datum/construction_ladder/built = ladder_for(holder)
	if(built.keeps_stage())
		var/datum/ladder_progress/progress = cap_data(holder, src)
		progress.stage = built.start || built.states[1]

/datum/capability/construction/legacy_holder_destroy(atom/holder)
	var/datum/ladder_progress/progress = capability_data(holder)?[key]
	if(progress)
		LAZYREMOVE(capability_runtime(holder).data, key)
		ended_with(progress, holder)

/// The stage's icon state, when the ladder draws its stages. Writes no holder state (ladder_for()
/// only builds the type's shared ladder the first time, which the type's first draw may be).
/datum/capability/construction/draw(atom/holder, datum/look/look)
	var/datum/construction_ladder/built = ladder_for(holder)
	if(!built.draws_icons)
		return
	var/datum/ladder_stage/stage = built.stage_named(built.state_of(holder))
	look.state(stage?.icon || initial(holder.icon_state))

/// The construction ladder `target` follows, or null.
/proc/ladder_of(atom/target)
	RETURN_TYPE(/datum/construction_ladder)
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

/// Whether `holder_type` (or an ancestor) defines the proc `proc_path` names (a PROC_REF value).
/proc/ladder_holder_has_proc(holder_type, proc_path)
	var/proc_name = "[proc_path]"
	var/slash = findlasttext(proc_name, "/")
	if(slash)
		proc_name = copytext(proc_name, slash + 1)
	for(var/path = holder_type; path; path = type2parent(path))
		if(text2path("[path]/proc/[proc_name]"))
			return TRUE
	return FALSE

// ---------------------------------------------------------------------------
// The declaration vocabulary. Plain procs: named arguments are compile-checked.

/// A condition on a step: holder proc `needs(actor, held)` and what the actor is told when it fails.
/// The proc returns TRUE to allow; FALSE or null refuses with `else_say`; text refuses with that text.
/// `needs` may be a list of procs sharing `else_say`.
/proc/ladder_need(needs, else_say)
	if(!needs)
		return null
	. = list()
	for(var/need in (islist(needs) ? needs : list(needs)))
		. += list(list(need, else_say))

/**
 * A cost entry read into plain values (LCOST_*): cap_tool(), cap_insert(), cap_use_on() or cap_hand()
 * with no handler. `uses` makes a cap_use_on() item used up (stack units, or the part itself). Null
 * for no cost; a spec with a null kind when `entry` is not a cost entry (validate() reports it).
 */
/proc/ladder_cost_spec(datum/capability/entry/entry, uses = 0)
	if(isnull(entry))
		return null
	var/list/spec = new /list(LCOST_LEN)
	var/datum/interaction/capability/E = istype(entry) ? entry.entry : null
	if(!E)
		return spec
	spec[LCOST_KIND] = ladder_entry_kind(E, uses)
	spec[LCOST_TOOL] = E.tool
	spec[LCOST_ITEM] = E.held_type
	spec[LCOST_USES] = uses
	spec[LCOST_DELAY] = E.duration
	spec[LCOST_FUEL] = E.tool_amount
	spec[LCOST_VOLUME] = E.tool_volume
	spec[LCOST_NAME] = length(E.name) ? E.name : null
	spec[LCOST_NEEDS] = ladder_need(E.needs, E.else_say)
	spec[LCOST_HANDLER] = !!E.handler
	return spec

/// A branch: a step to `destination` (a stage name or LADDER_DONE; with `next`, the list of stages
/// `next` may pick). `become` (with `amount`, for a stack) replaces the holder; `on_enter` runs after
/// the stages' hooks.
/datum/ladder_branch
	var/to_stage
	/// ladder_cost_spec() of the step's cost.
	var/list/cost
	var/say
	var/list/needs
	var/when
	var/on_enter
	var/list/become
	var/next
	var/priority
	var/quiet = FALSE
	var/sfx
	var/done_sfx
	/// A holder proc that says the holder is ruined now (a broken frame): the step then makes `ruined_become` instead of `become`.
	var/ruined_when
	var/list/ruined_become

/// A step leaving a stage that isn't the ladder's next or previous one.
/proc/branch(destination, datum/capability/entry/cost, uses = 0, say, needs, else_say, when, on_enter, become, amount, next, priority, quiet = FALSE, sfx, done_sfx)
	var/datum/ladder_branch/made = new
	made.to_stage = destination
	made.cost = ladder_cost_spec(cost, uses)
	made.say = say
	made.needs = ladder_need(needs, else_say)
	made.when = when
	made.on_enter = on_enter
	if(become)
		made.become = isnull(amount) ? list(become) : list(become, amount)
	made.next = next
	made.priority = priority
	made.quiet = quiet
	made.sfx = sfx
	made.done_sfx = done_sfx
	return made

/// One stage of the ladder. See doc/rewrite/systems.md section 21.
/datum/ladder_stage
	var/name
	/// ladder_cost_spec() of the build (from the stage before) and of the undo (back to it).
	var/list/build
	var/list/undo
	var/list/needs
	var/list/undo_needs
	var/when
	var/undo_when
	var/say
	var/undo_say
	var/desc
	/// The icon state drawn on this stage (draw(look)); null draws the holder's type default.
	var/icon
	var/anchored
	var/on_enter
	var/on_leave
	/// Branches leaving this stage.
	var/list/also
	var/refund = TRUE
	var/priority
	var/quiet = FALSE
	/// Sound sets of the build step: when it starts and when it is done.
	var/sfx
	var/done_sfx

/// A stage. `build` / `undo`: cost entries (see the file header); `uses`: what a cap_use_on() build
/// uses up; `sfx` / `done_sfx`: sound sets of the build step; `icon`: the state drawn on this stage.
/proc/legacy_stage(name, datum/capability/entry/build, datum/capability/entry/undo, uses = 0, needs, else_say, undo_needs, undo_else_say, when, undo_when, say, undo_say, desc, icon, anchored, on_enter, on_leave, list/also, refund = TRUE, priority, quiet = FALSE, sfx, done_sfx)
	var/datum/ladder_stage/made = new
	made.name = name
	made.build = ladder_cost_spec(build, uses)
	made.undo = ladder_cost_spec(undo)
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
	made.sfx = sfx
	made.done_sfx = done_sfx
	return made

/// A dismantle branch (ladder_options(dismantle =)): the first stage can be taken apart with `tool` into `becomes` (`amount` of it);
/// when the holder's `when_ruined` proc answers TRUE (a broken frame) it comes apart into `ruined_becomes` (`ruined_amount`) instead.
/proc/ladder_dismantle(tool, becomes, amount, when_ruined, ruined_becomes, ruined_amount)
	return list(tool, becomes, amount, when_ruined, ruined_becomes, ruined_amount)

/// Graph-wide options (any element of cap_construction()'s list).
/datum/ladder_settings
	var/state_var
	var/state
	var/set_proc
	/// Branches leaving every stage.
	var/list/anywhere
	var/on_step
	var/on_start
	var/list/starts
	var/start
	var/stance
	var/category
	/// Prefix of the derived stage icons ("[sprite][position]").
	var/sprite
	/// The compartment the steps are done at (BAY_*, when the operations layer defines it).
	var/at
	/// Wait of every undo step, overriding the tool defaults.
	var/undo_delay
	/// list(tool quality, result type, amount): a branch out of the first stage that takes the holder apart.
	var/list/dismantle
	// The standard gating, applied to the capability (cap_gating()).
	var/behind = NONE
	var/blocked_by = NONE
	var/locked_by = NONE
	var/needs
	var/else_say
	var/works_broken = TRUE
	var/works_unpowered = TRUE
	var/log

/// `start`: the stage a new holder is in (default the first).
/// `state_var`: a holder var holding the stage name, as nameof(src.var) (default: the capability keeps it). `state` /
/// `store`: holder procs that derive and store the stage instead. `anywhere`: branches leaving every
/// stage. `on_step(actor, from, to)` after any step; `on_start(actor, held)` before a step's cost
/// (FALSE stops it). `starts`: stages a holder can be made in besides the first (a mapped
/// reinforced wall). `stance` and `category` apply to every step; the standard gating arguments
/// gate every step.
/// The holder is marked changed after every step (its appearance refreshes); `on_step` is for other work.
/// `sprite`: stage icons are derived as "[sprite][position]" for stages that name none. `at`: the compartment the
/// steps are done in. `undo_delay`: the wait of every undo. `dismantle` = list(tool, result_type, amount, ruined_proc, ruined_type, ruined_amount): a
/// branch out of the first stage that takes the holder apart into `result_type`; when the holder's `ruined_proc` answers TRUE (a broken
/// frame) it comes apart into `ruined_type` instead.
/proc/ladder_options(start, state_var, state, store, list/anywhere, on_step, on_start, list/starts, stance, category, sprite, at, undo_delay, list/dismantle, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/ladder_settings/made = new
	made.start = start
	made.starts = starts
	made.state_var = state_var
	made.state = state
	made.set_proc = store
	made.anywhere = anywhere
	made.on_step = on_step
	made.on_start = on_start
	made.stance = stance
	made.category = category
	made.sprite = sprite
	made.at = at
	made.undo_delay = undo_delay
	made.dismantle = dismantle
	// State gates are requirements in `needs` (req_set / req_clear), folded onto the gate bits (cap_gating()).
	var/list/gate = cap_fold_state_needs(needs)
	made.behind = gate[1]
	made.blocked_by = gate[2]
	made.locked_by = gate[3]
	made.needs = gate[4]
	made.else_say = else_say
	made.works_broken = works_broken
	made.works_unpowered = works_unpowered
	made.log = log
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
	/// Stage name -> the stage's index in the capability's declaration (stage_named()).
	var/list/stage_by_name
	/// Stage name -> effective anchoring (TRUE/FALSE), when any stage sets it.
	var/list/anchoring
	/// Whether any stage has an icon: the capability then draws every stage's.
	var/draws_icons = FALSE
	/// The construction capability this ladder belongs to (its data holds the stage).
	var/tmp/datum/capability/construction/cap
	/// A holder var holding the stage name instead of the capability's data (ladder_options(state_var = nameof(...))).
	var/state_var
	/// The stage a new holder is in, when not the first (ladder_options(start = ...)).
	var/start
	/// Holder procs deriving and storing the stage (ladder_options(state, store)).
	var/state_get
	var/state_set
	/// Holder procs run after any step and before a step's cost.
	var/after_proc
	var/start_proc
	/// Every step's stance and category, when set.
	var/stance
	var/category
	/// ladder_options(sprite, at, undo_delay, dismantle): see there.
	var/sprite
	var/at
	var/undo_delay
	var/list/dismantle
	/// Stages a holder can be made in besides the first.
	var/list/starts
	/// All steps, as shared singletons (owned).
	var/tmp/list/edges
	/// "[stage]" -> the indexes in `edges` of the steps leaving it.
	var/tmp/list/edges_by_state
	/// Indexes in `edges` of the steps leaving every stage.
	var/tmp/list/wildcard_edges
	/// Every step id, for uniqueness.
	var/tmp/list/edge_ids
	/// Problems found while reading the declaration (validate() reports them).
	var/tmp/list/row_errors

CAPABILITIES(/datum/construction_ladder)
	owns_many(nameof(edges))

/datum/construction_ladder/New(datum/capability/construction/owner, declared_on)
	..()
	rel_set(src, nameof(src.cap), owner)
	src.declared_on = declared_on
	id = "[declared_on]:construction"
	states = list()
	stage_by_name = list()
	edges_by_state = list()
	wildcard_edges = list()
	edge_ids = list()
	var/list/datum/ladder_stage/ladder = list()
	var/list/anywhere = list()
	// Options first: they may come anywhere in the declaration but shape every stage (the sprite prefix).
	for(var/datum/ladder_settings/options in owner.declaration)
		read_options(options, anywhere)
	for(var/i in 1 to length(owner.declaration))
		var/entry = owner.declaration[i]
		if(istype(entry, /datum/ladder_settings))
			continue
		else if(istype(entry, /datum/ladder_stage))
			var/datum/ladder_stage/stage = entry
			if(stage_by_name["[stage.name]"])
				LAZYADD(row_errors, "[id]: stage [stage.name] declared twice")
				continue
			ladder += stage
			states += stage.name
			stage_by_name["[stage.name]"] = i
			if(!stage.icon && sprite)
				stage.icon = "[sprite][length(states)]"
			if(stage.icon)
				draws_icons = TRUE
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
			add_edge(new /datum/interaction/capability/construction_step(owner = src, from = before.name, destination = stage.name,
				cost = stage.build, say = stage.say, step_needs = stage.needs, when = stage.when,
				step_priority = stage.priority, quiet = stage.quiet, sfx = stage.sfx, done_sfx = stage.done_sfx))
		if(before && stage.undo)
			var/list/undo_cost = stage.undo
			if(!isnull(undo_delay) && undo_cost)
				undo_cost = undo_cost.Copy()
				undo_cost[LCOST_DELAY] = undo_delay
			add_edge(new /datum/interaction/capability/construction_step(owner = src, from = stage.name, destination = before.name,
				cost = undo_cost, say = stage.undo_say, step_needs = stage.undo_needs, when = stage.undo_when,
				step_priority = stage.priority, quiet = stage.quiet, forward = FALSE,
				refund = stage.refund ? stage.build : null))
		for(var/datum/ladder_branch/extra as anything in stage.also)
			add_edge(branch_edge(stage.name, extra))
	for(var/datum/ladder_branch/extra as anything in anywhere)
		add_edge(branch_edge(LADDER_ANY, extra))
	if(length(dismantle) >= 2)
		var/datum/ladder_stage/first = ladder[1]
		// ALLOW(sys_dx_raw_delay): the literal is a list index (dismantle[1]), not a delay
		var/datum/ladder_branch/apart = branch(LADDER_DONE, cap_tool(quality = dismantle[1], delay = ladder_tool_delay(dismantle[1])),
			say = "take %T% apart", become = dismantle[2], amount = length(dismantle) >= 3 ? dismantle[3] : null)
		if(length(dismantle) >= 5)
			apart.ruined_when = dismantle[4]
			apart.ruined_become = length(dismantle) >= 6 && !isnull(dismantle[6]) ? list(dismantle[5], dismantle[6]) : list(dismantle[5])
		add_edge(branch_edge(first.name, apart))

/// Reads one ladder_options() value; its `anywhere` branches go into `anywhere`.
/datum/construction_ladder/proc/read_options(datum/ladder_settings/options, list/anywhere)
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
	if(options.stance)
		stance = options.stance
	if(options.category)
		category = options.category
	if(options.sprite)
		sprite = options.sprite
		draws_icons = TRUE
	if(options.at)
		at = options.at
	if(!isnull(options.undo_delay))
		undo_delay = options.undo_delay
	if(options.dismantle)
		dismantle = options.dismantle

/// The stage named `name`, or null.
/datum/construction_ladder/proc/stage_named(name)
	var/index = stage_by_name?["[name]"]
	return index ? cap.declaration[index] : null

/// Whether the capability's data keeps the stage (no holder var or procs do).
/datum/construction_ladder/proc/keeps_stage()
	return !state_get && !state_var && length(states)

/// The step a branch() declares.
/datum/construction_ladder/proc/branch_edge(from, datum/ladder_branch/extra)
	var/list/reaches = extra.next ? (islist(extra.to_stage) ? extra.to_stage : list(extra.to_stage)) : null
	return new /datum/interaction/capability/construction_step(owner = src, from = from,
		destination = extra.next ? null : extra.to_stage, cost = extra.cost, say = extra.say,
		step_needs = extra.needs, when = extra.when, on_enter = extra.on_enter, become = extra.become,
		next = extra.next, reaches = reaches, step_priority = extra.priority, quiet = extra.quiet,
		sfx = extra.sfx, done_sfx = extra.done_sfx, ruined_when = extra.ruined_when, ruined_become = extra.ruined_become)

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

/// Registers a step, gives it an id and makes it a real operation: keyed "step:<from>><to>:<tool or item>" (the id without
/// the ladder's own prefix), a structural ACT_USE op at the step's priority, so the gesture router ranks the ladder's
/// steps against the holder's other ops (the APC's hand step that takes its board out over its interface).
/datum/construction_ladder/proc/add_edge(datum/interaction/capability/construction_step/edge)
	var/step_key = "[edge.from_state]>[isnull(edge.to_state) ? "?" : edge.to_state]:[edge.tool || edge.item_key()]"
	var/base_id = "[id]:[step_key]"
	edge.id = base_id
	var/n = 1
	while(edge_ids[edge.id])
		n++
		edge.id = "[base_id]#[n]"
		step_key = "[copytext(step_key, 1, findtext(step_key, "#") || 0)]#[n]"
	edge_ids[edge.id] = TRUE
	op_attach(edge, "step:[step_key]", ACT_USE, edge.priority, OP_STRUCTURAL, at = edge.at)
	rel_add(src, nameof(src.edges), edge)
	var/index = length(edges)
	if(edge.from_state == LADDER_ANY)
		wildcard_edges += index
	else
		var/list/leaving = edges_by_state["[edge.from_state]"]
		if(!leaving)
			leaving = list()
			edges_by_state["[edge.from_state]"] = leaving
		leaving += index
	return edge

/// The holder's stage, or null when it isn't on this graph right now. Pure: reads only.
/datum/construction_ladder/proc/state_of(atom/target)
	if(state_get)
		return holder_call(target, state_get)
	if(state_var)
		return target.vars[state_var]
	var/datum/ladder_progress/progress = capability_data(target)?[cap.key]
	return progress?.stage || start || states[1]

/// Stores the stage on the holder.
/datum/construction_ladder/proc/set_state(atom/target, state)
	if(state == LADDER_DONE || QDELETED(target))
		return
	if(state_get)
		if(state_set)
			holder_call(target, state_set, state)
		return
	if(state_var)
		target.vars[state_var] = state // ALLOW(api): a ladder names the var holding its stage
	else
		var/datum/ladder_progress/progress = cap_data(target, cap)
		progress.stage = state

/// The steps leaving `state`.
/datum/construction_ladder/proc/edges_leaving(state)
	. = list()
	if(isnull(state))
		return
	for(var/index in edges_by_state["[state]"])
		. += edges[index]
	for(var/index in wildcard_edges)
		. += edges[index]

/// The steps leaving the holder's stage.
/datum/construction_ladder/proc/edges_for(atom/target)
	return edges_leaving(state_of(target))

/// The examine line for the holder's stage, or null.
/datum/construction_ladder/proc/node_desc(atom/target)
	var/datum/ladder_stage/stage = stage_named(state_of(target))
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
	for(var/proc_ref in list(state_get, state_set, after_proc, start_proc))
		if(proc_ref && !ladder_holder_has_proc(declared_on, proc_ref))
			. += "[id]: [declared_on] has no proc [proc_ref]"
	for(var/name in stage_by_name)
		var/datum/ladder_stage/stage = stage_named(name)
		for(var/proc_ref in list(stage.on_enter, stage.on_leave, stage.when, stage.undo_when))
			if(proc_ref && !ladder_holder_has_proc(declared_on, proc_ref))
				. += "[id]: stage [name]: [declared_on] has no proc [proc_ref]"
	for(var/datum/interaction/capability/construction_step/edge as anything in edges)
		if(!edge.phrase)
			. += "[edge.id]: no phrase"
		if(!edge.tool && !edge.item_type && !edge.by_hand)
			. += "[edge.id]: takes nothing"
		if(!isnull(edge.to_state) && edge.to_state != LADDER_DONE && !stage_named(edge.to_state))
			. += "[edge.id]: leads to unknown stage [edge.to_state]"
		for(var/next in edge.reaches)
			if(next != LADDER_DONE && !stage_named(next))
				. += "[edge.id]: may lead to unknown stage [next]"
		if(isnull(edge.to_state) && !edge.next_proc)
			. += "[edge.id]: leads nowhere"
		if(edge.become && edge.to_state != LADDER_DONE)
			. += "[edge.id]: replaces the holder but doesn't leave the graph"
		var/datum/predicate/pred = edge.predicate()
		if(pred?.errors)
			. += "[edge.id]: requirements don't compile: [jointext(pred.errors, "; ")]"
		for(var/proc_ref in edge.holder_procs())
			if(!ladder_holder_has_proc(declared_on, proc_ref))
				. += "[edge.id]: [declared_on] has no proc [proc_ref]"
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
				if(next == LADDER_DONE || !stage_named(next) || reached["[next]"])
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
	/// gating reaches every step through cap_apply_gating()).
	var/list/step_needs
	/// Holder procs: whether the step is offered, the step's own hook.
	var/when_proc
	var/step_hook
	/// Done with an empty hand: meant only when the actor holds nothing.
	var/by_hand = FALSE
	/// Sound sets when the step starts and when it is done.
	var/start_sfx
	var/done_sfx
	/// What undoing this step gives back (the build it undoes): LADDER_ITEM_USE / _DELETE / _INSERT,
	/// the item type (or list of types), and the stack units.
	var/refund_use = LADDER_ITEM_KEEP
	var/refund_type
	var/refund_amount = 0
	/// list(type, args...) the holder is replaced by.
	var/list/become
	/// A holder proc saying the holder is ruined; the step then replaces it by `ruined_become` instead.
	var/ruined_when
	var/list/ruined_become
	/// No generated messages (the hook says it).
	var/quiet = FALSE

/datum/interaction/capability/construction_step/New(datum/construction_ladder/owner, from, destination, list/cost, say, list/step_needs, when, on_enter, list/become, next, list/reaches, step_priority, quiet = FALSE, forward = TRUE, sfx, done_sfx, list/refund, ruined_when, list/ruined_become)
	rel_set(src, nameof(src.graph), owner)
	from_state = from
	to_state = destination
	src.forward = forward
	src.become = become
	src.ruined_when = ruined_when
	src.ruined_become = ruined_become
	src.quiet = quiet
	src.reaches = reaches
	next_proc = next
	when_proc = when
	step_hook = on_enter
	start_sfx = sfx
	src.done_sfx = done_sfx
	tags = list(INTERACTION_TAG_CONSTRUCTION)
	if(become && isnull(to_state))
		to_state = LADDER_DONE
	if(!isnull(step_priority))
		priority = step_priority
	if(owner.stance)
		stance = owner.stance
	if(owner.category)
		category = owner.category
	src.step_needs = step_needs
	at = owner.at
	if(!read_cost(cost))
		LAZYADD(owner.row_errors, "[owner.id]: the step from [from] to [destination] has no cost (a cap_tool/cap_insert/cap_use_on/cap_hand entry)")
	else if(cost[LCOST_HANDLER])
		LAZYADD(owner.row_errors, "[owner.id]: the cost of the step from [from] to [destination] has a handler; a ladder step's cost takes none")
	if(refund)
		read_refund(refund)
	phrase = say || generated_phrase()
	name = capitalize(next_text())
	..()

/// Copies what a cost spec (ladder_cost_spec()) takes onto the step. FALSE when it is no cost.
/datum/interaction/capability/construction_step/proc/read_cost(list/cost)
	var/kind = cost?[LCOST_KIND]
	if(!kind)
		return FALSE
	switch(kind)
		if(LADDER_COST_TOOL)
			tool = cost[LCOST_TOOL]
			tool_amount = cost[LCOST_FUEL]
			tool_volume = cost[LCOST_VOLUME]
		if(LADDER_COST_HAND)
			by_hand = TRUE
			offered_when = list(REQ_EMPTY_HANDED)
		else
			item_type = cost[LCOST_ITEM]
			item_use = ladder_item_use(kind, item_type)
			if(item_use == LADDER_ITEM_USE)
				item_amount = cost[LCOST_USES]
			// An item step is meant only with that kind of item in hand, as a tool step is with the tool.
			held_type = item_type
	duration = cost[LCOST_DELAY]
	item_name = cost[LCOST_NAME]
	var/list/more = cost[LCOST_NEEDS]
	if(length(more))
		step_needs = length(step_needs) ? step_needs + more : more
	return TRUE

/// Reads what undoing gives back from the build (a cost spec) it undoes.
/datum/interaction/capability/construction_step/proc/read_refund(list/build)
	refund_use = ladder_item_use(build[LCOST_KIND], build[LCOST_ITEM])
	if(refund_use == LADDER_ITEM_KEEP)
		return
	refund_type = build[LCOST_ITEM]
	refund_amount = build[LCOST_USES]

/// LADDER_COST_* for a cost entry: its kind, and a checked item that `uses` makes used up.
/proc/ladder_entry_kind(datum/interaction/capability/E, uses)
	if(E.tool)
		return LADDER_COST_TOOL
	if(E.category == INTERACTION_CAT_INSERT)
		return LADDER_COST_INSERT
	if(E.held_type)
		return uses ? LADDER_COST_USE : LADDER_COST_HOLD
	return LADDER_COST_HAND

/// LADDER_ITEM_* for an item cost of `kind` on `item_type`.
/proc/ladder_item_use(kind, item_type)
	switch(kind)
		if(LADDER_COST_INSERT)
			return LADDER_ITEM_INSERT
		if(LADDER_COST_USE)
			var/first = islist(item_type) ? item_type[1] : item_type
			return ispath(first, /obj/item/stack) ? LADDER_ITEM_USE : LADDER_ITEM_DELETE
	return LADDER_ITEM_KEEP

/// Every holder proc this step names, for validate().
/datum/interaction/capability/construction_step/proc/holder_procs()
	. = list()
	for(var/proc_ref in list(next_proc, when_proc, step_hook, ruined_when))
		if(proc_ref)
			. += proc_ref
	for(var/list/need as anything in step_needs)
		. += need[1]

// ---- Generated text ----

/// The phrase the verb table gives this step's cost and direction.
/datum/interaction/capability/construction_step/proc/generated_phrase()
	if(tool)
		return ladder_tool_phrase(tool, forward)
	if(by_hand)
		return refund_type ? "take [refund_noun()] out of %T%" : "work on %T% by hand"
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
	var/obj/item/path = islist(refund_type) ? refund_type[1] : refund_type
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
	if(caps_suspended(target))
		return FALSE
	var/state = graph.state_of(target)
	if(isnull(state))
		return FALSE
	if(from_state != LADDER_ANY && "[state]" != "[from_state]")
		return FALSE
	return when_proc ? holder_call(target, when_proc) : TRUE

/// Steps are instances: key the shared predicates by step id.
/datum/interaction/capability/construction_step/predicate_key()
	return "ladder:[id]"

/datum/interaction/capability/construction_step/why_not(mob/actor, atom/target, obj/item/held)
	// Re-checked after the wait: the holder may have moved on to another stage.
	if(!applies_to(target))
		return "it has changed"
	. = ..()
	if(.)
		return
	for(var/list/need as anything in step_needs)
		var/answer = holder_call(target, need[1], actor, held)
		if(istext(answer))
			return answer
		if(!answer)
			return need[2] || "you can't do that right now"
	if(item_type)
		return item_failure(held)

/datum/interaction/capability/construction_step/duration_for(mob/actor, atom/target, obj/item/held)
#ifdef UNIT_TESTS
	if(GLOB.dq_ladder_instant)
		return 0
#endif
	return ..()

/datum/interaction/capability/construction_step/pay_cost(mob/actor, atom/target, obj/item/held)
	if(graph.start_proc)
		// FALSE (not null) stops the step before its cost: a shock, a refusal only known now.
		var/started = holder_call(target, graph.start_proc, actor, held)
		if(!isnull(started) && !started)
			return FALSE
	if(start_sfx)
		play_sfx(target, start_sfx)
	return ..()

/// Why `held` won't do for this step's item, or null.
/datum/interaction/capability/construction_step/proc/item_failure(obj/item/held)
	if(!held || !item_matches(held))
		return "needs [item_text()]"
	if(item_amount && istype(held, /obj/item/stack))
		var/obj/item/stack/stack = held
		if(stack.get_amount() < item_amount)
			return "needs [item_text()]"
	return null

/// Whether `held` is the kind of item this step takes.
/datum/interaction/capability/construction_step/proc/item_matches(obj/item/held)
	if(islist(item_type))
		for(var/path in item_type)
			if(istype(held, path))
				return TRUE
		return FALSE
	return istype(held, item_type)

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
		return holder_call(target, next_proc, state)
	return to_state

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
/// Unit tests set this to run construction steps with no wait.
GLOBAL_VAR_INIT(dq_ladder_instant, FALSE)
#endif

/**
 * Runs the step on `target` after its cost is paid: the item, the stage stored, anchoring, what
 * an undo gives back, the stages' on_leave/on_enter and the step's own hook, the replacement, the
 * message and sound, then the graph's on_step. The holder is marked changed by the dispatch, so its
 * stage icon is redrawn through draw(look).
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
			return refuse(actor, "You need [item_text()] for this.")
	if(item_type && item_use == LADDER_ITEM_INSERT && held)
		actor.drop_from_inventory(held)
		held.forceMove(target)
	var/datum/ladder_stage/left = graph.stage_named(before)
	var/datum/ladder_stage/entered = graph.stage_named(after)
	// on_leave runs while the holder is still in the stage it leaves; FALSE (not null) refuses.
	if(left?.on_leave && left != entered)
		var/leaving = holder_call(target, left.on_leave, actor, held, after)
		if(QDELETED(target) || (!isnull(leaving) && !leaving))
			return FALSE
	var/was_anchored
	if(ismovable(target))
		var/atom/movable/movable = target
		was_anchored = movable.anchored
	graph.set_state(target, after)
	apply_anchoring(target, after)
	if(refund_use != LADDER_ITEM_KEEP)
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
		var/result = holder_call(target, hook, actor, held, before)
		if(!isnull(result) && !result)
			if(!QDELETED(target))
				graph.set_state(target, before)
				if(!isnull(was_anchored))
					var/atom/movable/movable = target
					movable.set_anchored(was_anchored)
			return FALSE
	if(item_type && item_use == LADDER_ITEM_DELETE && !QDELETED(held))
		consume(held, actor)
	var/list/lines = done_lines()
	if(lines)
		act_message(actor, target, msg_span(lines[1], "notice"), msg_span(lines[2], "notice"), item = held)
	if(done_sfx)
		play_sfx(where || target, done_sfx)
	if(become && !QDELETED(target) && ismovable(target))
		var/list/replace_args = list(target) + ((ruined_when && ruined_become && holder_call(target, ruined_when)) ? ruined_become : become)
		replace_with(arglist(replace_args))
	// A turf that changed into something else (a cut-open wall) no longer has the graph's procs.
	if(graph.after_proc && !QDELETED(target) && hascall(target, graph.after_proc))
		holder_call(target, graph.after_proc, actor, before, after)
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
	var/path = islist(refund_type) ? refund_type[1] : refund_type
	if(!path)
		return
	switch(refund_use)
		if(LADDER_ITEM_USE)
			new path(where, max(refund_amount, 1))
		if(LADDER_ITEM_DELETE)
			new path(where)
		if(LADDER_ITEM_INSERT)
			var/obj/item/part
			for(var/part_type in (islist(refund_type) ? refund_type : list(refund_type)))
				part = locate_within(target, part_type)
				if(part)
					break
			part?.forceMove(where)

/// Construction steps run through the central dispatch (fingerprint, log, changed()) like every entry, as ops: the
/// holder's before_op reactions (by the step's key, or the construction capability's type) may stop one, and its
/// after_op reactions follow one that committed.
/datum/interaction/capability/construction_step/run_effect(mob/actor, atom/target, obj/item/held)
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
	. = dispatch_call(ctx, target, GLOBAL_PROC_REF(traverse_ladder_step), list("user" = actor, "held" = held, "step" = src), name, log)
	if(isnull(.))
		. = TRUE
	if(octx)
		if(dispatch_succeeded(.))
			op_after(octx)
		octx.release()

/// A step pays its cost through the tool pipeline (its start lines, the stage it leaves re-checked when the wait ends),
/// not the op wait.
/datum/interaction/capability/construction_step/op_waits()
	return FALSE

/// The handler every construction step dispatches to.
/proc/traverse_ladder_step(atom/holder, mob/user, obj/item/held, datum/interaction/capability/construction_step/step)
	return step.traverse(holder, user, held)

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
	for(var/text in ladder_step_lines(target, graph))
		lines += span_notice("Next: [text]")
	return length(lines) ? lines : null

/// "wrench it into place (needs a wrench)" per step the holder offers now, unstyled (description panels).
/proc/ladder_step_lines(atom/target, datum/construction_ladder/graph)
	. = list()
	graph ||= ladder_of(target)
	if(!graph)
		return
	for(var/datum/interaction/capability/construction_step/edge as anything in graph.edges_for(target))
		if(!edge.applies_to(target))
			continue
		var/needs = edge.requirement_text()
		. += "[edge.next_text()][needs ? " ([needs])" : ""]"
