/datum/admins/proc/CheckAdminHref(href, href_list, mob/user)
	var/auth = href_list["admin_token"]
	. = auth && (auth == href_token || auth == GLOB.href_token)
	if(.)
		return
	var/msg = !auth ? "no" : "a bad"
	message_admins("[key_name_admin(user)] clicked an href with [msg] authorization key!")

	/* Debug code in case one needs to dig missing token HREFS
	var/debug_admin_hrefs = TRUE // Remove once everything is converted over
	if(debug_admin_hrefs)
		message_admins("Debug mode enabled, call not blocked. Please ask your coders to review this round's logs.")
		log_world("UAH: [href]")
		return TRUE
	*/

	log_admin("[key_name(user)] clicked an href with [msg] authorization key! [href]")

// The admin panel's href actions are topic ops of /datum/admins (its CAPABILITIES block, code/modules/admin/holder2.dm), their handlers split by area under
// code/modules/admin/topic/. This gate runs before every one of them.
/datum/admins/topic_allowed(mob/user, list/href_list)
	. = ..()
	if(!.)
		return
	if(!user?.client || user.client != owner() || !check_rights_for(user.client, 0))
		log_admin("[key_name(user)] tried to use the admin panel without authorization.")
		message_admins("[user?.key] has attempted to override the admin panel!")
		return FALSE
	if(!CheckAdminHref(list2params(href_list), href_list, user))
		return FALSE

/// A trusted in-game panel (tgui) running one of this holder's href actions for `user`:
/// the admin token is supplied, every row's rights and the owner check still apply.
/datum/admins/proc/topic_internal(mob/user, list/href_list)
	var/list/trusted = href_list.Copy()
	trusted["admin_token"] = href_token
	return topic_dispatch(src, user, trusted)

/mob/living/proc/can_centcom_reply()
	return 0

/mob/living/carbon/human/can_centcom_reply()
	return istype(get_equipped_item(SLOT_ID_EAR_L), /obj/item/radio/headset) || istype(get_equipped_item(SLOT_ID_EAR_R), /obj/item/radio/headset)

/mob/living/silicon/ai/can_centcom_reply()
	return common_radio != null && !check_unable(2)

/proc/extra_admin_link(atom/target, source)
	if(isobserver(target))
		var/mob/observer/dead/ghost = target
		if(ghost.mind && ghost.mind.current)
			return "|<A href='byond://?[source];[HrefToken(TRUE)];adminplayerobservejump=\ref[ghost.mind.current]'>BDY</A>"
		return
	if(ismob(target))
		var/mob/M = target
		var/mob/observer/eye/eyeobj = M?.active_eye()
		if(M.client && eyeobj)
			return "|<A href='byond://?[source];[HrefToken(TRUE)];adminplayerobservejump=\ref[eyeobj]'>EYE</A>"

/proc/admin_jump_link(atom/target, source)
	if(!target) return
	// The way admin jump links handle their src is weirdly inconsistent...
	if(istype(source, /datum/admins))
		source = "src=\ref[source]"
	else
		source = "_src_=holder"

	. = "<A href='byond://?[source];[HrefToken(TRUE)];adminplayerobservejump=\ref[target]'>JMP</A>"
	. += extra_admin_link(target, source)
