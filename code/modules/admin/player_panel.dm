
/datum/admins/proc/player_panel_new(client/user)//The new one
	// DQEdit Start — fully structured TGUI PlayerPanel. Replaces the
	// 320-line HTML+JS table with a React panel that has native
	// filtering / sorting and structured action dispatch (see
	// code/modules/admin/player_panel_tgui.dm).
	open_player_panel_tgui(user)
	return
	// DQEdit End


// DQEdit Start — player_panel_old now redirects to the structured
// PlayerPanel; the legacy HTML body is gone. Both the "Player Panel" and
// "Player Panel New" admin verbs land in the same place.
/datum/admins/proc/player_panel_old(client/user)
	if (!check_rights_for(user, R_HOLDER))
		return
	open_player_panel_tgui(user)
// DQEdit End



/datum/admins/proc/check_antagonists(client/user)
	// DQEdit — structured TGUI RoundStatusPanel (see
	// code/modules/admin/round_status_panel.dm).
	open_round_status_panel(user.mob)
