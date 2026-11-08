/**
 * The Abilities tab's button pictures as one sprite sheet: every state of the icon files ability buttons draw from (each /datum/action
 * type's button_icon; the states an entry picks at runtime, a spell's or a changeling power's, are states of those files too). The sheet is
 * built at boot by the asset system (rust-g iconforge, kept across rounds by the smart cache) and sent to a client once, with its stat panel;
 * an entry then names its sprite ("icon_class" in ability_entry_data()) instead of an image of its own. A client gets the sheet with the
 * first Abilities push that has a picture from it (ability_panel.dm), not on join: a player with no such ability never downloads it. An entry whose picture is a target's
 * own (an item's) is not in the sheet and is sent on its own (icon_file_asset_url()), as is any entry while the client has not got the sheet.
 * Nothing waits for the sheet: a client that connected before it was built gets it when it is (realize_spritesheets()).
 */
/datum/asset/spritesheet_batched/ability_icons
	name = "ability_icons"

/datum/asset/spritesheet_batched/ability_icons/create_spritesheets()
	for(var/icon_file in ability_sheet_files())
		var/key = ability_sheet_file_key(icon_file)
		for(var/state in icon_states_fast(icon_file))
			insert_icon(ability_sprite_id(key, state), uni_icon(icon_file, state, SOUTH))

/datum/asset/spritesheet_batched/ability_icons/realize_spritesheets(yield)
	..()
	if(fully_generated)
		ability_sheet_ready(src)

/// The icon files the sheet packs: the button_icon of every ability type.
/proc/ability_sheet_files()
	. = list()
	for(var/datum/action/type as anything in typesof(/datum/action))
		var/icon_file = initial(type.button_icon)
		if(isfile(icon_file) && !(icon_file in .))
			. += icon_file

/// The sprite name prefix of an icon file in the sheet: its file name, letters and digits only ("ab_screenspells").
/proc/ability_sheet_file_key(icon_file)
	var/file_name = "[icon_file]"
	var/slash = findlasttext(file_name, "/")
	if(slash)
		file_name = copytext(file_name, slash + 1)
	var/dot = findtext(file_name, ".")
	if(dot)
		file_name = copytext(file_name, 1, dot)
	return "ab_[sanitize_css_class_name(file_name)]"

/// The sprite name of state `state` of the icon file whose key is `key`: a CSS class, so a character that is not a letter or a digit is written as
/// "_" and its code in hex (two states never share a name).
/proc/ability_sprite_id(key, state)
	var/static/regex/plain = regex(@"^[a-zA-Z0-9]*$")
	if(plain.Find(state))
		return "[key]-[state]"
	var/encoded = ""
	for(var/i in 1 to length(state))
		var/character = copytext(state, i, i + 1)
		var/code = text2ascii(character)
		var/kept = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122)
		encoded += kept ? character : "_[num2text(code, 2, 16)]"
	return "[key]-[encoded]"

/// The ability sheet, or null before the asset system made it. Never builds it: a caller that finds it not ready uses the single images.
/proc/ability_sheet()
	RETURN_TYPE(/datum/asset/spritesheet_batched/ability_icons)
	var/datum/asset/spritesheet_batched/ability_icons/sheet = GLOB.asset_datums[/datum/asset/spritesheet_batched/ability_icons]
	return sheet?.fully_generated ? sheet : null

/// Sends the sheet to `player`'s stat panel when both are ready and the panel has not got it. TRUE when the panel has it now.
/proc/ability_sheet_send(client/player)
	var/datum/asset/spritesheet_batched/ability_icons/sheet = ability_sheet()
	var/datum/tgui_window/panel = player?.stat_panel
	if(!sheet || !panel?.is_ready())
		return FALSE
	if(sheet in panel.sent_assets)
		return TRUE
	panel.send_asset(sheet)
	log_asset("Abilities sheet sent to [key_name(player)] ([length(sheet.sprites)] sprites).")
	return TRUE

/// The sheet was built: every stat panel that is up and has an ability that draws from it gets it, and its Abilities tab is sent again.
/proc/ability_sheet_ready(datum/asset/spritesheet_batched/ability_icons/sheet)
	for(var/client/player as anything in GLOB.clients)
		if(!player?.stat_panel?.is_ready() || (sheet in player.stat_panel.sent_assets) || !ability_sheet_wanted(player.mob))
			continue
		if(ability_sheet_send(player))
			player.mob?.abilities_changed()

/// Whether `user` has an ability whose button picture is in the sheet: only then is the sheet worth a client's download (a player with no
/// abilities, or only items' own pictures, never gets it).
/proc/ability_sheet_wanted(mob/user)
	for(var/datum/action/entry as anything in user?.actions)
		if(entry.button_icon && !entry.ability_icon_source())
			return TRUE
	return FALSE

/// The sheet sprite of `entry`'s button picture for `viewer` (its CSS classes), or null: the picture is a target's own (an item's), or the viewer's
/// stat panel has not got the sheet.
/proc/ability_icon_class(datum/action/entry, client/viewer)
	if(!viewer?.stat_panel || !entry.button_icon || entry.ability_icon_source())
		return null
	var/datum/asset/spritesheet_batched/ability_icons/sheet = ability_sheet()
	if(!sheet || !(sheet in viewer.stat_panel.sent_assets))
		return null
	return sheet.icon_class_name(ability_sprite_id(ability_sheet_file_key(entry.button_icon), entry.button_icon_state))
