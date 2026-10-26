/**
 * Inserts the target_datum into [/datum/admins/var/tagged_datums], for later reference.
 *
 * Arguments:
 * * target_datum - The datum you want to create a tag for
 */
/datum/admins/proc/add_tagged_datum(datum/target_datum)
	if(LAZYFIND(tagged_datums, target_datum))
		to_chat(owner(), span_warning("[target_datum] is already tagged!"))
		return

	rel_add(src, nameof(tagged_datums), target_datum)
	observe(target_datum, /datum/notice/qdeleting, src, then(PROC_REF(handle_tagged_del)))
	to_chat(owner(), span_notice("[target_datum] has been tagged."))

/// Get ahead of the curve with deleting
/datum/admins/proc/handle_tagged_del(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = A.target

	if(owner())
		to_chat(owner(), span_boldnotice("Tagged datum [source] ([source.type]) has been deleted."))
	remove_tagged_datum(source, silent = TRUE)

/**
 * Attempts to remove the specified datum from [/datum/admins/var/tagged_datums] if it exists
 *
 * Arguments:
 * * target_datum - The datum you want to remove from the tagged_datums list
 * * silent - If TRUE, won't print messages to the owner's chat
 */
/datum/admins/proc/remove_tagged_datum(datum/target_datum, silent=FALSE)
	if(!istype(target_datum))
		return

	if(LAZYFIND(tagged_datums, target_datum))
		rel_remove(src, nameof(tagged_datums), target_datum)
		if(!silent)
			to_chat(owner(), span_notice("[target_datum] has been untagged."))
	else if(!silent)
		to_chat(owner(), span_warning("[target_datum] was not already tagged."))

ADMIN_VERB(display_tags, R_ADMIN, "View Tags", "Display all of the tagged datums.", ADMIN_CATEGORY_GAME)
	user.holder.dq_open_tag_menu(user.mob)
