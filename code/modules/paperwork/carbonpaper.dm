/obj/item/paper/carbon
	name = "paper"
	icon_state = "paper_stack"
	item_state = "paper"
	var/copied = 0
	var/iscopy = 0


TRACKED(/obj/item/paper/carbon, copied)
TRACKED(/obj/item/paper/carbon, iscopy)

/obj/item/paper/carbon/look_parts(datum/look/look)
	if(iscopy)
		look.state(info ? "cpaper_words" : "cpaper")
	else if(copied)
		look.state(info ? "paper_words" : "paper")
	else
		look.state(info ? "paper_stack_words" : "paper_stack")



CAPABILITIES(/obj/item/paper/carbon)
	op("carbon_paper_verb_remove_copy", menu(), label("Remove carbon-copy"), needs(carried()), then(PROC_REF(carbon_paper_verb_remove_copy)))

/// Old Remove carbon-copy verb.
/obj/item/paper/carbon/proc/carbon_paper_verb_remove_copy(datum/act/op/A)
	var/mob/user = A.actor
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
		c.set_copied(1)
		copy.set_iscopy(1)
		changed(copy)
	else
		to_chat(user, "There are no more carbon copies attached to this paper!")
