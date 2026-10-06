GLOBAL_VAR_INIT(checked_for_inactives, FALSE)
GLOBAL_VAR_INIT(inactive_keys, "None<br>")

ADMIN_VERB(check_customitem_activity, R_ADMIN|R_MOD|R_SERVER, "Check activity of players with custom items", "Allows you to investigate custom item activity.", ADMIN_CATEGORY_INVESTIGATE)
	var/dat = span_bold("Inactive players with custom items") + "<br>"
	dat += "<br>"
	dat += "The list below contains players with custom items that have not logged\
		in for the past two months, or have not logged in since this system was implemented.\
		This system requires the feedback SQL database to be properly setup and linked.<br>"
	dat += "<br>"
	dat += "Populating this list is done automatically, but must be manually triggered on a per\
		round basis. Populating the list may cause a lag spike, so use it sparingly.<br>"
	dat += "<hr>"
	if(GLOB.checked_for_inactives)
		dat += GLOB.inactive_keys
		dat += "<hr>"
		dat += "This system was implemented on March 1 2013, and the database a few days before that. Root server access is required to add or disable access to specific custom items.<br>"
	else
		dat += "<a href='byond://?src=\ref[user];_src_=holder;[HrefToken()];populate_inactive_customitems=1'>Populate list (requires an active database connection)</a><br>"

	// structured TGUI AdminReport; populate_inactive link forwards
	// through dispatch_forwarded_topic to the admin holder Topic.
	dq_admin_report_html(user.mob, "Inactive Custom Items", dat, user.holder)

/proc/populate_inactive_customitems_list(client/C)

	if(GLOB.checked_for_inactives)
		return

	if(!SSdbcore.IsConnected())
		return

	//grab all ckeys associated with custom items
	var/list/ckeys_with_customitems = list()

	var/file = file2text("config/custom_items.txt")
	var/lines = splittext(file, "\n")

	for(var/line in lines)
		// split & clean up
		var/list/Entry = splittext(line, ":")
		for(var/i = 1 to Entry.len)
			Entry[i] = trim(Entry[i])

		if(Entry.len < 1)
			continue

		var/cur_key = Entry[1]
		if(!ckeys_with_customitems.Find(cur_key))
			ckeys_with_customitems.Add(cur_key)

	if(!ckeys_with_customitems.len)
		populate_inactive_customitems_finish(list(), C?.ckey)
		return
	//run a query to get all ckeys inactive for over 2 months (io_job: the answer continues below)
	io_job(null, /datum/io_backend/sql, "SELECT ckey, lastseen FROM erro_player WHERE datediff(Now(), lastseen) > 60", null, /proc/populate_inactive_customitems_inactive, ckeys_with_customitems, C?.ckey)

/// io_job() callback: the long-inactive players are known; now check which of the rest have any
/// database entry at all.
/proc/populate_inactive_customitems_inactive(list/result, error, list/ckeys_with_customitems, asker_ckey)
	var/list/inactive_ckeys = list()
	for(var/list/row as anything in result?["rows"])
		var/cur_ckey = row[1]
		//if the ckey has a custom item attached, output it
		if(ckeys_with_customitems.Find(cur_ckey))
			ckeys_with_customitems.Remove(cur_ckey)
			inactive_ckeys[cur_ckey] = "last seen on [row[2]]"
	if(!ckeys_with_customitems.len)
		populate_inactive_customitems_finish(inactive_ckeys, asker_ckey)
		return
	//if there are ckeys left over, check whether they have a database entry at all (one query)
	var/list/placeholders = list()
	var/list/arguments = list()
	for(var/i in 1 to length(ckeys_with_customitems))
		placeholders += ":k[i]"
		arguments["k[i]"] = ckeys_with_customitems[i]
	io_job(null, /datum/io_backend/sql, "SELECT ckey FROM erro_player WHERE ckey IN ([jointext(placeholders, ",")])", arguments, /proc/populate_inactive_customitems_known, ckeys_with_customitems, inactive_ckeys, asker_ckey)

/// io_job() callback: whoever isn't in the player table has no database entry.
/proc/populate_inactive_customitems_known(list/result, error, list/ckeys_with_customitems, list/inactive_ckeys, asker_ckey)
	var/list/known = list()
	for(var/list/row as anything in result?["rows"])
		known[row[1]] = TRUE
	for(var/cur_ckey in ckeys_with_customitems)
		if(!known[cur_ckey])
			inactive_ckeys += cur_ckey
	populate_inactive_customitems_finish(inactive_ckeys, asker_ckey)

/proc/populate_inactive_customitems_finish(list/inactive_ckeys, asker_ckey)
	if(inactive_ckeys.len)
		GLOB.inactive_keys = ""
		for(var/cur_key in inactive_ckeys)
			if(inactive_ckeys[cur_key])
				GLOB.inactive_keys += span_bold("[cur_key]") + " - [inactive_ckeys[cur_key]]<br>"
			else
				GLOB.inactive_keys += "[cur_key] - no database entry<br>"

	GLOB.checked_for_inactives = TRUE
	var/client/C = asker_ckey ? GLOB.directory[asker_ckey] : null
	if(C && check_rights_for(C, R_ADMIN|R_MOD|R_SERVER))
		SSadmin_verbs.dynamic_invoke_verb(C, /datum/admin_verb/check_customitem_activity)
