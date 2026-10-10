// Presentation entries and outputs (doc/rewrite/final_api.html, section 13 "Look, UI, verbs, prompts"; section 11 "Defining one";
// doc/rewrite/engine_contracts.md "Phase 2 additions").
//
// What a CAPABILITIES list can say about how its holder looks, reads and talks to a window:
//
//   look_layer(name, when = cond)         a layer of the holder's look while `cond` holds (a capability state key, a stat, a tracked var,
//                                         cond_not/cond_all/cond_any, a PROC_REF of the holder): look.part(name)
//   examine_line(text | MSG | PROC_REF, when = cond)
//                                         a line of the holder's examine text while `cond` holds. A text or a /datum/msg type is the
//                                         line itself; a PROC_REF is a proc of the holder, x(datum/act/A), returning a text or a list
//   interface(window, title =, ...)       (code/engine/parts/part.dm) the window the holder opens: ui_interface() and ui_title() read it
//
// and what a CAPABILITY_TYPE datum can contribute when it overrides one of the output procs below (each takes the pooled eval context, A.holder
// and A.cap set):
//
//   on_draw(A, look)                      draws into the holder's look (after the capability's look_layer entries, before the type's own draw())
//   on_examine(A, list/lines)             adds examine lines
//   on_ui_data(A, list/data)              adds window data, merged by the engine under data["caps"][<capability name>]
//
// The legacy look builder, examine and tgui paths are the carriers: /atom/draw() calls present_draw(), examine_lines() calls present_examine(),
// and tgui_data() merges present_ui_data() and the holder's own ui_data(A). What a draw or a window reads is found by the same read analysis
// that finds the reads of a type's own draw() and tgui_data() (tools/analyze, derived_reads); a capability output reads state through its
// accessors (cover_open(holder), ...), which publish a key when they change, so a redraw or a window refresh follows with nothing called by hand.
// A window's buttons are ops with a ui_act() binding: tgui_act() routes a button to its op first (code/engine/parts/inputs.dm, op_ui_act()).

/// The entry kinds of the presentation layer: look_layer and examine_line are code/engine/present/look.dm and examine.dm.
/// The kind interface() makes (code/engine/parts/part.dm).
#define ENTRY_INTERFACE "interface"

/// The output hooks a capability definition overrides (its `output_hooks` bits): the presentation skips a capability without them.
#define OUTPUT_HOOK_DRAW (1<<0)
#define OUTPUT_HOOK_EXAMINE (1<<1)
#define OUTPUT_HOOK_UI (1<<2)

/datum/capability
	/// OUTPUT_HOOK_* bits: which of on_draw(), on_examine() and on_ui_data() this definition overrides (the presentation skips it otherwise).
	var/output_hooks = 0

/// Draws the capability's own part of the holder's look (after its look_layer entries).
/datum/capability/proc/on_draw(datum/act/eval/A, datum/look/look)
	return

/// Adds the capability's examine lines.
/datum/capability/proc/on_examine(datum/act/eval/A, list/lines)
	return

/// Adds the capability's window data (merged under data["caps"][name] by present_ui_data()).
/datum/capability/proc/on_ui_data(datum/act/eval/A, list/data)
	return

/// Do the when() blocks around a compiled entry and its own `when` hold on `holder` now?
/proc/present_holds(datum/holder, datum/centry/C, datum/entry/E)
	for(var/datum/entry/W as anything in C.whens)
		if(!change_condition(holder, W.args["cond"]))
			return FALSE
	var/cond = E.args["when"]
	return isnull(cond) || !!change_condition(holder, cond)

/// The entries of `kind` that apply to `holder` now, with their enclosing conditions already checked, in effective order: the type's own, then those of
/// the activations it carries (a granted capability's look layers and examine lines).
/proc/present_entries(datum/holder, kind)
	. = list()
	var/datum/type_table/T = table_of(holder)
	for(var/datum/centry/C as anything in compiled_entries(T, kind))
		var/datum/entry/E = C.item
		if(present_holds(holder, C, E))
			. += E
	var/datum/rx_state/rx = holder.rx
	if(!rx?.activations)
		return
	for(var/datum/activation/A as anything in rx.activations)
		if(A.dead || A.scope == SCOPE_TYPE)
			continue
		for(var/datum/centry/C as anything in compiled_entries(activation_table(A), kind))
			var/datum/entry/E = C.item
			if(present_holds(holder, C, E))
				. += E

/// A table of just the entries an activation's definition brings (the ones its attach applies), for the presentation to read.
/proc/activation_table(datum/activation/A)
	var/static/list/tables = list()
	var/datum/type_table/T = tables[A.def]
	if(T)
		return T
	T = new
	T.owner_type = A.def.type
	T.items = activation_plan(A.def)
	T.caps = list()
	tables[A.def] = T
	return T

/// The capabilities of the holder's table that override an output (type-level ones; a granted capability's outputs are not read).
/proc/present_capabilities(datum/holder, hook)
	. = list()
	var/datum/type_table/T = table_of(holder)
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_CAPABILITY))
		var/datum/capability/def = C.item
		if(def.output_hooks & hook)
			var/ok = TRUE
			for(var/datum/entry/W as anything in C.whens)
				if(!change_condition(holder, W.args["cond"]))
					ok = FALSE
					break
			if(ok)
				. += def

/// The look: the capability draws of the holder's table (the look_layer entries draw through look_layers_draw(), code/engine/present/look.dm). Called from /atom/draw().
/proc/present_draw(atom/holder, datum/look/look)
	var/datum/type_table/T = table_of(holder)
	if(!length(T.items))
		return
	for(var/datum/capability/def as anything in present_capabilities(holder, OUTPUT_HOOK_DRAW))
		var/datum/act/eval/A = take(/datum/act/eval)
		A.holder = holder // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
		A.cap = def
		def.on_draw(A, look)
		A.release()

/// The examine lines the capabilities' on_examine() add (the examine_line entries are examine_collect(), code/engine/present/examine.dm). Called from caps_examine().
/proc/present_examine(atom/holder, mob/user)
	. = list()
	var/datum/type_table/T = table_of(holder)
	if(!length(T.items))
		return
	for(var/datum/capability/def as anything in present_capabilities(holder, OUTPUT_HOOK_EXAMINE))
		var/datum/act/eval/A = take(/datum/act/eval)
		A.holder = holder // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
		A.cap = def
		def.on_examine(A, .)
		A.release()

/// The window data of the holder's capabilities, merged under data["caps"][name]. Called from tgui_data().
/proc/present_ui_data(datum/holder, list/data)
	var/list/caps
	for(var/datum/capability/def as anything in present_capabilities(holder, OUTPUT_HOOK_UI))
		var/datum/act/eval/A = take(/datum/act/eval)
		A.holder = holder // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
		A.cap = def
		var/list/mine = list()
		def.on_ui_data(A, mine)
		A.release()
		if(!length(mine))
			continue
		caps ||= list()
		caps[capability_label(def)] = mine
	if(caps)
		var/list/existing = data["caps"]
		if(islist(existing))
			existing += caps
		else
			data["caps"] = caps

// ---- the window: interface() ----

/// The interface entry of a holder's table (the window it opens), or null. A subtype that declares its own window beats the one it inherits (the most
/// specific declaration wins, section 1 "Precedence"; it also says `without("ui_open")` so the inherited open op does not clash with its own).
/proc/present_interface(datum/holder)
	RETURN_TYPE(/datum/entry)
	var/datum/type_table/T = table_of(holder)
	var/datum/entry/found
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_INTERFACE))
		found = C.item
	return found

/// The first live datum a holder's window forwards to (interface(forwards = nameof(v)): a var holding one, or a list), or null.
/proc/present_forwarded_unit(datum/holder)
	READS_FROM(holder)
	var/datum/entry/declared = present_interface(holder)
	var/where = declared?.args["forwards"]
	if(!istext(where) || !(where in holder.vars))
		return null
	var/targets = holder.vars[where]
	if(!islist(targets))
		targets = targets ? list(targets) : null
	for(var/datum/unit as anything in targets)
		if(!QDELETED(unit) && unit != holder)
			return unit
	return null

/// A type's own window data: the output of the standard name ui_data(datum/act/A). A.actor is the viewer. Base: no data. On /datum: a window's host
/// need not be an atom (tgui modules, prompt windows, apps); only the reach rules of a window's ops are atom-specific.
/datum/proc/ui_data(datum/act/eval/A)
	return list()

/// The window data of a holder that declares an interface or overrides ui_data(): the type's ui_data(A) (A.holder the holder, A.actor the viewer)
/// merged over `data`, and its capabilities' data under data["caps"]. A holder that declares neither adds nothing. A window that forwards
/// (interface(forwards = nameof(v))) is its unit's panel: the first unit's data comes first and the holder's own goes over it, so the sleeper
/// console shows its sleeper's data with no ui_data() of its own. `observer` is A.observer: the viewer is a ghost with the window read-only.
/proc/present_tgui_data(datum/holder, mob/user, list/data, observer = FALSE)
	var/datum/type_table/T = table_of(holder)
	if(!length(T.items))
		return
	var/datum/act/eval/A = take(/datum/act/eval)
	A.holder = holder // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	A.actor = user // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	A.observer = observer
	A.authority = user?.click_authority() // what the viewer's inputs carry: a window shows a silicon what its link may change
	var/datum/unit = present_forwarded_unit(holder)
	if(unit)
		A.holder = unit // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
		var/list/shown = unit.ui_data(A)
		for(var/key in shown)
			data[key] = shown[key]
		A.holder = holder // ALLOW(ownership): a pooled context holds its entities for one trigger and is reset on release
	var/list/own = holder.ui_data(A)
	A.release()
	if(islist(own))
		for(var/key in own)
			data[key] = own[key]
	// A question shown in this window (asks(..., inline = TRUE)) is its modal: the client's ComplexModal reads data["modal"].
	var/list/modal = holder.presentation_modal_data()
	if(modal)
		data["modal"] = modal
	present_ui_data(holder, data)

/// A window button the holder answers with an op that has a ui_act() binding: runs it as the player (origin ORIGIN_UI), its arguments through the
/// schema boundary. Returns the op's /datum/op_result, or null when the holder has no op for the action (the legacy UI_ACT rows follow).
/proc/present_ui_act(datum/holder, mob/user, action, list/params, datum/pressed_in = null)
	RETURN_TYPE(/datum/op_result)
	if(!user || !op_has_ops(holder))
		return null
	return op_ui_act(user, holder, action, params, pressed_in = pressed_in)

// ---- what the outputs read: the carrier's read analysis ----

/// The var names a condition (a var, a tree, an id) reads on `holder`: what a change of must redraw or refresh. Ids (stat, capability key) are
/// not vars: a capability key's change marks every output (capability_key_changed()), a stat's change is its own var's.
/proc/present_condition_reads(datum/holder, cond, list/into)
	if(islist(cond))
		var/list/tree = cond
		for(var/i in 2 to length(tree))
			present_condition_reads(holder, tree[i], into)
		return
	if(istext(cond) && (cond in holder.vars))
		into |= cond

/// The implicit derived() entries of `holder`'s table: drawn_from() the vars its look_layer entries read (their `when` and `reads`), ui_from()
/// the vars its capabilities' window data reads. They add reads and never make the holder exact (derived_entry_implicit).
/proc/present_derived(atom/holder)
	. = list()
	var/datum/type_table/T = table_of(holder)
	if(!length(T.items))
		return
	var/list/drawn = list()
	var/list/shown = list()
	for(var/datum/centry/C as anything in T.items)
		var/datum/entry/E = C.item
		if(istype(E) && (E.kind == ENTRY_LOOK_LAYER || E.kind == ENTRY_EXAMINE_LINE))
			var/list/into = E.kind == ENTRY_LOOK_LAYER ? drawn : list()
			present_condition_reads(holder, E.args["when"], into)
			for(var/datum/entry/W as anything in C.whens)
				present_condition_reads(holder, W.args["cond"], into)
			for(var/read in E.args["reads"])
				if(read in holder.vars)
					into |= read
			continue
		var/datum/capability/def = C.item
		if(istype(def) && def.output_hooks)
			for(var/read in def.output_reads(OUTPUT_HOOK_DRAW))
				if(read in holder.vars)
					drawn |= read
			for(var/read in def.output_reads(OUTPUT_HOOK_UI))
				if(read in holder.vars)
					shown |= read
	if(length(drawn))
		. += derived_entry(DKIND_DRAWN, null, drawn, TRUE)
	if(length(shown))
		. += derived_entry(DKIND_UI, null, shown, TRUE)

/// The holder vars this capability's on_draw() (OUTPUT_HOOK_DRAW) or on_ui_data() (OUTPUT_HOOK_UI) read, besides capability state keys.
/datum/capability/proc/output_reads(hook)
	return list()

/// Does the type's table draw anything: a look_layer entry, or a capability that overrides on_draw()? (type_derive_flags(): such a type is redrawn.)
/proc/present_declares_look(atom/A)
	var/datum/type_table/T = table_of(A)
	for(var/datum/centry/C as anything in T.items)
		var/datum/entry/E = C.item
		if(istype(E) && E.kind == ENTRY_LOOK_LAYER)
			return TRUE
		var/datum/capability/def = C.item
		if(istype(def) && (def.output_hooks & OUTPUT_HOOK_DRAW))
			return TRUE
	return FALSE

/datum/proc/presentation_modal_data()
	return null
