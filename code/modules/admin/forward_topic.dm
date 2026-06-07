// Forwarded byond:// link dispatch — used by structured TGUI panels
// (AdminReport, PermissionsPanel, ViewVariables, etc.) to route the
// `forward_topic` act produced by HtmlRenderer to the appropriate
// Topic handler, mirroring what `world.Topic` / `client.Topic` would
// do for the same href in the legacy browser.
//
// Lifted out of the deleted admin_log_viewer.dm so the deprecated
// catchall could go away while every structured panel that still
// renders some HTML body keeps working.

/proc/dispatch_forwarded_topic(mob/user, datum/host, href_str)
	if(!length(href_str))
		return
	var/list/href_list = params2list(href_str)
	switch(href_list["_src_"])
		if("holder")
			var/datum/admins/holder = user?.client?.holder
			if(holder)
				holder.Topic(href_str, href_list)
			return
		if("usr")
			if(user)
				user.Topic(href_str, href_list)
			return
		if("prefs")
			if(user?.client?.prefs)
				user.client.prefs.process_link(user, href_list)
			return
		if("vars")
			if(user?.client)
				user.client.view_var_Topic(href_str, href_list, host)
			return
	if(host)
		host.Topic(href_str, href_list)

// Forward a queryString-style href to /datum/admins/Topic with _src_=holder set,
// mirroring how the legacy admin browse() panels routed their links. Used by
// structured admin panels (PermissionsPanel, EditPlayer, AdminNewscaster, …)
// when an action's only job is to dispatch into the existing admin Topic.
/proc/forward_holder_topic(datum/admins/holder, qs, list/extra_params = null)
	if(!holder)
		return
	var/list/href_list = params2list(qs)
	href_list["_src_"] = "holder"
	if(extra_params)
		for(var/k in extra_params)
			href_list[k] = extra_params[k]
	holder.Topic(qs, href_list)
