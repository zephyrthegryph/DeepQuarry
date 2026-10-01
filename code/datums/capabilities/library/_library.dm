// Shared helpers for the standard capability library (doc/rewrite/dx_conventions.md §2).
//
// Every library constructor takes the standard gating arguments (needs, else_say, works_broken,
// works_unpowered, log; `at` for a compartment), stored with cap_gating() and merged onto each entry by
// cap_apply_gating(). There is no `behind` / `blocked_by` / `locked_by` and no `layer =` (G12): a state gate is a
// requirement in `needs` (req_set(COVER) / req_clear(COVER | PANEL) / req_clear(LOCK)), and a capability draws
// its fixed standard look name (code/__defines/look_names.dm), which the look resolves against the holder's
// icon ("<base>-<name>", else "<name>", else nothing); a holder that shows it another way calls look.hide(name).
// Every entry the library builds is a real operation (G16): lib_op() (cap_op() with the library's defaults) taken out
// of its wrapper with adopt_entry(), the one entry-building helper (M12), or an entry datum of the capability's own made
// an op with op_attach(). Each has a key, an action, a priority and requirements, so the gesture router ranks it
// against every other op of the holder (doc/rewrite/operations_and_actions.md §5): nothing in the library produces a
// legacy entry. An entry passes only its own gating; the capability's comes on top centrally.
//
// Offered or needs: a condition under which the player did not mean the op at all (nobody is buckled, the held item is
// not a container) is `offered`: the gesture falls through to the next op or the legacy handlers, as the resolver let
// a blocked entry fall through. A condition under which the player meant it but it can't be done (the tool click on a
// cover that is held shut) is `needs`: the refusal answers.

/**
 * A library operation: cap_op() with the library's defaults. `shape` is the preset shape it replaces (OP_SHAPE_HAND,
 * OP_SHAPE_TOOL, OP_SHAPE_USE_ON, OP_SHAPE_INSERT), whose works_broken / works_unpowered defaults apply. No provider
 * slot (by = NONE): cyborg modules and simple mobs keep working the library's parts until they have provider slots of
 * their own. Real (not a preset): the router ranks it by `action`, `priority` and declaration order.
 */
/proc/lib_op(name, handler, shape, using, key, action = ACT_USE, priority, needs, offered, else_say, delay, fuel, volume, works_broken, works_unpowered, log, list/form, name_proc, applies, stance, kind = OP_CONTROL, via = ROUTE_PHYSICAL, by = NONE, at, cooldown, behind = NONE, blocked_by = NONE, locked_by = NONE, entry)
	return cap_op(name, handler, using = using, by = by, via = via, action = action, needs = needs, delay = delay, cost = fuel, kind = kind, key = key, at = at, log = log, shape = shape, behind = behind, blocked_by = blocked_by, locked_by = locked_by, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, form = form, priority = priority, stance = stance, name_proc = name_proc, applies = applies, cooldown = cooldown, volume = volume, offered = offered, entry = entry)

/**
 * Makes E, an entry datum of a library capability's own (a slot's insert, a ladder step), a real operation: an op_def
 * with the `key`, `action` and `priority` the router ranks it by, `stance` (one: the entry's selector; a list: an
 * offered req_stance()) and `offered` requirements. The entry keeps its selectors, handler and gating (the target
 * contract stage runs them); the op adds the fixed stage order, before_op / after_op by key and the pending wait.
 * Its compartment and gating reads are taken from the entry once the capability's gating is merged
 * (cap_op_sync_gating()). Returns E.
 */
/proc/op_attach(datum/interaction/capability/E, key, action = ACT_USE, priority = 0, kind = OP_CONTROL, via = ROUTE_PHYSICAL, by = NONE, at, stance, list/offered)
	var/datum/op_def/op = new
	op.name = E.name
	op.key = key
	op.kind = kind
	op.action = action
	op.priority = priority
	op.by = by
	op.via = via
	op.at = at
	op.handler = E.handler
	op.using = E.tool || E.held_type
	op.offered = req_list(offered)
	if(islist(stance))
		op.stances = stance
		op.offered += req_stance(stance)
	else if(stance)
		E.stance = stance
		E.apply_stance_tags()
	E.priority = priority
	if(action == ACT_NONE)
		E.default_action = null
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	E.op = op
	return E

/// Takes the entry out of a one-entry wrapper built by cap_hand()/cap_tool()/cap_use_on()/cap_insert(),
/// makes src its capability and, with `id`, gives it a stable id (the predicate cache key: it must
/// differ wherever the tool or held type differs). category: overrides the constructor's;
/// empty_handed: offered only to an empty hand; pass_cap: the handler also gets this capability as
/// the named arg `cap` (review 2 M15: a handler never looks its capability up after a sleep).
/datum/capability/proc/adopt_entry(datum/capability/entry/wrapper, id, category, empty_handed = FALSE, pass_cap = FALSE)
	var/datum/interaction/capability/E = wrapper.entry
	E.cap = src
	wrapper.entry = null
	if(id)
		E.id = id
	if(category)
		E.category = category
	if(empty_handed)
		E.offered_when = list(REQ_EMPTY_HANDED)
	E.passes_cap = pass_cap
	return E

/// Draws this capability's layer while `when` holds, unless it draws nothing (CAP_NO_LAYER).
/datum/capability/proc/draw_layer(datum/look/look, when = TRUE)
	if(!layer_name || layer_name == CAP_NO_LAYER)
		return
	look.part(layer_name, !!when)

/// needs: the actor can reach the holder (adjacent, silicon remote use, or a legacy entry).
/atom/proc/cap_in_reach(mob/user, obj/item/held)
	return dq_interaction_reach(user, src, held) ? TRUE : "you're too far away"

/// needs: the holder (an item) is in one of the actor's hands.
/atom/proc/cap_in_hand(mob/user, obj/item/held)
	return dq_interaction_self_reach(user, src, held) ? TRUE : "it's not in your hand"

/proc/is_bolted(atom/A)
	return !!(A.cap_state & CAP_BOLTED)

/proc/is_welded(atom/A)
	return !!(A.cap_state & CAP_WELDED)

/// Sets D's var to a capability's type default unless the instance already differs from its compiled
/// default (a map edit, an earlier write): a capability's arguments are type defaults, instance vars win.
/proc/cap_default_var(datum/D, var_name, value)
	if(isnull(value) || D.vars[var_name] != initial(D.vars[var_name]))
		return FALSE
	D.vars[var_name] = value // ALLOW(api): the capability default writer is the reflection point: var_name is declared by the capability
	return TRUE
