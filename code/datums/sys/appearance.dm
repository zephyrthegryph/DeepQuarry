// Appearance keyed on declared state: the runtime (code/__defines/sys_appearance.dm,
// doc/rewrite/systems.md section 1).
//
// Declarations live in the type's /datum/lifecycle_decls table (DECLARE_APPEARANCE layers,
// APPEARANCE_TEMPLATE, APPEARANCE_LEVEL, APPEARANCE_EMISSIVE, APPEARANCE_SLOT, APPEARANCE_WATCH).
// finish_appearance() validates them against the first instance, resolves which names are procs and
// computes the type's appearance watch mask from the channels of the declared fields they read.
//
// Drawing: appearance_key() reads the instance's state into one key (the rendered icon_state and
// overlay states); the combined result is built once per (type, key) in the `decl_appearance` shared
// cache and applied by apply_appearance(), which swaps out only the overlays the previous key added.
// The base /atom/update_icon() calls it, so a declared type needs no update_icon() override.
//
// Refresh: om_dispatch_change() (code/datums/om/entity.dm) queues an atom whose raised channels hit
// its type's watch mask; the presentation lane (scheduler run_lane()) drains the queue, calling
// update_icon() once per queued atom, so any number of field changes in a frame cost one refresh.

/datum/lifecycle_decls
	/// DECLARE_APPEARANCE layers: state name (APPEARANCE_ANY for a static layer) -> rows (key -> row).
	var/list/appearance_layers
	/// APPEARANCE_TEMPLATE: the raw template until finish(), then its parsed parts.
	var/appearance_template
	/// APPEARANCE_LEVEL: value name -> list(steps, format); the format is parsed in finish().
	var/list/appearance_levels
	/// APPEARANCE_EMISSIVE: field name -> rows ("value" -> icon_state).
	var/list/appearance_emissives
	/// APPEARANCE_SLOT: slot id -> icon_state.
	var/list/appearance_slots
	/// APPEARANCE_WATCH: names of the declared fields a procedural update_icon() reads.
	var/list/appearance_watch
	/// DECLARE_APPEARANCE_PROC: the provider proc, and the fields/channels it reads.
	var/appearance_proc
	var/list/appearance_proc_fields
	/// Names read by call() (procs) rather than from vars; name -> TRUE.
	var/list/appearance_procs
	/// Channels whose raise refreshes the appearance (fields read, CHANGE_CONTENTS for slots).
	var/appearance_mask = 0
	/// TRUE when a declaration draws something (anything but APPEARANCE_WATCH).
	var/appearance_draws = FALSE

/datum/lifecycle_decls/proc/set_appearance(state_var, list/rows)
	LAZYSET(appearance_layers, state_var || APPEARANCE_ANY, rows)

/datum/lifecycle_decls/proc/set_appearance_template(template)
	appearance_template = template

/datum/lifecycle_decls/proc/add_appearance_level(value_name, steps, format)
	LAZYSET(appearance_levels, value_name, list(steps, format))

/datum/lifecycle_decls/proc/add_appearance_emissive(field, list/rows)
	LAZYSET(appearance_emissives, field, rows)

/datum/lifecycle_decls/proc/add_appearance_slot(slot_id, state)
	LAZYSET(appearance_slots, slot_id, state)

/datum/lifecycle_decls/proc/add_appearance_watch(list/fields)
	for(var/name in fields)
		LAZYOR(appearance_watch, name)

/datum/lifecycle_decls/proc/set_appearance_proc(proc_ref, list/fields)
	appearance_proc = proc_ref
	appearance_proc_fields = fields

/datum/lifecycle_decls/proc/clear_appearance()
	appearance_proc = null
	appearance_proc_fields = null
	appearance_layers = null
	appearance_template = null
	appearance_levels = null
	appearance_emissives = null
	appearance_slots = null

/datum/lifecycle_decls/proc/drop_appearance()
	clear_appearance()
	appearance_watch = null
	appearance_procs = null
	appearance_mask = 0
	appearance_draws = FALSE

// ---- validation (once per type) ----

/// Resolves `name` against the first instance D: a var reads from vars, a proc is called. Records a
/// proc in appearance_procs. FALSE (with a stack trace naming `what`) when D has neither.
/datum/lifecycle_decls/proc/appearance_name_ok(datum/D, name, what)
	if(name in D.vars)
		return TRUE
	if(hascall(D, name))
		LAZYSET(appearance_procs, name, TRUE)
		return TRUE
	stack_trace("[what]([owner_type], \"[name]\"): no such var or proc; dropped")
	return FALSE

/// Parses a template into parts: text, or list(APPEARANCE_PART_READ, name), or
/// list(APPEARANCE_PART_TERNARY, name, if_true, if_false) where a branch is text or list(var name).
/// [initial(x)] becomes text. Null (with a stack trace) when a name does not resolve.
/datum/lifecycle_decls/proc/parse_appearance_template(datum/D, template, what)
	var/list/parts = list()
	var/pos = 1
	var/len = length(template)
	while(pos <= len)
		var/open = findtext(template, "{", pos)
		if(!open)
			parts += copytext(template, pos)
			break
		if(open > pos)
			parts += copytext(template, pos, open)
		var/close = findtext(template, "}", open + 1)
		if(!close)
			stack_trace("[what]([owner_type], \"[template]\"): unclosed {; dropped")
			return null
		var/token = trimtext(copytext(template, open + 1, close))
		pos = close + 1
		if(findtext(token, "initial(") == 1 && copytext(token, -1) == ")")
			var/var_name = trimtext(copytext(token, 9, -1))
			if(!(var_name in D.vars))
				stack_trace("[what]([owner_type], \"[template]\"): initial([var_name]) is not a var; dropped")
				return null
			parts += "[initial(D.vars[var_name])]"
			continue
		var/question = findtext(token, "?")
		if(question)
			var/name = trimtext(copytext(token, 1, question))
			var/colon = findtext(token, ":", question + 1)
			if(!colon)
				stack_trace("[what]([owner_type], \"[template]\"): {[token]} needs {name?A:B}; dropped")
				return null
			var/list/branches = list(copytext(token, question + 1, colon), copytext(token, colon + 1))
			for(var/i in 1 to 2)
				var/branch = branches[i]
				if(copytext(branch, 1, 2) == "@")
					var/var_name = copytext(branch, 2)
					if(!appearance_name_ok(D, var_name, what))
						return null
					branches[i] = list(var_name)
			if(!appearance_name_ok(D, name, what))
				return null
			parts += list(list(APPEARANCE_PART_TERNARY, name, branches[1], branches[2]))
			continue
		if(!appearance_name_ok(D, token, what))
			return null
		parts += list(list(APPEARANCE_PART_READ, token))
	// Adjacent literals (an initial() next to text) are joined.
	var/list/joined = list()
	for(var/part in parts)
		if(istext(part) && length(joined) && istext(joined[length(joined)]))
			joined[length(joined)] = joined[length(joined)] + part
		else
			joined += list(part)
	return joined

/// Called by /datum/lifecycle_decls/finish(): validates the appearance declarations against D and
/// computes appearance_mask.
/datum/lifecycle_decls/proc/finish_appearance(datum/D)
	if(!isatom(D))
		if(appearance_proc || appearance_layers || appearance_template || appearance_levels || appearance_emissives || appearance_slots || appearance_watch)
			stack_trace("appearance declarations on [owner_type]: only atoms have an appearance; dropped")
		drop_appearance()
		return
	var/list/read_names = list()
	for(var/layer_var in appearance_layers?.Copy())
		if(layer_var == APPEARANCE_ANY)
			continue
		if(appearance_name_ok(D, layer_var, "DECLARE_APPEARANCE"))
			read_names |= layer_var
		else
			appearance_layers -= layer_var
	if(!length(appearance_layers))
		appearance_layers = null
	if(istext(appearance_template))
		appearance_template = parse_appearance_template(D, appearance_template, "APPEARANCE_TEMPLATE")
	for(var/list/part in appearance_template)
		read_names |= part[2]
	for(var/value_name in appearance_levels?.Copy())
		var/list/level = appearance_levels[value_name]
		var/list/format = istext(level[2]) ? parse_appearance_template(D, level[2], "APPEARANCE_LEVEL") : level[2]
		if(!appearance_name_ok(D, value_name, "APPEARANCE_LEVEL") || !format || !isnum(level[1]) || level[1] < 1)
			appearance_levels -= value_name
			continue
		appearance_levels[value_name] = list(level[1], format)
		read_names |= value_name
		for(var/list/part in format)
			read_names |= part[2]
	if(!length(appearance_levels))
		appearance_levels = null
	for(var/field in appearance_emissives?.Copy())
		if(appearance_name_ok(D, field, "APPEARANCE_EMISSIVE"))
			read_names |= field
		else
			appearance_emissives -= field
	if(!length(appearance_emissives))
		appearance_emissives = null
	appearance_draws = !!(appearance_proc || appearance_layers || appearance_template || appearance_levels || appearance_emissives || appearance_slots)
	var/list/fields = definition_registry().fields_of(owner_type)
	appearance_mask = 0
	for(var/entry in appearance_proc_fields)
		if(isnum(entry))
			appearance_mask |= entry
		else if(fields[entry])
			appearance_mask |= fields[entry]
		else
			stack_trace("DECLARE_APPEARANCE_PROC([owner_type], \"[entry]\"): not a declared field with a channel; ignored")
	for(var/name in read_names)
		appearance_mask |= fields[name]
	for(var/name in appearance_watch?.Copy())
		if(!fields[name])
			stack_trace("APPEARANCE_WATCH([owner_type], \"[name]\"): not a declared field with a channel; dropped")
			appearance_watch -= name
			continue
		appearance_mask |= fields[name]
	if(!length(appearance_watch))
		appearance_watch = null
	if(appearance_slots)
		appearance_mask |= CHANGE_CONTENTS

// ---- drawing ----

/atom
	/// The declared appearance key applied last (its overlays are the ones to swap out).
	var/tmp/decl_appearance_key
	/// What the DECLARE_APPEARANCE_PROC provider returned last (the overlays the runtime owns for it).
	var/tmp/list/appearance_proc_overlays
	/// TRUE while queued for a refresh on the presentation lane (appearance_queue()), or
	/// APPEARANCE_PENDING_LATENT while a latent movable waits to materialize before it joins.
	var/tmp/appearance_queued = FALSE

/// The value of declared name `name` on A: a proc's result or a var.
/datum/lifecycle_decls/proc/appearance_value(atom/A, name)
	if(appearance_procs?[name])
		return call(A, name)()
	return A.vars[name]

/// Renders parsed template parts for A.
/datum/lifecycle_decls/proc/render_appearance_template(atom/A, list/parts)
	. = ""
	for(var/part in parts)
		if(istext(part))
			. += part
			continue
		var/list/P = part
		var/value = appearance_value(A, P[2])
		if(P[1] == APPEARANCE_PART_TERNARY)
			value = value ? P[3] : P[4]
			if(islist(value))
				var/list/branch = value
				value = appearance_value(A, branch[1])
		. += "[value]"

/// A's combined appearance key, five sections joined by newlines: the template's icon_state; each
/// layer's row key ("[value]", or the "*" row, or nothing); the level overlay states; the emissive
/// states; the slot states. Everything the built result depends on is in it.
/datum/lifecycle_decls/proc/appearance_key(atom/A)
	var/key = appearance_template ? render_appearance_template(A, appearance_template) : ""
	key += "\n"
	for(var/layer_var in appearance_layers)
		var/list/rows = appearance_layers[layer_var]
		var/row_key = APPEARANCE_ANY
		if(layer_var != APPEARANCE_ANY)
			row_key = "[appearance_value(A, layer_var)]"
			if(!rows[row_key])
				row_key = APPEARANCE_ANY
		if(!rows[row_key])
			row_key = ""
		key += "[row_key]|"
	key += "\n"
	for(var/value_name in appearance_levels)
		var/value = appearance_value(A, value_name)
		if(isnull(value))
			key += "|"
			continue
		var/list/level = appearance_levels[value_name]
		var/steps = level[1]
		var/step = clamp(round(value * steps / 100, 1), 0, steps)
		var/state = render_appearance_template(A, level[2])
		state = replacetext(replacetext(state, "%d", "[step]"), "%p", "[round(step * 100 / steps, 1)]")
		key += "[state]|"
	key += "\n"
	for(var/field in appearance_emissives)
		var/list/rows = appearance_emissives[field]
		key += "[rows["[appearance_value(A, field)]"] || rows[APPEARANCE_ANY]]|"
	key += "\n"
	for(var/slot_id in appearance_slots)
		key += "[A.slot_item_real(slot_id) ? appearance_slots[slot_id] : ""]|"
	return key

/// The built appearance for a combined key, shared by every instance: list(icon_state, color,
/// overlay list, icon). One `decl_appearance` shared cache entry per (type, key), interned: types
/// whose declarations build the same overlays share one list. Read-only (test builds runtime on a
/// write).
/datum/lifecycle_decls/proc/appearance_row(atom/A, key)
	return CACHED_KEY(decl_appearance, "[owner_type]|[key]", src, key)

/// Builder for decl_appearance. The table's owner type is the instance's type (lifecycle_decls_of()
/// is keyed by it), so its initial icon is the type's.
/proc/build_decl_appearance(datum/lifecycle_decls/decls, key)
	var/atom/owner = decls.owner_type
	var/base_icon = initial(owner.icon)
	var/list/sections = splittext(key, "\n")
	var/state = length(sections[1]) ? sections[1] : null
	var/tint
	var/row_icon
	var/list/images
	var/list/row_keys = splittext(sections[2], "|")
	var/i = 0
	for(var/layer_var in decls.appearance_layers)
		i++
		var/row_key = row_keys[i]
		if(!row_key)
			continue
		var/list/row = decls.appearance_layers[layer_var][row_key]
		if(row[APPEARANCE_ICON])
			row_icon = row[APPEARANCE_ICON]
		if(!isnull(row[APPEARANCE_ICON_STATE]))
			state = row[APPEARANCE_ICON_STATE]
		if(!isnull(row[APPEARANCE_COLOR]))
			tint = row[APPEARANCE_COLOR]
		for(var/overlay in row[APPEARANCE_OVERLAYS])
			if(istext(overlay))
				LAZYADD(images, image(row[APPEARANCE_ICON] || base_icon, overlay))
			else
				LAZYADD(images, overlay)
	var/overlay_icon = row_icon || base_icon
	for(var/overlay_state in splittext(sections[3], "|"))
		if(overlay_state)
			LAZYADD(images, image(overlay_icon, overlay_state))
	for(var/overlay_state in splittext(sections[4], "|"))
		if(overlay_state)
			LAZYADD(images, emissive_appearance(overlay_icon, overlay_state))
	for(var/overlay_state in splittext(sections[5], "|"))
		if(overlay_state)
			LAZYADD(images, image(overlay_icon, overlay_state))
	return list(state, tint, images, row_icon)

DECLARE_SHARED_CACHE_EX(decl_appearance, GLOBAL_PROC_REF(build_decl_appearance), SC_NEVER, 0, SC_INTERN)

/// Applies the appearance for A's current state: the keyed declarations, then the provider.
/datum/lifecycle_decls/proc/apply_appearance(atom/A)
	apply_appearance_keyed(A)
	if(appearance_proc)
		apply_appearance_proc(A)

/// Runs the provider and swaps its overlays: the ones it returned last time out, the new ones in.
/datum/lifecycle_decls/proc/apply_appearance_proc(atom/A)
	var/result = call(A, appearance_proc)()
	var/list/overlays
	if(islist(result))
		var/list/returned = result
		for(var/overlay in returned)
			if(!isnull(overlay))
				LAZYADD(overlays, overlay)
	else if(!isnull(result))
		overlays = list(result)
	if(A.appearance_proc_overlays)
		A.cut_overlay(A.appearance_proc_overlays)
	A.appearance_proc_overlays = overlays
	if(overlays)
		A.add_overlay(overlays)

/// Applies the keyed declarations for A's state; swaps out the overlays the previous key added.
/datum/lifecycle_decls/proc/apply_appearance_keyed(atom/A)
	var/key = appearance_key(A)
	if(key == A.decl_appearance_key)
		return
	var/list/row = appearance_row(A, key)
	if(A.decl_appearance_key)
		var/list/old = appearance_row(A, A.decl_appearance_key)
		if(old[3])
			A.cut_overlay(old[3])
	A.decl_appearance_key = key
	if(row[4])
		A.icon = row[4]
	if(!isnull(row[1]))
		A.icon_state = row[1]
	if(!isnull(row[2]))
		A.color = row[2]
	if(row[3])
		A.add_overlay(row[3])

/// Init (lifecycle_decls_init()): draws the declared appearance and starts listening on the watch
/// mask, so a declared field's setter refreshes it from then on.
/// A keyed declaration that reads only vars is drawn right here; one that calls a reader proc may
/// depend on what the subtype's Initialize() sets up after `. = ..()`, so it is queued and drawn on
/// the next presentation pass instead. A provider first runs on the type's own first update_icon()
/// (its Initialize() draws, as before).
/datum/lifecycle_decls/proc/init_appearance(atom/A)
	if(appearance_mask)
		A.om_listen |= appearance_mask
	if(!appearance_draws)
		return
	if(appearance_procs)
		appearance_queue(A)
		return
	apply_appearance_keyed(A)

/// Re-applies A's declared appearance. The base /atom/update_icon() calls it, so a declared type only
/// needs update_icon() (or ..() from a procedural override).
/atom/proc/decl_appearance_apply()
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(src)
	if(decls?.appearance_draws)
		decls.apply_appearance(src)

/// The default DECLARE_APPEARANCE_PROC provider: no overlays. Types override it and declare it.
/atom/proc/appearance_overlays()
	return null

// ---- automatic refresh ----

/// Atoms waiting for update_icon() on the presentation lane, each once (appearance_queued).
GLOBAL_LIST_EMPTY(appearance_queue)

/// The appearance watch mask of E's type (0 for a datum, or a type that declares none).
/proc/appearance_mask_of(datum/E)
	if(!isatom(E))
		return 0
	var/datum/lifecycle_decls/decls = lifecycle_decls_of(E)
	return decls ? decls.appearance_mask : 0

/// Queues A for one update_icon() on the next presentation lane pass (om_dispatch_change() calls it
/// when a raised channel is in the watch mask).
/proc/appearance_queue(atom/A)
	if(A.appearance_queued || QDELING(A))
		return
	// A latent movable (a sandboxed Initialize(), a collapsed ledger's contents) is not in the live
	// world: the queue would hold it and draw it for nobody. It joins when it materializes.
	if(ismovable(A) && !(A.flags & ATOM_MATERIALIZED))
		A.appearance_queued = APPEARANCE_PENDING_LATENT
		return
	A.appearance_queued = TRUE
	GLOB.appearance_queue += A

/// Runs the queued refreshes within the lane budget. TRUE when the queue is empty. Refreshes raised
/// by a refresh join the same pass.
/proc/appearance_drain(datum/om/scheduler/sched)
	// The refresh engine shares the presentation lane (code/datums/capabilities/refresh.dm).
	if(!refresh_drain(sched))
		return FALSE
	refresh_sweep_step()
	var/list/Q = GLOB.appearance_queue
	if(!length(Q))
		return TRUE
	var/i = 0
	while(i < length(Q))
		i++
		var/atom/A = Q[i]
		A.appearance_queued = FALSE
		if(QDELETED(A))
			continue
		try
			A.update_icon()
		catch(var/exception/e)
			sched?.report_caught(e, "appearance refresh of [A.type]: [e] ([e.file]:[e.line])")
		if(sched?.out_of_budget() && i < length(Q))
			Q.Cut(1, i + 1)
			return FALSE
	Q.Cut()
	return TRUE

/// Runs every queued refresh now, ignoring the budget (unit tests, admin tools).
/proc/appearance_flush()
	refresh_flush()
	while(length(GLOB.appearance_queue))
		appearance_drain(null)
