// Admin panel href actions: CentCom / Syndicate headset replies and fax viewing / replies.

TOPIC_ACTION(/datum/admins, "CentComReply", PROC_REF(topic_centcomreply), TOPIC_REF("CentComReply", /mob/living))
TOPIC_ACTION(/datum/admins, "SyndicateReply", PROC_REF(topic_syndicatereply), TOPIC_REF("SyndicateReply", /mob/living/carbon/human))
TOPIC_ACTION(/datum/admins, "AdminFaxView", PROC_REF(topic_adminfaxview), TOPIC_REF("AdminFaxView", /obj/item))
TOPIC_ACTION(/datum/admins, "AdminFaxViewPage", PROC_REF(topic_adminfaxviewpage), TOPIC_NUM("AdminFaxViewPage"), TOPIC_REF("paper_bundle", /obj/item/paper_bundle))
TOPIC_ACTION(/datum/admins, "FaxReply", PROC_REF(topic_faxreply), TOPIC_REF("FaxReply", /mob), TOPIC_REF("originfax", /obj/machinery/photocopier/faxmachine), TOPIC_TEXT("replyorigin"))

/datum/admins/proc/topic_centcomreply(mob/user, list/args)
	var/mob/living/L = args["CentComReply"]
	if(!L.can_centcom_reply())
		to_chat(owner(), span_filter_adminlog("The person you are trying to contact does not have functional radio equipment."))
		return

	var/input = topic_ask(user, args, "a31", /datum/om/prompt/text, message = "Please enter a message to reply to [key_name(L)] via their headset.", title = "Outgoing message from CentCom")
	if(!input || QDELETED(L))
		return

	to_chat(owner(), span_filter_adminlog("You sent [input] to [L] via a secure channel."))
	log_admin("[owner()] replied to [key_name(L)]'s CentCom message with the message [input].")
	message_admins("[owner()] replied to [key_name(L)]'s CentCom message with: \"[input]\"")
	if(!isAI(L))
		to_chat(L, span_info("You hear something crackle in your headset for a moment before a voice speaks."))
	to_chat(L, span_info("Please stand by for a message from Central Command."))
	to_chat(L, span_info("Message as follows."))
	to_chat(L, span_notice("[input]"))
	to_chat(L, span_info("Message ends."))

/datum/admins/proc/topic_syndicatereply(mob/user, list/args)
	var/mob/living/carbon/human/H = args["SyndicateReply"]
	if(!istype(H.get_equipped_item(SLOT_ID_EAR_L), /obj/item/radio/headset) && !istype(H.get_equipped_item(SLOT_ID_EAR_R), /obj/item/radio/headset))
		to_chat(user, span_filter_adminlog("The person you are trying to contact is not wearing a headset"))
		return

	var/input = topic_ask(user, args, "a32", /datum/om/prompt/text, message = "Please enter a message to reply to [key_name(H)] via their headset.", title = "Outgoing message from a shadowy figure...")
	if(!input || QDELETED(H))
		return

	to_chat(owner(), span_filter_adminlog("You sent [input] to [H] via a secure channel."))
	log_admin("[owner()] replied to [key_name(H)]'s illegal message with the message [input].")
	to_chat(H, "<span class='filter_notice'>You hear something crackle in your headset for a moment before a voice speaks.  \
				\"Please stand by for a message from your benefactor.  Message as follows, agent. <b>\"[input]\"</b>  Message ends.\"</span>")

/datum/admins/proc/topic_adminfaxview(mob/user, list/args)
	var/obj/item/fax = args["AdminFaxView"]
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

/datum/admins/proc/topic_adminfaxviewpage(mob/user, list/args)
	var/page = args["AdminFaxViewPage"]
	var/obj/item/paper_bundle/bundle = args["paper_bundle"]
	if(!bundle || !isnum(page) || page < 1 || page > length(bundle.pages))
		return

	var/obj/item/page_item = bundle.pages[page]
	if(istype(page_item, /obj/item/paper))
		var/obj/item/paper/P = page_item
		P.show_content(owner(), 1)
	else if(istype(page_item, /obj/item/photo))
		var/obj/item/photo/H = page_item
		H.show(owner())

/datum/admins/proc/topic_faxreply(mob/user, list/args)
	var/mob/sender = args["FaxReply"]
	var/obj/machinery/photocopier/faxmachine/fax = args["originfax"]

	var/obj/item/paper/admin/P = new /obj/item/paper/admin(null) //hopefully the null loc won't cause trouble for us
	own_set(src, nameof(faxreply), P)

	rel_set(P, nameof(P.admindatum), src)
	P.origin = args["replyorigin"]
	rel_set(P, nameof(P.destination), fax)
	rel_set(P, nameof(P.sender), sender)

	P.adminbrowse(user)
