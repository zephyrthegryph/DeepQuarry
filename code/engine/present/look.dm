// Look layers (doc/rewrite/final_api.html, section 13 "Look"): look_layer(name, when =) entries on a type or a capability. A layer is drawn while
// its condition holds, through the look builder (look.part: the icon state "<base>-<name>" when the icon has it), so a cover's open state is
// `look_layer(LOOK_COVER_OPEN, when = COVER_OPEN)` and nothing else. The condition is read when the look is drawn: a condition used for matching.
//
// A capability key that changes redraws its holder (capability_key_changed -> look_key_changed): the layers a key gates need no call after the setter.

/// look_layer(name, when = condition): the layer is part of the holder's look while the condition holds.
/proc/look_layer(layer_name, when = null, under = FALSE, list/reads = null)
	if(!istext(layer_name) || !length(layer_name))
		declare_report("look_layer(): the first argument is the layer's name (a LOOK_* text), got [isnull(layer_name) ? "null" : "[layer_name]"]")
		return null
	return entry_make(ENTRY_LOOK_LAYER, null, list("layer" = layer_name, "when" = when, "under" = under, "reads" = reads))

/**
 * look_glow(glow, when = condition): the holder casts a light while the condition holds (no condition: always). `glow` is a GLOW(range, power, color)
 * value, or a handler (PROC_REF / CAP_PROC) that returns one, read when the look is drawn; its reads are the handler's declared reads, so a light
 * that follows a tracked var (a lamp's colour) redraws when the var changes. A type that starts lit declares it here instead of setting
 * light_range on the type: `look_glow(GLOW(2, 1, "#ff0000"))`. A draw() that also calls look.glow() wins (the type's own draw runs after its entries).
 */
/proc/look_glow(glow, when = null, list/reads = null)
	if(!islist(glow) && !istext(glow))
		declare_report("look_glow(): the first argument is a GLOW(range, power, color) or a PROC_REF returning one, got [isnull(glow) ? "null" : "[glow]"]")
		return null
	return entry_make(ENTRY_LOOK_LAYER, null, list("glow" = glow, "when" = when, "under" = FALSE, "reads" = reads))

/datum/type_table
	/// 1 when the table has a look_layer entry, 0 when not, null before anybody asked (see look_table_has_layers).
	var/look_layers_known

/// Does the type's table (or an activation on the holder) carry a look_layer? Cached per table.
/proc/look_table_has_layers(datum/type_table/T)
	if(isnull(T.look_layers_known))
		T.look_layers_known = length(compiled_entries(T, ENTRY_LOOK_LAYER)) ? 1 : 0
	return T.look_layers_known

/// The names of the layers that are part of `holder`'s look now, in order, each once.
/proc/look_layers_of(datum/holder)
	RETURN_TYPE(/list)
	. = list()
	if(!holder || QDELETED(holder))
		return
	for(var/datum/present_row/R as anything in present_rows(holder, ENTRY_LOOK_LAYER))
		var/source = R.entry.args["layer"]
		if(isnull(source))
			continue // a look_glow() row: look_glow_of()
		var/datum/act/op/A = present_context(holder, R, null)
		if(present_row_holds(holder, R, A))
			var/list/names = list()
			examine_row_text(A, source, names) // a layer name is text, or a handler's answer (CAP_PROC / PROC_REF) in the same forms an examine line takes
			for(var/layer_name in names)
				. |= layer_name
		A.release()

/// Draws every active layer into `look` (called from /atom/proc/draw after the legacy capabilities draw theirs).
/proc/look_layers_draw(atom/holder, datum/look/look)
	if(!look_table_has_layers(table_of(holder)) && !length(holder.rx?.activations))
		return
	for(var/layer_name in look_layers_of(holder))
		look.part(layer_name)
	var/list/glow = look_glow_of(holder)
	if(glow)
		look.glow(glow)

/// The GLOW(range, power, color) the holder's look_glow() rows give now (the last row that holds wins), or null when none holds.
/proc/look_glow_of(datum/holder)
	if(!holder || QDELETED(holder))
		return null
	for(var/datum/present_row/R as anything in present_rows(holder, ENTRY_LOOK_LAYER))
		var/glow = R.entry.args["glow"]
		if(isnull(glow))
			continue
		var/datum/act/op/A = present_context(holder, R, null)
		if(present_row_holds(holder, R, A))
			if(istext(glow))
				glow = op_call(A, glow)
			if(islist(glow))
				. = glow
		A.release()

/// A capability key of `holder` changed: when its look reads keys, the look is redrawn. Called from capability_key_changed().
/proc/look_key_changed(datum/holder)
	if(!isatom(holder) || QDELETED(holder))
		return
	if(look_table_has_layers(table_of(holder)))
		state_changed(holder)

/// How the look applies a dir to its holder; the atom layer answers with set_dir() (code/game/atom/_atom.dm).
/atom/proc/look_set_dir(new_dir)
	return

/// How the look applies a base icon_state; the atom layer answers with set_icon_state(), which publishes it (code/game/atom/_atom.dm).
/atom/proc/look_set_icon_state(new_state)
	return

/// How the look applies a base icon file; the atom layer answers with set_icon(), which publishes it (code/game/atom/_atom.dm).
/atom/proc/look_set_icon(new_icon)
	return

/// How the look applies an invisibility level; the atom layer answers with set_invisibility(), which publishes it (code/game/atom/_atom.dm).
/atom/proc/look_set_invisibility(new_invisibility)
	return
