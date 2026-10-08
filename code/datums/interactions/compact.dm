/**
 * Compact interaction specs (doc/rewrite/interactions.md §5a).
 *
 * A get_interactions() override returning INTERACT_* macro specs (code/__defines/
 * interactions.dm) in place of a declare_interactions() override plus a
 * one-off /datum/interaction subtype for the common shapes: a plain self-use,
 * an empty-hand touch, an item used on the target (typed or not), and
 * alt-click. The full datum form (interaction.dm) stays for anything with a
 * custom display_name(), feedback_for(), applies_to() or other override - menus,
 * multi-step or heavily conditional interactions.
 *
 * Each spec compiles, on first use, into a /datum/interaction/generic
 * singleton, interned by dq_interaction_from_spec() so two types that declare
 * an identical spec (most often an inherited one: a base type's proc,
 * referenced through PROC_REF(name) from a shared ancestor) share the same
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
	/// Optional proc on the target (a PROC_REF) answering whether this interaction is offered on
	/// that instance at all (applies_to()); null offers it everywhere its type declares it.
	var/applies_proc

/datum/interaction/generic/applies_to(atom/target)
	if(applies_proc && !holder_call(target, applies_proc))
		return FALSE
	return ..()

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

/// Every generic interaction carries its own requirements: key by id, not type
/// (a type key made every compact interaction share the first one's predicate).
/datum/interaction/generic/predicate_key()
	return "[type]:[id]"

/datum/interaction/generic/run_effect(mob/actor, atom/target, obj/item/held)
	var/ran = holder_call(target, effect, list(actor, held, src))
	// Handled, but the input isn't used up: the entry's caller lets afterattack / the loot panel follow.
	if(ran == INTERACTION_HANDLED_PASS && GLOB.interaction_entry_actors[actor])
		GLOB.interaction_entry_pass[actor] = TRUE
	return always_handled ? TRUE : ran

/**
 * Turns one compact spec (an INTERACT_* macro's output) into its interned
 * /datum/interaction/generic singleton. Called from declare_interactions()
 * for every entry in a type's `interactions` list.
 */
/proc/dq_interaction_from_spec(owner_type, list/spec)
	// Keyed by the spec list's own reference identity, not its printed content:
	// PROC_REF(x) expands to nameof() of the proc, a bare proc NAME with no type prefix, so two
	// unrelated types that happen to name their effect proc the same thing (e.g.
	// two different "interaction_self" procs) would collide on a string key. A
	// spec's identity is stable across calls that share it though: get_interactions()
	// returns a var/static/list, computed once per declaring proc and reused by
	// every subtype that inherits it unchanged (the assembly hierarchy's shared
	// assembly_self spec) - and distinct for two types that each build their own
	// list (aicard vs bodysnatcher), even if the content looks similar.
	var/static/list/cache = list() // ALLOW(cache): keyed by spec list identity; lists are not valid CACHED keys
	var/datum/interaction/generic/cached_by_ref = cache[spec]
	if(cached_by_ref)
		return cached_by_ref

	var/kind = spec[1]
	var/name = spec[2]
	var/effect = spec[3]
	var/list/requires = spec[4]
	var/held_type = length(spec) >= 5 ? spec[5] : null
	// The stance the interaction answers (I_HELP/I_DISARM/I_GRAB/I_HURT), or null for any: the INTERACT_*_AS shapes.
	var/stance = length(spec) >= 6 ? spec[6] : null
	// INTERACT_ORDER_DEFAULT: the type's default for this input, tried after everything else it offers.
	var/priority = (length(spec) >= 7 && spec[7] == INTERACT_ORDER_DEFAULT) ? INTERACTION_DEFAULT_PRIORITY : 0
	var/list/offered_when
	var/list/tags

	var/effect_key = "[effect]"
	var/entry
	var/category
	var/default_action = INPUT_ACTION_USE
	var/always_handled = FALSE
	var/behind_gate = TRUE
	// The entry base types' own requirements (entries.dm): a compact spec lists only
	// what it adds, so an item's self-use still needs it in hand and the rest need reach.
	var/list/base_requires
	if(kind == INTERACT_KIND_USE || kind == INTERACT_KIND_SELF)
		base_requires = ispath(owner_type, /obj/item) ? list(REQ_SELF_USE_REACH) : list()
	else if(kind == INTERACT_KIND_SILICON || kind == INTERACT_KIND_ROBOT || kind == INTERACT_KIND_OBSERVER || kind == INTERACT_KIND_TK)
		base_requires = list() // the actor's adapter decides reach (the AI's cameras, a cyborg's link, a ghost anywhere)
	else
		base_requires = list(REQ_INTERACTION_REACH)
	requires = base_requires + (requires || list())
	switch(kind)
		if(INTERACT_KIND_USE)
			entry = INTERACTION_ENTRY_SELF
			category = INTERACTION_CAT_TOGGLE
			always_handled = TRUE
		if(INTERACT_KIND_SELF)
			entry = INTERACTION_ENTRY_SELF
			category = INTERACTION_CAT_TOGGLE
		if(INTERACT_KIND_HAND)
			entry = INTERACTION_ENTRY_HAND
			category = INTERACTION_CAT_OPEN
		if(INTERACT_KIND_HAND_UNGATED)
			entry = INTERACTION_ENTRY_HAND
			category = INTERACTION_CAT_OPEN
			behind_gate = FALSE
		if(INTERACT_KIND_DRAG)
			entry = INTERACTION_ENTRY_DRAG
			category = INTERACTION_CAT_INSERT
			default_action = null
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
		// Object verb (I7): resolver-native, chosen from the Menu (no key or click runs it).
		if(INTERACT_KIND_VERB)
			category = INTERACTION_CAT_CONFIGURE
			default_action = null
		// Actor-kind Use (I3): resolver-native, offered only to the actors their tags name.
		if(INTERACT_KIND_SILICON)
			category = INTERACTION_CAT_OPEN
			tags = (tags || list()) + list(INTERACTION_TAG_REMOTE, INTERACTION_TAG_SILICON)
		if(INTERACT_KIND_ROBOT)
			category = INTERACTION_CAT_OPEN
			// A cyborg's own Use goes ahead of the silicon one it overrides. As an op (operations_and_actions.md 5a) it is
			// declared before the silicon op instead: declaration order, not a priority.
			priority = 1
			tags = (tags || list()) + list(INTERACTION_TAG_SILICON)
		if(INTERACT_KIND_OBSERVER)
			category = INTERACTION_CAT_OPEN
			tags = (tags || list()) + list(INTERACTION_TAG_OBSERVER)
		if(INTERACT_KIND_TK)
			category = INTERACTION_CAT_OPEN
			// Ahead of the hand's interactions telekinesis also reaches. As an op it takes ROUTE_TK instead: a telekinetic
			// click reaches only the ops of its own route.
			priority = 1
			tags = (tags || list()) + list(INTERACTION_TAG_TELEKINESIS)
		else
			CRASH("dq_interaction_from_spec: unknown compact interaction kind [kind] on [owner_type]")

	if(!name)
		name = (kind == INTERACT_KIND_INSERT) ? dq_interaction_insert_name(held_type) : dq_interaction_name_from_effect(effect_key)

	// Id disambiguation only: several distinct specs (different spec objects) can
	// still want the same auto-generated id text (two "interaction_self" procs on
	// unrelated types); this seed just needs to vary between them, not to be a
	// lookup key on its own.
	var/id_seed = "[kind]|[effect_key]|[held_type]|[owner_type]|[stance]|[priority]" // deterministic across builds (a \ref is not)
	var/base_id = "gen_[dq_interaction_slug(kind)]_[dq_interaction_slug(effect_key)]"
	var/id = base_id
	var/attempt = 0
	while(interaction_by_id(id) || cache_has_id(cache, id))
		id = "[base_id]_[md5("[id_seed]|[attempt++]")]"

	var/datum/interaction/generic/interaction = new(id, name, category, priority, default_action, requires, effect, entry, held_type, offered_when, /* consumes_input */ TRUE, behind_gate, always_handled)
	interaction.tags = tags
	interaction.stance = stance
	interaction.apply_stance_tags()
	cache[spec] = interaction
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
	// A converted handler's effect is named after the old proc (interaction_item, <type>_interaction_hand...):
	// name it for what the player does, not for the proc.
	var/static/list/converted_names = list("item" = "Use", "hand" = "Use", "self" = "Use", "alt" = "Alternate use", "drag" = "Drop onto")
	var/marker = findlasttext(tail, "interaction_")
	if(marker && (marker == 1 || copytext(tail, marker - 1, marker) == "_"))
		var/converted = converted_names[copytext(tail, marker + length("interaction_"))]
		if(converted)
			return converted
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
