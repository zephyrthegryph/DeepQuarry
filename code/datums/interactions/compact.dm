/**
 * Compact interaction specs (doc/rewrite/interactions.md §5a).
 *
 * A get_interactions() override returning INTERACT_* macro specs (code/__defines/
 * interactions.dm) in place of a declare_interactions() override plus a
 * one-off /datum/interaction subtype for the common shapes: a plain self-use,
 * an empty-hand touch, an item used on the target (typed or not), and
 * alt-click. The full datum form (interaction.dm) stays for anything with a
 * custom display_name(), messages(), applies_to() or other override - menus,
 * multi-step or heavily conditional interactions.
 *
 * Each spec compiles, on first use, into a /datum/interaction/generic
 * singleton, interned by dq_interaction_from_spec() so two types that declare
 * an identical spec (most often an inherited one: a base type's proc,
 * referenced through .proc/name from a shared ancestor) share the same
 * instance - zero extra memory beyond the first. Generated interactions plug
 * into the same registry, resolver and entry dispatch as the full form:
 * examine, the Menu, screentips and keybinds all keep working with no extra
 * code.
 */
/datum/interaction/generic
	/// TRUE only for INTERACT_USE: a self-use has no legacy fallthrough once
	/// reached (the old attack_self chain had nothing further to fall through
	/// to), so its effect proc's own return value is ignored - a plain existing
	/// proc, not written for the interaction system, can be pointed at with no
	/// wrapper. FALSE for every other shape: attack_hand falls through to
	/// hand_gate()/pickup, click_alt to the default alt-click panel, and
	/// attackby/insert may have sibling candidates competing for one click -
	/// all of those need the effect's real TRUE/FALSE, same as the full form.
	var/always_handled = FALSE

/datum/interaction/generic/New(id, name, category, priority, default_action, list/requires, effect, entry, held_type, list/offered_when, consumes_input, behind_gate, always_handled)
	src.id = id
	src.name = name
	src.category = category
	src.priority = priority
	src.default_action = default_action
	src.requires = requires
	src.effect = effect
	src.entry = entry
	src.held_type = held_type
	src.offered_when = offered_when
	src.consumes_input = consumes_input
	src.behind_gate = behind_gate
	src.always_handled = always_handled

/datum/interaction/generic/run_effect(mob/actor, atom/target, obj/item/held)
	var/ran = call(target, effect)(actor, held, src)
	return always_handled ? TRUE : ran

/**
 * Turns one compact spec (an INTERACT_* macro's output) into its interned
 * /datum/interaction/generic singleton. Called from declare_interactions()
 * for every entry in a type's `interactions` list.
 */
/proc/dq_interaction_from_spec(owner_type, list/spec)
	var/static/list/cache = list()

	var/kind = spec[1]
	var/name = spec[2]
	var/effect = spec[3]
	var/list/requires = spec[4]
	var/held_type = length(spec) >= 5 ? spec[5] : null

	var/effect_key = "[effect]"
	var/entry
	var/category
	var/default_action = INPUT_ACTION_USE
	var/always_handled = FALSE
	switch(kind)
		if(INTERACT_KIND_USE)
			entry = INTERACTION_ENTRY_SELF
			category = INTERACTION_CAT_TOGGLE
			always_handled = TRUE
		if(INTERACT_KIND_HAND)
			entry = INTERACTION_ENTRY_HAND
			category = INTERACTION_CAT_OPEN
		if(INTERACT_KIND_ITEM)
			entry = INTERACTION_ENTRY_ITEM
			category = INTERACTION_CAT_INSERT
		if(INTERACT_KIND_INSERT)
			entry = INTERACTION_ENTRY_ITEM
			category = INTERACTION_CAT_INSERT
		if(INTERACT_KIND_ALT)
			entry = INTERACTION_ENTRY_ALT
			category = INTERACTION_CAT_TOGGLE
			default_action = INPUT_ACTION_ALTERNATE
		else
			CRASH("dq_interaction_from_spec: unknown compact interaction kind [kind] on [owner_type]")

	if(!name)
		name = (kind == INTERACT_KIND_INSERT) ? dq_interaction_insert_name(held_type) : dq_interaction_name_from_effect(effect_key)

	var/key = "[kind]|[effect_key]|[held_type]|[length(requires)]"
	var/datum/interaction/generic/cached = cache[key]
	if(cached)
		return cached

	var/id = "gen_[dq_interaction_slug(kind)]_[dq_interaction_slug(effect_key)]"
	if(interaction_by_id(id) || cache_has_id(cache, id))
		id = "[id]_[md5(key)]"

	var/datum/interaction/generic/interaction = new(id, name, category, /* priority */ 0, default_action, requires, effect, entry, held_type, /* offered_when */ null, /* consumes_input */ TRUE, /* behind_gate */ TRUE, always_handled)
	cache[key] = interaction
	return interaction

/// Whether any interned generic interaction already uses this id (id collision guard).
/proc/cache_has_id(list/cache, id)
	for(var/key in cache)
		var/datum/interaction/generic/interaction = cache[key]
		if(interaction.id == id)
			return TRUE
	return FALSE

/// "Insert " plus the article and name of a held-item type, e.g. "Insert a power cell".
/proc/dq_interaction_insert_name(held_type)
	if(!held_type)
		return "Insert"
	var/list/types = islist(held_type) ? held_type : list(held_type)
	var/list/names = list()
	for(var/atom/path as anything in types)
		names += dq_pred_article(initial(path.name))
	return "Insert [english_list(names, and_text = " or ")]"

/// A display name from a proc reference string: the last path segment, underscores to spaces, capitalized.
/proc/dq_interaction_name_from_effect(effect_key)
	var/slash = findlasttext(effect_key, "/")
	var/tail = slash ? copytext(effect_key, slash + 1) : effect_key
	tail = replacetext(tail, "_", " ")
	return capitalize(tail)

/// A lowercase, alnum-and-underscore-only slug of `text`, for building stable ids.
/proc/dq_interaction_slug(text)
	var/result = ""
	for(var/i in 1 to length(text))
		var/ch = copytext(text, i, i + 1)
		if(ch == " " || ch == "/" || ch == "." || ch == "-")
			result += "_"
		else if(findtext("abcdefghijklmnopqrstuvwxyz0123456789_", ch, 1, 0) || findtext("ABCDEFGHIJKLMNOPQRSTUVWXYZ", ch, 1, 0))
			result += lowertext(ch)
	return result
