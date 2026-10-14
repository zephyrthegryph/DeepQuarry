// Shared belly lists (C7, doc/rewrite/containment.md §9).
//
// A belly carries about fifty list vars: its message lists, idle emotes, the liquid
// it makes, extra autotransfer targets and the vore-spawn whitelist. Nearly every
// belly keeps its type's defaults, so every belly of a type points at one shared
// copy of each, made once:
//   - a var the type leaves unset gets the base default (the belly_default_lists table);
//   - a var a subtype sets with its own list() is shared per type (the first
//     instance's list is kept, later instances drop theirs for it);
//   - a list loaded from saved prefs that equals the shared one is swapped back
//     for it (belly_reshare_lists(), from state_post_apply()).
//
// Copy on write. These lists are never edited in place: customizing one replaces
// the var with a new list (set_messages(), the vore panel, the importer).
// emote_lists is the one list of lists written by key; writers call
// own_emote_lists() first. Only a customized list costs the belly anything.

/// Per type: var name -> the list every instance of that type shares.
GLOBAL_LIST_EMPTY(belly_type_shared_lists)

/// The base defaults for every shared list var, keyed by var name. Never mutate these: a
/// write replaces the belly's var with a new list.
/proc/build_belly_default_lists()
	// The default message lists every /obj/belly shares until a player customizes one (C7).
	var/list/defaults = list(
		"struggle_messages_outside" = list(
			"%pred's %belly wobbles with a squirming meal.",
			"%pred's %belly jostles with movement.",
			"%pred's %belly briefly swells outward as someone pushes from inside.",
			"%pred's %belly fidgets with a trapped victim.",
			"%pred's %belly jiggles with motion from inside.",
			"%pred's %belly sloshes around.",
			"%pred's %belly gushes softly.",
			"%pred's %belly lets out a wet squelch."),
		"struggle_messages_inside" = list(
			"Your useless squirming only causes %pred's slimy %belly to squelch over your body.",
			"Your struggles only cause %pred's %belly to gush softly around you.",
			"Your movement only causes %pred's %belly to slosh around you.",
			"Your motion causes %pred's %belly to jiggle.",
			"You fidget around inside of %pred's %belly.",
			"You shove against the walls of %pred's %belly, making it briefly swell outward.",
			"You jostle %pred's %belly with movement.",
			"You squirm inside of %pred's %belly, making it wobble around."),
		"absorbed_struggle_messages_outside" = list(
			"%pred's %belly wobbles, seemingly on its own.",
			"%pred's %belly jiggles without apparent cause.",
			"%pred's %belly seems to shake for a second without an obvious reason."),
		"absorbed_struggle_messages_inside" = list(
			"You try and resist %pred's %belly, but only cause it to jiggle slightly.",
			"Your fruitless mental struggles only shift %pred's %belly a tiny bit.",
			"You can't make any progress freeing yourself from %pred's %belly."),
		"escape_attempt_messages_owner" = list(
			"%prey is attempting to free themselves from your %belly!"),
		"escape_attempt_messages_prey" = list(
			"You start to climb out of %pred's %belly."),
		"escape_messages_owner" = list(
			"%prey climbs out of your %belly!"),
		"escape_messages_prey" = list(
			"You climb out of %pred's %belly."),
		"escape_messages_outside" = list(
			"%prey climbs out of %pred's %belly!"),
		"escape_item_messages_owner" = list(
			"%item suddenly slips out of your %belly!"),
		"escape_item_messages_prey" = list(
			"Your struggles successfully cause %pred to squeeze your %item out of their %belly."),
		"escape_item_messages_outside" = list(
			"%item suddenly slips out of %pred's %belly!"),
		"escape_fail_messages_owner" = list(
			"%prey's attempt to escape from your %belly has failed!"),
		"escape_fail_messages_prey" = list(
			"Your attempt to escape %pred's %belly has failed!"),
		"escape_attempt_absorbed_messages_owner" = list(
			"%prey is attempting to free themselves from your %belly!"),
		"escape_attempt_absorbed_messages_prey" = list(
			"You try to force yourself out of %pred's %belly."),
		"escape_absorbed_messages_owner" = list(
			"%prey forces themselves free of your %belly!"),
		"escape_absorbed_messages_prey" = list(
			"You manage to free yourself from %pred's %belly."),
		"escape_absorbed_messages_outside" = list(
			"%prey climbs out of %pred's %belly!"),
		"escape_fail_absorbed_messages_owner" = list(
			"%prey's attempt to escape form your %belly has failed!"),
		"escape_fail_absorbed_messages_prey" = list(
			"Before you manage to reach freedom, you feel yourself getting dragged back into %pred's %belly!"),
		"primary_transfer_messages_owner" = list(
			"%prey slid into your %dest due to their struggling inside your %belly!"),
		"primary_transfer_messages_prey" = list(
			"Your attempt to escape %pred's %belly has failed and your struggles only results in you sliding into %pred's %dest!"),
		"secondary_transfer_messages_owner" = list(
			"%prey slid into your %dest due to their struggling inside your %belly!"),
		"secondary_transfer_messages_prey" = list(
			"Your attempt to escape %pred's %belly has failed and your struggles only results in you sliding into %pred's %dest!"),
		"primary_autotransfer_messages_owner" = list(
			"%prey moves along into your %dest!"),
		"primary_autotransfer_messages_prey" = list(
			"%pred's %belly moves you along into their %dest!"),
		"secondary_autotransfer_messages_owner" = list(
			"%prey moves along into your %dest!"),
		"secondary_autotransfer_messages_prey" = list(
			"%pred's %belly moves you along into their %dest!"),
		"digest_chance_messages_owner" = list(
			"You feel your %belly beginning to become active!"),
		"digest_chance_messages_prey" = list(
			"In response to your struggling, %pred's %belly begins to get more active..."),
		"absorb_chance_messages_owner" = list(
			"You feel your %belly start to cling onto its contents..."),
		"absorb_chance_messages_prey" = list(
			"In response to your struggling, %pred's %belly begins to cling more tightly..."),
		"digest_messages_owner" = list(
			"You feel %prey's body succumb to your digestive system, which breaks it apart into soft slurry.",
			"You hear a lewd glorp as your %belly muscles grind %prey into a warm pulp.",
			"Your %belly lets out a rumble as it melts %prey into sludge.",
			"You feel a soft gurgle as %prey's body loses form in your %belly. They're nothing but a soft mass of churning slop now.",
			"Your %belly begins gushing %prey's remains through your system, adding some extra weight to your thighs.",
			"Your %belly begins gushing %prey's remains through your system, adding some extra weight to your rump.",
			"Your %belly begins gushing %prey's remains through your system, adding some extra weight to your belly.",
			"Your %belly groans as %prey falls apart into a thick soup. You can feel their remains soon flowing deeper into your body to be absorbed.",
			"Your %belly kneads on every fiber of %prey, softening them down into mush to fuel your next hunt.",
			"Your %belly churns %prey down into a hot slush. You can feel the nutrients coursing through your digestive track with a series of long, wet glorps."),
		"digest_messages_prey" = list(
			"Your body succumbs to %pred's digestive system, which breaks you apart into soft slurry.",
			"%pred's %belly lets out a lewd glorp as their muscles grind you into a warm pulp.",
			"%pred's %belly lets out a rumble as it melts you into sludge.",
			"%pred feels a soft gurgle as your body loses form in their %belly. You're nothing but a soft mass of churning slop now.",
			"%pred's %belly begins gushing your remains through their system, adding some extra weight to %pred's thighs.",
			"%pred's %belly begins gushing your remains through their system, adding some extra weight to %pred's rump.",
			"%pred's %belly begins gushing your remains through their system, adding some extra weight to %pred's belly.",
			"%pred's %belly groans as you fall apart into a thick soup. Your remains soon flow deeper into %pred's body to be absorbed.",
			"%pred's %belly kneads on every fiber of your body, softening you down into mush to fuel their next hunt.",
			"%pred's %belly churns you down into a hot slush. Your nutrient-rich remains course through their digestive track with a series of long, wet glorps."),
		"absorb_messages_owner" = list(
			"You feel %prey becoming part of you."),
		"absorb_messages_prey" = list(
			"You feel yourself becoming part of %pred's %belly!"),
		"unabsorb_messages_owner" = list(
			"You feel %prey reform into a recognizable state again."),
		"unabsorb_messages_prey" = list(
			"You are released from being part of %pred's %belly."),
		"examine_messages" = list(
			"They have something solid in their %belly!",
			"It looks like they have something in their %belly!"),
		"examine_messages_absorbed" = list(
			"Their body looks somewhat larger than usual around the area of their %belly.",
			"Their %belly looks larger than usual."),
		"trash_eater_in" = list(
			"%pred demonstrates their voracious capabilities by swallowing %item whole!"
			),
		"trash_eater_out" = list( //handles all item expulsions regardless of whether they have the trash perk
			"%pred expels %item from their %belly!"
			)
	)
	defaults["fullness1_messages"] = list("%pred's %belly looks empty")
	defaults["fullness2_messages"] = list("%pred's %belly looks filled")
	defaults["fullness3_messages"] = list("%pred's %belly looks like it's full of liquid")
	defaults["fullness4_messages"] = list("%pred's %belly is quite full!")
	defaults["fullness5_messages"] = list("%pred's %belly is completely filled to it's limit!")
	defaults["emote_lists"] = list()
	defaults["generated_reagents"] = list(REAGENT_ID_WATER = 1)
	defaults["autotransferextralocation"] = list()
	defaults["autotransferextralocation_secondary"] = list()
	defaults["vorespawn_whitelist"] = list()
	return defaults

GLOBAL_TABLE(belly_default_lists, GLOBAL_PROC_REF(build_belly_default_lists))

/// The list `var_name` shares on this belly's type, or null if the type has none of its own.
/obj/belly/proc/belly_shared_list(var_name)
	var/list/type_lists = GLOB.belly_type_shared_lists[type]
	return type_lists?[var_name] || GLOBAL_TABLE_GET(belly_default_lists)[var_name]

/// Points every shared list var at its shared copy (see the file comment).
/obj/belly/proc/belly_share_lists()
	var/list/defaults = GLOBAL_TABLE_GET(belly_default_lists)
	var/list/type_lists = GLOB.belly_type_shared_lists[type]
	for(var/var_name in defaults)
		var/list/current = vars[var_name]
		if(isnull(current))
			vars[var_name] = defaults[var_name] // ALLOW(api): interned shared lists swapped in by var name
			continue
		if(!type_lists)
			type_lists = list()
			GLOB.belly_type_shared_lists[type] = type_lists
		var/list/shared = type_lists[var_name]
		if(shared)
			vars[var_name] = shared // ALLOW(api): interned shared lists swapped in by var name
		else
			type_lists[var_name] = current

/// After a load: every list equal to the shared one goes back to sharing it.
/obj/belly/proc/belly_reshare_lists()
	for(var/var_name in GLOBAL_TABLE_GET(belly_default_lists))
		var/list/current = vars[var_name]
		var/list/shared = belly_shared_list(var_name)
		if(current == shared)
			continue
		if(!islist(current))
			if(isnull(current))
				vars[var_name] = shared // ALLOW(api): interned shared lists swapped in by var name
			continue
		if(belly_lists_equal(current, shared))
			vars[var_name] = shared // ALLOW(api): interned shared lists swapped in by var name

/// TRUE if two lists hold the same entries (and values) in the same order, one level of nesting deep.
/proc/belly_lists_equal(list/a, list/b)
	if(length(a) != length(b))
		return FALSE
	for(var/i in 1 to length(a))
		var/key = a[i]
		if(key != b[i])
			return FALSE
		if(istext(key))
			var/value_a = a[key]
			var/value_b = b[key]
			if(islist(value_a) || islist(value_b))
				if(!islist(value_a) || !islist(value_b) || !belly_lists_equal(value_a, value_b))
					return FALSE
			else if(value_a != value_b)
				return FALSE
	return TRUE

/// Makes emote_lists this belly's own before a keyed write. Idempotent.
/obj/belly/proc/own_emote_lists()
	if(emote_lists != belly_shared_list("emote_lists") && islist(emote_lists))
		return emote_lists
	emote_lists = islist(emote_lists) ? emote_lists.Copy() : list()
	return emote_lists

/// Shared list vars this belly has customized (no longer the shared copy). The rest stay out of the saved state.
/obj/belly/proc/belly_unshared_list_names()
	. = list()
	for(var/var_name in GLOBAL_TABLE_GET(belly_default_lists))
		if(vars[var_name] != belly_shared_list(var_name))
			. += var_name

/// The lists this belly holds for itself rather than shares: customized shared-list vars and
/// the lazy per-instance ones (the C7 memory measure; an empty, default belly has none).
/obj/belly/proc/belly_owned_lists()
	. = belly_unshared_list_names()
	if(items_preserved)
		. += "items_preserved"
	if(belly_surrounding)
		. += "belly_surrounding"
	if(containment_ledger())
		. += "ledger"
