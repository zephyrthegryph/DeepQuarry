/**
 * Generated help (doc/rewrite/interactions.md §8): the keys that reach an
 * interaction, the examine "Interactions" section and screentips. All of it is
 * read from the resolver, so it can't drift from what the code does.
 */

/// The keys that run `interaction` right now, as shown to a player: "Click", "Alt-click", bound category keys.
/proc/interaction_keys(client/player, datum/interaction_resolution/resolution, datum/interaction/interaction)
	. = list()
	if(!(interaction in resolution.available))
		return
	if(interaction.default_action)
		var/list/best = resolution.best_for_action(interaction.default_action)
		if(length(best) == 1 && best[1] == interaction)
			if(interaction.default_action == INPUT_ACTION_USE)
				. += "Click"
			else if(interaction.default_action == INPUT_ACTION_ALTERNATE)
				. += "Alt-click"
				if(player?.right_click_binding() == INPUT_ACTION_ALTERNATE)
					. += "Right-click"
	if(interaction.category && player)
		var/list/best_in_category = resolution.best_in_category(interaction.category)
		if(length(best_in_category) == 1 && best_in_category[1] == interaction)
			var/datum/keybinding/binding = GLOB.keybindings[INTERACTION_CATEGORY_BINDING(interaction.category)]
			if(binding)
				var/profile = player.mob?.keybind_profile() || KEYBIND_PROFILE_DEFAULT
				. += keybinding_keys(binding, profile, player.keybinding_overrides())

/// The examine section: what `user` can do to `target` now, with keys, and what they can't, with why. Null if nothing applies.
/proc/interaction_examine_lines(mob/user, atom/target)
	var/datum/interaction_resolution/resolution = interactions_for(user, target, user.get_active_hand())
	if(!length(resolution.available) && !length(resolution.blocked))
		return null
	var/list/lines = list(span_bold("Interactions"))
	for(var/datum/interaction/interaction as anything in resolution.available)
		var/list/keys = interaction_keys(user.client, resolution, interaction)
		lines += span_notice("[interaction.display_name(user, target)][length(keys) ? " ([jointext(keys, ", ")])" : ""]")
	for(var/datum/interaction/interaction as anything in resolution.blocked)
		lines += span_warning("[interaction.display_name(user, target)]: [resolution.blocked[interaction]]")
	return lines

/// The screentip for `target`: its name, then what Click and Alt-click would do. Null for nothing to show.
/proc/interaction_screentip_text(mob/user, atom/target, obj/item/held)
	if(!user || !target)
		return null
	var/datum/interaction_resolution/resolution = interactions_for(user, target, held)
	var/list/parts = list()
	var/list/use = resolution.best_for_action(INPUT_ACTION_USE)
	if(length(use) == 1)
		var/datum/interaction/interaction = use[1]
		parts += "Click: [interaction.display_name(user, target)]"
	else if(length(use) > 1)
		parts += "Click: choose"
	var/list/alternate = resolution.best_for_action(INPUT_ACTION_ALTERNATE)
	if(length(alternate) == 1)
		var/datum/interaction/interaction = alternate[1]
		parts += "Alt-click: [interaction.display_name(user, target)]"
	else if(length(alternate) > 1)
		parts += "Alt-click: choose"
	if(!length(parts))
		return capitalize(target.name)
	return "[capitalize(target.name)]\n[jointext(parts, "\n")]"

// ---------------------------------------------------------------------------
// Screentips: one screen object per client, updated when the hovered atom or
// the held item changes.

/atom/movable/screen/interaction_screentip
	name = ""
	icon = null
	icon_state = null
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	screen_loc = "TOP,LEFT"
	plane = PLANE_PLAYER_HUD_ABOVE
	maptext_height = 64
	maptext_width = 480
	maptext_x = 0
	maptext_y = -48

/// This client's screentip, when screentips are on.
/client/var/tmp/atom/movable/screen/interaction_screentip/screentip
/// What the screentip was made from, so it only updates when the hovered atom or the held item changes.
/client/var/tmp/screentip_key

/// Are screentips on for this client?
/client/proc/screentips_enabled()
	return prefs?.read_preference(/datum/preference/toggle/screentips) ? TRUE : FALSE

/// Refreshes the screentip for the hovered atom. Cheap when nothing changed.
/client/proc/update_screentip()
	if(!screentips_enabled() || !mob)
		clear_screentip()
		return
	var/atom/hovered = hovered_atom()
	var/obj/item/held = mob.get_active_hand()
	var/key = "[hovered ? REF(hovered) : "none"]|[held ? REF(held) : "none"]"
	if(key == screentip_key && screentip && (screentip in screen))
		return
	screentip_key = key
	var/text = hovered ? interaction_screentip_text(mob, hovered, held) : null
	if(!screentip)
		screentip = new
	if(!(screentip in screen))
		screen += screentip
	screentip.maptext = text ? MAPTEXT("<span style='text-align:center'>[replacetext(html_encode(text), "\n", "<br>")]</span>") : null

/client/proc/clear_screentip()
	screentip_key = null
	if(screentip)
		screen -= screentip
		screentip.maptext = null
