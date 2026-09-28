//Not using datum.vv_do_topic for very basic/low level debug things, incase the datum's vv_do_topic is runtiming/whatnot.
/client/proc/vv_do_basic(datum/target, href_list)
	var/target_var = GET_VV_VAR_TARGET
	if(check_rights(R_VAREDIT))
		if(target_var)
			if(href_list[VV_HK_BASIC_EDIT])
				if(!modify_variables(target, target_var, 1))
					return
				switch(target_var)
					if("name")
						vv_update_display(target, "name", "[target]")
					if("dir")
						var/atom/A = target
						if(istype(A))
							vv_update_display(target, "dir", dir2text(A.dir) || A.dir)
					if("ckey")
						var/mob/living/L = target
						if(istype(L))
							vv_update_display(target, "ckey", L.ckey || "No ckey")
					if("real_name")
						var/mob/living/L = target
						if(istype(L))
							vv_update_display(target, "real_name", L.real_name || "No real name")

			if(href_list[VV_HK_BASIC_CHANGE])
				modify_variables(target, target_var, 0)
			if(href_list[VV_HK_BASIC_MASSEDIT])
				cmd_mass_modify_object_variables(target, target_var)
	if(check_rights(R_ADMIN, FALSE))
		if(href_list[VV_HK_EXPOSE])
			var/value = vv_get_value(VV_CLIENT, key = "expose")
			if (value["class"] != VV_CLIENT)
				return
			var/client/C = value["value"]
			if (!C)
				return
			if(!target)
				to_chat(usr, span_warning("The object you tried to expose to [C] no longer exists (nulled or hard-deled)"), confidential = TRUE)
				return
			message_admins("[key_name_admin(usr)] Showed [key_name_admin(C)] a <a href='byond://?_src_=vars;datumrefresh=[REF(target)]'>VV window</a>")
			log_admin("Admin [key_name(usr)] Showed [key_name(C)] a VV window of a [target]")
			to_chat(C, "[holder.fakekey ? "an Administrator" : "[usr.client.key]"] has granted you access to view a View Variables window", confidential = TRUE)
			C.debug_variables(target)
	if(check_rights(R_DEBUG))
		if(href_list[VV_HK_DELETE])
			usr.client.admin_delete(target)
			if (isturf(target)) // show the turf that took its place
				usr.client.debug_variables(target)
				return

	if(href_list[VV_HK_MARK])
		usr.client.mark_datum(target)
	if(href_list[VV_HK_TAG])
		usr.client.tag_datum(target)
	if(href_list[VV_HK_ADDCOMPONENT])
		if(!check_rights(R_DEBUG))
			return
		var/list/names = sortList(subtypesof(/datum/om/behaviour), GLOBAL_PROC_REF(cmp_typepaths_asc))
		var/result = flow_ask(mob, "behaviour:add", list("kind" = "list", "message" = "Choose an OM behaviour to attach", "title" = "Attach Behaviour", "choices" = names))
		if(isnull(result) || !usr)
			return
		if(QDELETED(target))
			to_chat(usr, "That thing doesn't exist anymore!", confidential = TRUE)
			return
		om_attach(target, result)
		log_admin("[key_name(usr)] has attached behaviour [result] to [key_name(target)].")
		message_admins(span_notice("[key_name_admin(usr)] has attached behaviour [result] to [key_name_admin(target)]."))
	if(href_list[VV_HK_REMOVECOMPONENT] || href_list[VV_HK_MASS_REMOVECOMPONENT])
		if(!check_rights(R_DEBUG))
			return
		var/mass_remove = href_list[VV_HK_MASS_REMOVECOMPONENT]
		var/list/names = list()
		for(var/datum/om/behaviour/B as anything in target.om_rec?.att)
			names += B.type
		if(!length(names))
			to_chat(usr, "[target] has no OM behaviours attached.")
			return
		var/path = flow_ask(mob, "behaviour:remove", list("kind" = "list", "message" = "Choose an OM behaviour to detach", "title" = "Detach Behaviour", "choices" = names))
		if(isnull(path) || !usr)
			return
		if(QDELETED(target))
			to_chat(usr, "That thing doesn't exist anymore!")
			return
		var/list/targets_to_remove_from = list(target)
		if(mass_remove)
			var/method = vv_subtype_prompt(target.type, "behaviour")
			if(isnull(method))
				return
			if(flow_ask(mob, "behaviour:mass", list("message" = "Are you sure you want to mass-detach [path] on [target.type]?", "title" = "Mass Detach Confirmation", "choices" = list("Yes", "No"))) != "Yes")
				return
			targets_to_remove_from = get_all_of_type(target.type, method)
		for(var/datum/target_to_remove_from as anything in targets_to_remove_from)
			om_detach(target_to_remove_from, path)
		message_admins(span_notice("[key_name_admin(usr)] has [mass_remove? "mass " : ""]detached behaviour [path] from [mass_remove? target.type : key_name_admin(target)]."))

	if(href_list[VV_HK_CALLPROC])
		return SSadmin_verbs.dynamic_invoke_verb(usr, /datum/admin_verb/call_proc_datum, target)
