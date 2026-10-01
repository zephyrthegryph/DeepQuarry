// Shared helpers for the standard capability library (doc/rewrite/dx_conventions.md §2).
//
// Every library constructor takes the standard gating arguments (needs, else_say, works_broken,
// works_unpowered, log; `at` for a compartment), stored with cap_gating() and merged onto each entry by
// cap_apply_gating(). There is no `behind` / `blocked_by` / `locked_by` and no `layer =` (G12): a state gate is a
// requirement in `needs` (req_set(COVER) / req_clear(COVER | PANEL) / req_clear(LOCK)), and a capability draws
// its fixed standard look name (code/__defines/look_names.dm), which the look resolves against the holder's
// icon ("<base>-<name>", else "<name>", else nothing); a holder that shows it another way calls look.hide(name).
// Entries are built with the standard constructors (cap_hand()/cap_tool()/cap_use_on()/cap_insert())
// and taken out of their wrapper with adopt_entry(), the one entry-building helper (M12). An entry
// passes only its own gating; the capability's comes on top centrally.

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
	D.vars[var_name] = value
	return TRUE
