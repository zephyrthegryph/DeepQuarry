/**
 * The Abilities tab of the stat panel (the right side panel): the mob's ability list (action.dm) as buttons grouped by category, with
 * the mob's resources and the toggles that are on at the top. It replaced the action buttons of the HUD.
 *
 * One panel per client (the client owns it). The data goes to the stat panel as an "update_abilities" message
 * (tgui-panel/statpanel); its buttons come back as "Abilities-Act" messages (/client/on_stat_panel_message). Nothing polls: the
 * panel is sent when an ability is gained or lost (Grant()/Remove()), when its state changes (ability_changed(),
 * update_mob_action_buttons()), when a granted capability comes or goes (capabilities_changed()) and when a resource changes.
 * Pushes of one moment coalesce into one. A cooldown is sent as the time left; the tab counts it down on its own.
 *
 * The list's order is the player's: the saved order (/datum/preference/ability_order, by ability id) first, then the abilities not
 * yet placed by category and the order they were gained in. The first ABILITY_HOTKEY_SLOTS of the list are the hotkeys of the
 * slot keybindings (keybindings/abilities.dm). Reordering from the tab saves the order and logs it.
 */

/// How soon after a change the tab is sent; changes within it share one message.
#define ABILITY_PANEL_PUSH_DELAY (0.2 SECONDS)

/// The player's saved order of ability ids, a hidden player preference.
/datum/preference/ability_order
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "ability_order"
	savefile_identifier = PREFERENCE_PLAYER

/datum/preference/ability_order/is_valid(value)
	if(!islist(value))
		return FALSE
	for(var/id in value)
		if(!istext(id))
			return FALSE
	return TRUE

/datum/preference/ability_order/pref_deserialize(input, datum/preferences/preferences)
	var/list/cleaned = list()
	if(!islist(input))
		return cleaned
	for(var/id in input)
		if(istext(id) && length(id) && !(id in cleaned))
			cleaned += copytext(id, 1, 200)
	return cleaned

/datum/preference/ability_order/create_default_value()
	return list()

/datum/preference/ability_order/is_accessible(datum/preferences/preferences)
	. = ..()
	return FALSE

/// The categories in the order they are listed by default.
/proc/ability_category_rank(category)
	switch(category)
		if(ABILITY_CATEGORY_ITEMS)
			return 1
		if(ABILITY_CATEGORY_SPECIES)
			return 2
		if(ABILITY_CATEGORY_SPELLS)
			return 3
		if(ABILITY_CATEGORY_IMPLANTS)
			return 4
	return 5

/// The abilities of `user` in the player's order: the saved order, then what it does not place by category and gain order.
/proc/ordered_abilities(mob/user)
	if(!user)
		return list()
	return ability_order_sorted(user.actions, user.client?.prefs?.read_preference(/datum/preference/ability_order))

/// `abilities` in the order of `saved` (a list of ability ids): the ones it names first, in its order, then the rest by category and by the
/// order they came in. An id that is not among the abilities is ignored; two abilities with one id keep the order they came in.
/proc/ability_order_sorted(list/abilities, list/saved)
	var/list/result = list()
	var/list/keys = list()
	var/index = 0
	for(var/datum/action/entry as anything in abilities)
		if(QDELETED(entry))
			continue
		index++
		var/place = saved ? saved.Find(entry.ability_id()) : 0
		// Placed abilities come first, in the saved order; the rest after them by category, then by when they were gained.
		var/key = place ? place : 10000 + ability_category_rank(entry.ability_category) * 1000 + index
		// Insert in key order; an equal key goes after the earlier one (the order they were gained in).
		var/at = length(result) + 1
		for(var/i in 1 to length(result))
			if(keys[i] > key)
				at = i
				break
		result.Insert(at, entry)
		keys.Insert(at, key)
	return result

/// The order to save when the player puts `picked` (abilities, in the new order) on the tab: their ids first, then the ids of `previous` (the order
/// saved so far) that are not among them, so an ability the player does not have now keeps its place after the ones they do.
/proc/ability_order_to_save(list/picked, list/previous)
	var/list/saved = list()
	for(var/datum/action/entry as anything in picked)
		saved |= entry.ability_id()
	for(var/id in previous)
		saved |= id
	return saved

/// The abilities of `user` that the refs of a reorder name, in that order, or null when they are not exactly the abilities `user` has now (each
/// once): a message that names too few, too many, a stranger's or a repeated one is refused.
/proc/ability_order_from_refs(mob/user, list/order)
	if(!islist(order))
		return null
	if(length(order) != length(ordered_abilities(user)))
		return null
	var/list/picked = list()
	for(var/ref in order)
		var/datum/action/entry = handle_get(ref)
		if(!istype(entry) || entry.action_owner() != user || (entry in picked))
			return null
		picked += entry
	return picked

/// The ability in slot `slot` (1 to ABILITY_HOTKEY_SLOTS) of `user`'s list, or null.
/proc/ability_in_slot(mob/user, slot)
	if(!isnum(slot) || slot < 1 || slot > ABILITY_HOTKEY_SLOTS)
		return null
	var/list/abilities = ordered_abilities(user)
	if(slot > length(abilities))
		return null
	return abilities[slot]

// ---- The mob side ----

/// The mob's abilities (what is in the list, or what any of it shows) changed: its Abilities tab is sent again shortly.
/mob/proc/abilities_changed()
	if(!client)
		return
	ability_panel_of(client).queue_push()

/// The state an ability depends on changed (an item was equipped, the mob fell, was cuffed): the tab is refreshed. Called by the items and states
/// whose abilities become usable or not.
/mob/proc/update_mob_action_buttons()
	abilities_changed()

/// The capabilities the mob carries changed (a grant came or went): the abilities they bring are looked at again (op_ability.dm).
/mob/capabilities_changed()
	sync_op_abilities()

/// Uses `entry` for this mob as from the tab (`via` = "tab") or a hotkey ("slot 3"): the entry's refusal is told to the player, the use is logged.
/mob/proc/use_ability_entry(datum/action/entry, via)
	if(!entry || QDELETED(entry) || entry.action_owner() != src)
		log_input("Input: [key_name(src)] tried to use an ability they do not have ([via]).")
		return FALSE
	if(!checkClickCooldown())
		return FALSE
	setClickCooldown(0.1 SECONDS)
	var/why = entry.ability_refusal()
	if(why)
		to_chat(src, span_warning("[entry.name]: [why]."))
		log_input("Input: [key_name(src)] could not use ability [entry.ability_id()] ([via]): [why].")
		return FALSE
	log_input("Input: [key_name(src)] used ability [entry.ability_id()] ([via]).")
	return entry.Trigger() ? TRUE : FALSE

/// Uses the ability in hotkey slot `slot` of this mob's list. FALSE when the slot is empty.
/mob/proc/use_ability_slot(slot)
	var/datum/action/entry = ability_in_slot(src, slot)
	if(!entry)
		log_input("Input: [key_name(src)] pressed ability slot [slot] with nothing in it.")
		return FALSE
	return use_ability_entry(entry, "slot [slot]")

/// The resources shown at the top of the tab: rows of list("name", "value", "max", "color") ("max" null for a number with no bar). A species, a
/// state or a mob type adds its own.
/mob/proc/ability_resources()
	return list()

/mob/living/ability_resources()
	. = ..()
	if(shadekin)
		. += list(shadekin.ability_resource())

/// The shadekin's energy as a resource row.
/datum/shadekin/proc/ability_resource()
	return list("name" = "Energy", "value" = round(shadekin_get_energy()), "max" = round(shadekin_get_max_energy()), "color" = "#9b6bff")

/// The shadekin's energy changed: the tab shows it (the push coalesces and waits a moment, so a steady gain is not a message per tick).
/datum/shadekin/proc/energy_changed(datum/act/A)
	owner?.abilities_changed()

// ---- The client's panel ----

/client/var/tmp/datum/ability_panel/ability_panel

/// The client's ability panel, made when it is first needed.
/proc/ability_panel_of(client/player)
	RETURN_TYPE(/datum/ability_panel)
	if(!player.ability_panel)
		rel_set(player, nameof(/client::ability_panel), new /datum/ability_panel(player))
	return player.ability_panel

/datum/ability_panel
	/// The client using the panel: a one-sided back view (the client owns the panel).
	var/client/owner

/datum/ability_panel/New(client/owner)
	rel_set(src, nameof(owner), owner)

CAPABILITIES(/datum/ability_panel)
	ref_one(nameof(owner))

/// The client using the panel.
/datum/ability_panel/proc/owner() as /client
	return owner

/// Sends the panel a moment from now; a push already waiting covers this one.
/datum/ability_panel/proc/queue_push()
	if(after_pending(src, "ability_push"))
		return
	after(src, ABILITY_PANEL_PUSH_DELAY, PROC_REF(push), key = "ability_push")

/// Sends the panel's data to the client's stat panel.
/datum/ability_panel/proc/push()
	var/client/player = owner()
	if(!player?.stat_panel?.is_ready())
		log_input("Input: Abilities tab data for [player ? key_name(player) : "nobody"] not sent (stat panel not ready).")
		return
	// A push whose data is what the tab shows (a resource moved less than its shown rounding) is dropped by the window.
	player.stat_panel.send_message("update_abilities", payload(player.mob, player), same_key = "update_abilities")

/// The panel's data: the entries in order, with the resources, for `user`. `viewer` (a client) gets the icons.
/datum/ability_panel/proc/payload(mob/user, client/viewer)
	return ability_panel_data(user, viewer)

/// The stat panel's message for this panel (a button in the Abilities tab): `action` and its arguments.
/datum/ability_panel/proc/act(action, list/params)
	var/mob/user = owner()?.mob
	if(!user)
		return FALSE
	switch(action)
		if("use")
			return user.use_ability_entry(handle_get(params["ref"]), "tab")
		if("reorder")
			return act_reorder(user, params["order"])
	log_input("Input: [key_name(user)] sent unknown Abilities tab action '[action]'.")
	return FALSE

/// The tab dropped an ability into a new place: `order` is the refs of every ability in the new order. It must be exactly the mob's abilities.
/// The order is saved by ability id (kept after the abilities the player does not have now) and logged.
/datum/ability_panel/proc/act_reorder(mob/user, list/order)
	var/list/picked = ability_order_from_refs(user, order)
	if(!picked)
		log_input("Input: [key_name(user)] sent an ability order that is not their abilities.")
		return FALSE
	var/datum/preferences/prefs = user.client?.prefs
	if(!prefs)
		return FALSE
	var/list/saved = ability_order_to_save(picked, prefs.read_preference(/datum/preference/ability_order))
	prefs.write_preference_by_type(/datum/preference/ability_order, saved)
	log_input("Input: [key_name(user)] reordered their abilities: [jointext(ability_ids_of(picked), ", ")].")
	queue_push()
	return TRUE

/// The ability ids of a list of abilities, in its order.
/proc/ability_ids_of(list/abilities)
	. = list()
	for(var/datum/action/entry as anything in abilities)
		. += entry.ability_id()

/// What the tab shows for `user`: "abilities" (entries in the player's order), "resources" and "slots". `viewer` is the client the icons are made for
/// (null: no icons, as in a test).
/proc/ability_panel_data(mob/user, client/viewer = null)
	var/list/entries = list()
	var/list/abilities = ordered_abilities(user)
	// The op entries' refusals come from the mob's op menu: read once for the push, not once per entry.
	var/list/menu_rows = null
	for(var/datum/action/op_ability/op_entry in abilities)
		menu_rows = op_menu(user, user, null)
		break
	var/slot = 0
	for(var/datum/action/entry as anything in abilities)
		slot++
		entries += list(ability_entry_data(entry, slot, viewer, menu_rows))
	return list("abilities" = entries, "resources" = user ? user.ability_resources() : list(), "slots" = ABILITY_HOTKEY_SLOTS)

/// One entry's data: the fields the tab shows.
/proc/ability_entry_data(datum/action/entry, slot, client/viewer = null, list/menu_rows = null)
	var/toggled = entry.ability_toggled()
	return list(
		"ref" = handle_text(handle_of(entry)), // as text: a handle past a million does not survive a number in json
		"id" = entry.ability_id(),
		"name" = entry.name,
		"desc" = entry.ability_desc(),
		"category" = entry.ability_category,
		"icon" = viewer ? ability_icon_src(entry, viewer) : null,
		"cost" = entry.ability_cost(),
		"cooldown" = entry.ability_cooldown_left(),
		"toggled" = isnull(toggled) ? null : (toggled ? TRUE : FALSE),
		"channel" = entry.ability_channel(),
		"refusal" = entry.ability_refusal(menu_rows),
		"slot" = slot <= ABILITY_HOTKEY_SLOTS ? slot : null,
	)

/// The source of the ability's icon for `viewer`: the target's own picture, or a state of the action's icon file. Both are a state of a
/// compiled-in icon file, cut and hashed once per (file, state, dir) (icon_file_asset_url()), not on every push of the tab.
/proc/ability_icon_src(datum/action/entry, client/viewer)
	var/atom/source = entry.ability_icon_source()
	if(source)
		if(ishuman(source) || !source.icon)
			return icon2html(source, viewer, sourceonly = TRUE)
		var/state = isnull(source.icon_state) ? initial(source.icon_state) : source.icon_state
		return icon_file_asset_url(source.icon, state, viewer, source.dir)
	if(!entry.button_icon)
		return null
	return icon_file_asset_url(entry.button_icon, entry.button_icon_state, viewer)
