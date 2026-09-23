//Please use mob or src (not usr) in these procs. This way they can be called in the same fashion as procs.
/client/verb/wiki(query as text)
	set name = "wiki"
	set desc = "Type what you want to know about.  This will open the wiki on your web browser."
	set category = "OOC.Resources"
	if(CONFIG_GET(string/wikiurl))
		if(query)
			if(CONFIG_GET(string/wikisearchurl))
				var/output = replacetext(CONFIG_GET(string/wikisearchurl), "%s", url_encode(query))
				src << link(output)
			else
				to_chat(src, span_warning(" The wiki search URL is not set in the server configuration."))
		else
			src << link(CONFIG_GET(string/wikiurl))
	else
		to_chat(src, span_warning("The wiki URL is not set in the server configuration."))
		return

/client/verb/forum()
	set name = "forum"
	set desc = "Visit the forum."
	set hidden = 1
	if(CONFIG_GET(string/forumurl))
		if(tgui_alert(usr, "This will open the forum in your browser. Are you sure?","Visit Website",list("Yes","No")) != "Yes")
			return
		src << link(CONFIG_GET(string/forumurl))
	else
		to_chat(src, span_warning("The forum URL is not set in the server configuration."))
		return

/client/verb/rules()
	set name = "Rules"
	set desc = "Show Server Rules."
	set hidden = 1

	if(CONFIG_GET(string/rulesurl))
		if(tgui_alert(usr, "This will open the rules in your browser. Are you sure?","Visit Website",list("Yes","No")) != "Yes")
			return
		src << link(CONFIG_GET(string/rulesurl))
	else
		to_chat(src, span_danger("The rules URL is not set in the server configuration."))
	return

/client/verb/map()
	set name = "Map"
	set desc = "See the map."
	set hidden = 1

	if(CONFIG_GET(string/mapurl))
		if(tgui_alert(usr, "This will open the map in your browser. Are you sure?","Visit Website",list("Yes","No")) != "Yes")
			return
		src << link(CONFIG_GET(string/mapurl))
	else
		to_chat(src, span_danger("The map URL is not set in the server configuration."))
	return

/client/verb/github()
	set name = "GitHub"
	set desc = "Visit the GitHub"
	set hidden = 1

	if(CONFIG_GET(string/githuburl))
		if(tgui_alert(usr, "This will open the GitHub in your browser. Are you sure?","Visit Website",list("Yes","No")) != "Yes")
			return
		src << link(CONFIG_GET(string/githuburl))
	else
		to_chat(src, span_danger("The GitHub URL is not set in the server configuration."))
	return

/client/verb/discord()
	set name = "Discord"
	set desc = "Visit the discord"
	set hidden = 1

	if(CONFIG_GET(string/discordurl))
		if(tgui_alert(usr, "This will open the Discord in your browser. Are you sure?","Visit Website",list("Yes","No")) != "Yes")
			return
		src << link(CONFIG_GET(string/discordurl))
	else
		to_chat(src, span_danger("The Discord URL is not set in the server configuration."))
	return

/client/verb/patreon()
	set name = "Patreon"
	set desc = "Visit the patreon"
	set hidden = 1

	if(CONFIG_GET(string/patreonurl))
		if(tgui_alert(usr, "This will open the Patreon in your browser. Are you sure?","Visit Website",list("Yes","No")) != "Yes")
			return
		src << link(CONFIG_GET(string/patreonurl))
	else
		to_chat(src, span_danger("The Patreon URL is not set in the server configuration."))
	return

