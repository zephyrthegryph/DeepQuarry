// Admin panel href actions: CentCom / Syndicate headset replies and fax viewing / replies.


MSG_DEF_SELF(admin_topic/centcom_unreachable, "The person you are trying to contact does not have functional radio equipment.")
MSG_DEF_SELF(admin_topic/syndicate_unreachable, "The person you are trying to contact is not wearing a headset.")

/datum/admins/proc/centcom_reply_possible(datum/act/op/A)
	var/mob/living/L = A.args["CentComReply"]
	return L?.can_centcom_reply()

/datum/admins/proc/centcom_reply_question(datum/act/op/A)
	return "Please enter a message to reply to [key_name(A.args["CentComReply"])] via their headset."

/datum/admins/proc/topic_centcomreply(datum/act/op/A, href_CentComReply)
	var/mob/living/L = href_CentComReply
	var/input = A.step_value("message")
	if(!input || QDELETED(L))
		return
	to_chat(owner(), span_filter_adminlog("You sent [input] to [L] via a secure channel."))
	log_admin("[owner()] replied to [key_name(L)]'s CentCom message with the message [input].")
	message_admins("[owner()] replied to [key_name(L)]'s CentCom message with: \"[input]\"")
	if(!istype(L, /mob/living/silicon/ai))
		to_chat(L, span_info("You hear something crackle in your headset for a moment before a voice speaks."))
	to_chat(L, span_info("Please stand by for a message from Central Command."))
	to_chat(L, span_info("Message as follows."))
	to_chat(L, span_notice("[input]"))
	to_chat(L, span_info("Message ends."))

/datum/admins/proc/syndicate_reply_possible(datum/act/op/A)
	var/mob/living/carbon/human/H = A.args["SyndicateReply"]
	return istype(H) && (istype(H.get_equipped_item(SLOT_ID_EAR_L), /obj/item/radio/headset) || istype(H.get_equipped_item(SLOT_ID_EAR_R), /obj/item/radio/headset))

/datum/admins/proc/syndicate_reply_question(datum/act/op/A)
	return "Please enter a message to reply to [key_name(A.args["SyndicateReply"])] via their headset."

/datum/admins/proc/topic_syndicatereply(datum/act/op/A, href_SyndicateReply)
	var/mob/living/carbon/human/H = href_SyndicateReply
	var/input = A.step_value("message")
	if(!input || QDELETED(H))
		return
	to_chat(owner(), span_filter_adminlog("You sent [input] to [H] via a secure channel."))
	log_admin("[owner()] replied to [key_name(H)]'s illegal message with the message [input].")
	to_chat(H, "<span class='filter_notice'>You hear something crackle in your headset for a moment before a voice speaks.  \
				\"Please stand by for a message from your benefactor.  Message as follows, agent. <b>\"[input]\"</b>  Message ends.\"</span>")

/datum/admins/proc/topic_adminfaxview(datum/act/op/A, href_adminfaxview)
	var/mob/user = A.actor
	var/obj/item/fax = href_adminfaxview
	if(istype(fax, /obj/item/paper))
		var/obj/item/paper/P = fax
		P.show_content(user, 1)
	else if(istype(fax, /obj/item/photo))
		var/obj/item/photo/H = fax
		H.show(user)
	else if(istype(fax, /obj/item/paper_bundle))
		// paper_bundle is TGUI now; open its window directly
		// rather than building an HTML page list.
		var/obj/item/paper_bundle/B = fax
		B.tgui_interact(user)
	else
		to_chat(user, span_warning("The faxed item is not viewable. This is probably a bug, and should be reported on the tracker: [fax.type]"))

/datum/admins/proc/topic_adminfaxviewpage(datum/act/op/A, href_adminfaxviewpage, href_paper_bundle)
	var/page = href_adminfaxviewpage
	var/obj/item/paper_bundle/bundle = href_paper_bundle
	if(!bundle || !isnum(page) || page < 1 || page > length(bundle.pages))
		return

	var/obj/item/page_item = bundle.pages[page]
	if(istype(page_item, /obj/item/paper))
		var/obj/item/paper/P = page_item
		P.show_content(owner(), 1)
	else if(istype(page_item, /obj/item/photo))
		var/obj/item/photo/H = page_item
		H.show(owner())

/datum/admins/proc/topic_faxreply(datum/act/op/A, href_faxreply, href_originfax, href_replyorigin)
	var/mob/user = A.actor
	var/mob/sender = href_faxreply
	var/obj/machinery/photocopier/faxmachine/fax = href_originfax

	var/obj/item/paper/admin/P = new /obj/item/paper/admin(null) //hopefully the null loc won't cause trouble for us
	rel_set(src, nameof(faxreply), P)

	rel_set(P, nameof(P.admindatum), src)
	P.origin = href_replyorigin
	rel_set(P, nameof(P.destination), fax)
	rel_set(P, nameof(P.sender), sender)

	P.adminbrowse(user)

/datum/prompt/text/admin_comms_topic
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/text/admin_comms_topic/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return null

/datum/prompt/text/admin_comms_topic/normalize(given)
	return istext(given) ? given : null

/datum/prompt/text/admin_comms_topic/refusal(given)
	return null
