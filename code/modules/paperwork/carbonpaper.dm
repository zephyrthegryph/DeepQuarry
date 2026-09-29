/obj/item/paper/carbon
	name = "paper"
	icon_state = "paper_stack"
	item_state = "paper"
	var/copied = 0
	var/iscopy = 0


DECLARE_APPEARANCE_PROC(/obj/item/paper/carbon, PROC_REF(appearance_overlays), list())
/obj/item/paper/carbon/appearance_overlays()
	. = list()
	if(iscopy)
		if(info)
			icon_state = "cpaper_words"
			return .
		icon_state = "cpaper"
	else if (copied)
		if(info)
			icon_state = "paper_words"
			return .
		icon_state = "paper"
	else
		if(info)
			icon_state = "paper_stack_words"
			return .
		icon_state = "paper_stack"



EXTEND_INTERACTIONS(/obj/item/paper/carbon, INTERACT_VERB("Remove carbon-copy", PROC_REF(carbon_paper_verb_remove_copy), REQ_IN_INVENTORY))

/// Old Remove carbon-copy verb.
/obj/item/paper/carbon/proc/carbon_paper_verb_remove_copy(mob/user, obj/item/held, datum/interaction/interaction)
	if (copied == 0)
		var/obj/item/paper/carbon/c = src
		var/copycontents = html_decode(c.info)
		var/obj/item/paper/carbon/copy = new /obj/item/paper/carbon (user.loc)
		// <font>
		copycontents = replacetext(copycontents, "<font face=\"[c.deffont]\" color=", "<font face=\"[c.deffont]\" nocolor=")	//state of the art techniques in action
		copycontents = replacetext(copycontents, "<font face=\"[c.crayonfont]\" color=", "<font face=\"[c.crayonfont]\" nocolor=")	//This basically just breaks the existing color tag, which we need to do because the innermost tag takes priority.
		copy.info += copycontents
		copy.info += "</font>"
		copy.name = "Copy - " + c.name
		copy.fields = c.fields
		copy.updateinfolinks()
		to_chat(user, span_notice("You tear off the carbon-copy!"))
		c.copied = 1
		copy.iscopy = 1
		copy.update_icon()
		c.update_icon()
	else
		to_chat(user, "There are no more carbon copies attached to this paper!")
