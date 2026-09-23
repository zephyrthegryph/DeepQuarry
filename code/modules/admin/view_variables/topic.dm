//DO NOT ADD MORE TO THIS FILE.
//Use vv_do_topic() for datums!
/client/proc/view_var_Topic(href, href_list, hsrc)
	if(!check_rights_for(src, R_VAREDIT) || !holder.CheckAdminHref(href, href_list))
		return
	var/target = GET_VV_TARGET
	vv_do_basic(target, href_list, href)
	if(isdatum(target))
		var/datum/D = target
		D.vv_do_topic(href_list)
	else if(islist(target))
		vv_do_list(target, href_list)
	if(href_list["Vars"])
		var/datum/vars_target = locate(href_list["Vars"])
		if(href_list["special_varname"]) // Some special vars can't be located even if you have their ref, you have to use this instead
			vars_target = vars_target.vars[href_list["special_varname"]]
		debug_variables(vars_target)

//~CARN: for renaming mobs (updates their name, real_name, mind.name, their ID/PDA and datacore records).
	if(href_list["rename"])

		var/mob/M = locate(href_list["rename"]) in GLOB.mob_list
		if(!istype(M))
			to_chat(usr, "This can only be used on instances of type /mob", confidential = TRUE)
			return

		var/new_name = stripped_input(usr,"What would you like to name this mob?","Input a name",M.real_name,MAX_NAME_LEN)

		// If the new name is something that would be restricted by IC chat filters,
		// give the admin a warning but allow them to do it anyway if they want.
		//if(is_ic_filtered(new_name) || is_soft_ic_filtered(new_name) && tgui_alert(usr, "Your selected name contains words restricted by IC chat filters. Confirm this new name?", "IC Chat Filter Conflict", list("Confirm", "Cancel")) == "Cancel")
		//	return

		if( !new_name || !M )
			return

		message_admins("Admin [key_name_admin(usr)] renamed [key_name_admin(M)] to [new_name].")
		M.fully_replace_character_name(M.real_name,new_name)
		vv_update_display(M, "name", new_name)
		vv_update_display(M, "real_name", M.real_name || "No real name")

	else if(href_list["rotatedatum"])

		var/atom/A = locate(href_list["rotatedatum"])
		if(!istype(A))
			to_chat(usr, "This can only be done to instances of type /atom", confidential = TRUE)
			return

		switch(href_list["rotatedir"])
			if("right")
				A.set_dir(turn(A.dir, -45))
			if("left")
				A.set_dir(turn(A.dir, 45))
		vv_update_display(A, "dir", dir2text(A.dir))


	else if(href_list["adjustBody"] && href_list["mobToDamage"])
		var/mob/living/L = locate(href_list["mobToDamage"]) in GLOB.mob_list
		if(!istype(L) || !L.body)
			return
		var/action = href_list["adjustBody"]
		var/log_msg = L.vv_adjust_body(src, action)
		if(!log_msg)
			return
		if(QDELETED(L))
			to_chat(usr, "Mob doesn't exist anymore", confidential = TRUE)
			return
		log_msg = "[key_name(usr)] [log_msg] on [key_name(L)]"
		message_admins("[log_msg] ([ADMIN_LOOKUPFLW(L)])")
		log_admin(log_msg)
		admin_ticket_log(L, "<font color='blue'>[log_msg]</font>")
		vv_update_display(L, "vitality", "[round(L.vitality() * 100)]%")
		vv_update_display(L, "afflictions", "[LAZYLEN(L.body?.afflictions)]")
		vv_update_display(L, "oxygen_debt", "[round(L.oxygen_debt(), 0.1)]")

	else if(href_list["item_to_tweak"] && href_list["var_tweak"])

		var/obj/item/editing = locate(href_list["item_to_tweak"])
		if(!istype(editing) || QDELING(editing))
			return

		var/existing_val = -1
		switch(href_list["var_tweak"])
			if("injury_kind")
				existing_val = editing.injury_kind
			if("force")
				existing_val = editing.force
			//if("wound")
			//	existing_val = editing.wound_bonus
			//if("bare wound")
			//	existing_val = editing.exposed_wound_bonus
			else
				CRASH("Invalid var_tweak passed to item vv set var: [href_list["var_tweak"]]")

		var/new_val
		if(href_list["var_tweak"] == "injury_kind")
			var/list/kinds = list()
			for(var/kind in 1 to INJURY_KIND_COUNT)
				kinds[injury_kind_name(kind)] = kind
			var/picked = tgui_input_list(usr, "Enter the new injury kind for [editing]","Set Injury Kind", kinds, injury_kind_name(existing_val))
			new_val = picked ? kinds[picked] : null
		else
			new_val = tgui_input_number(usr, "Enter the new value for [editing]'s [href_list["var_tweak"]]","Set [href_list["var_tweak"]]", existing_val)
		if(isnull(new_val) || new_val == existing_val || QDELETED(editing) || !check_rights(R_VAREDIT))
			return

		switch(href_list["var_tweak"])
			if("injury_kind")
				editing.injury_kind = new_val
			if("force")
				editing.force = new_val
			//if("wound")
			//	editing.wound_bonus = new_val
			//if("bare wound")
			//	editing.exposed_wound_bonus = new_val

		message_admins("[key_name(usr)] set [editing]'s [href_list["var_tweak"]] to [new_val] (was [existing_val])")
		log_admin("[key_name(usr)] set [editing]'s [href_list["var_tweak"]] to [new_val] (was [existing_val])")
		vv_update_display(editing, href_list["var_tweak"], istext(new_val) ? uppertext(new_val) : new_val)

	//Finally, refresh if something modified the list.
	if(href_list[VV_HK_DATUM_REFRESH])
		var/datum/DAT = locate(href_list[VV_HK_DATUM_REFRESH])
		if(isdatum(DAT) || istype(DAT, /client) || islist(DAT))
			debug_variables(DAT)
