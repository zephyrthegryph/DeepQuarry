/datum/prompt/text/shock_collar_ui_tag
	title = "Set Tag"
	question = "Tag text?"
	max_len = MAX_NAME_LEN
	name_text = TRUE
	timeout = 0

/datum/prompt/text/shock_collar_ui_tag/normalize(given)
	return istext(given) ? strip_name_tokens(given) : given

/datum/prompt/text/collar_tag
	question = "Tag text?"
	title = "Set tag"
	timeout = 0
	max_len = MAX_NAME_LEN
	name_text = TRUE
	encode = TRUE
	multiline = FALSE
	var/obj/item/captured_item
	var/item_expected = FALSE
	var/original_client_ckey
	var/tool_edit = FALSE
	var/erasemethod
	var/erasing
	var/writemethod

CAPABILITIES(/datum/prompt/text/collar_tag)
	ref_one(nameof(captured_item), /obj/item)

/datum/prompt/text/collar_tag/prepare(datum/act/A)
	. = ..()
	var/obj/item/item = captured_item
	rel_clear(src, nameof(captured_item))
	rel_set(src, nameof(captured_item), item)

/datum/prompt/text/collar_tag/proc/user_value()
	return original_client_ckey ? GLOB.directory[original_client_ckey] : answerer

/datum/prompt/text/collar_tag/proc/captures_gone()
	return QDELETED(answerer) || (original_client_ckey && !GLOB.directory[original_client_ckey]) || (item_expected && QDELETED(captured_item))

/datum/prompt/text/collar_tag/recheck_extra()
	. = ..()
	if(.)
		return
	if(captures_gone())
		return "gone"
	var/obj/item/clothing/accessory/collar/collar = owner
	if(tool_edit)
		var/mob/user = user_value()
		if(!(istype(user.get_active_hand(), captured_item)) || !(istype(user.get_inactive_hand(), collar)) || user.stat)
			return "the collar and writing tool must stay in the same hands"
	else if(collar.special_collar || (!istype(collar, /obj/item/clothing/accessory/collar/holo) && collar.writtenon))
		return "the collar tag cannot be edited by hand"
	return null
