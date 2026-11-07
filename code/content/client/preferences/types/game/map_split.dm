// The main window's splitter between the map and the right-hand column (mainwindow.mainvsplit). BYOND lets the player drag it;
// the skin does not save it (a stale value would squeeze the map on the next connect), so the chat page reports where it was
// left (layout/mapsplit, tgui-panel/layout) and it is remembered here. 0 means the player never set one: the viewport fit
// (auto-fit-viewport, Fit Viewport) picks the width. The map control stretches to its pane, so the map rescales with it.

#define MAP_SPLIT_MIN 10
#define MAP_SPLIT_MAX 90
/// How long after a viewport fit a splitter report is the fit's own move, not the player's.
#define MAP_SPLIT_FIT_QUIET (6 SECONDS)

/datum/preference/numeric/map_split
	category = PREFERENCE_CATEGORY_GAME_PREFERENCES
	savefile_key = "MAP_SPLIT"
	savefile_identifier = PREFERENCE_PLAYER
	minimum = 0
	maximum = MAP_SPLIT_MAX

/datum/preference/numeric/map_split/create_default_value()
	return 0

/datum/preference/numeric/map_split/apply_to_client(client/client, value)
	client.map_split_apply()

/client
	/// The splitter percent this client was last put at or reported at.
	var/map_split_applied = 0
	COOLDOWN_DECLARE(map_split_fit_quiet)

/// Puts the main splitter where the player left it, once the chat page is up (login applies preferences before the skin has loaded).
/client/proc/map_split_apply()
	if(!prefs || !tgui_panel?.is_ready())
		return
	var/split = prefs.read_preference(/datum/preference/numeric/map_split)
	if(!split || split == map_split_applied)
		return
	split = clamp(round(split), MAP_SPLIT_MIN, MAP_SPLIT_MAX)
	map_split_applied = split
	winset(src, SKIN_MAIN_SPLIT, "splitter=[split]")
	log_tgui(src, "Map split restored to [split]%.", context = "chat_float")

/// The chat page measured the main splitter after a resize: remember it when the player moved it.
/client/proc/map_split_report(split)
	if(!isnum(split) || !prefs)
		return
	split = clamp(round(split), MAP_SPLIT_MIN, MAP_SPLIT_MAX)
	if(!COOLDOWN_FINISHED(src, map_split_fit_quiet))
		log_tgui(src, "Map split report [split]% ignored: a viewport fit is settling.", context = "chat_float")
		return
	if(split == prefs.read_preference(/datum/preference/numeric/map_split))
		return
	log_tgui(src, "Map split reported: [split]%.", context = "chat_float")
	map_split_applied = split // already there; the preference write must not move it again
	prefs.update_preference_by_type(/datum/preference/numeric/map_split, split)

/// A viewport fit is about to move the splitter itself: forget the saved width and ignore the reports its steps cause.
/client/proc/map_split_forget()
	COOLDOWN_START(src, map_split_fit_quiet, MAP_SPLIT_FIT_QUIET)
	map_split_applied = 0
	if(prefs?.read_preference(/datum/preference/numeric/map_split))
		prefs.update_preference_by_type(/datum/preference/numeric/map_split, 0)
SCHEMA(/client, map_split_applied, num())
