/// Helper to open the panel
/datum/lootpanel/proc/open(turf/tile)
	rel_set(src, nameof(source_turf), tile)

#if !defined(OPENDREAM) && !defined(UNIT_TESTS)
	if(!notified)
		var/build = owner().byond_build
		var/version = owner().byond_version
		if(build < 515 || (build == 515 && version < 1635))
			to_chat(owner().mob, span_info("\
				<span class='bolddanger'>Your version of Byond doesn't support fast image loading.</span>\n\
				Detected: [version].[build]\n\
				Required version for this feature: <b>515.1635</b> or later.\n\
				Visit <a href=\"https://secure.byond.com/download\">BYOND's website</a> to get the latest version of BYOND.\n\
			"))

			notified = TRUE
#endif

	populate_contents()
	tgui_interact(owner().mob)


/// One step of icon generation, every 0.5 s while `imaging` (was SSlooting).
/// Parks when the queue is empty or the window has closed.
/datum/lootpanel/proc/image_step(datum/act/A)
	if(QDELETED(src) || !length(to_image))
		set_imaging(FALSE)
		return
	if(process_images())
		set_imaging(FALSE)

/**
 * Called on the loot icon lane while this panel has icons left to generate.
 * Iterates over to_image list to create icons, then removes them.
 * Returns boolean - whether this proc has finished the queue or not.
 */
/datum/lootpanel/proc/process_images()
	for(var/datum/search_object/index as anything in to_image)
		rel_remove(src, nameof(to_image), index)

		if(QDELETED(index) || index.icon)
			continue

		index.generate_icon(owner())

		if(TICK_CHECK)
			break

	var/datum/tgui/window = SStgui.get_open_ui(owner().mob, src)
	if(isnull(window))
		reset_contents()
		return TRUE

	window.send_update()

	return !length(to_image)
