/// Adds the item to searchables and to_image (if needed)
/datum/lootpanel/proc/add_to_index(datum/search_object/index)
	observe(index, /datum/notice/qdeleting, src, then(PROC_REF(on_searchable_deleted)))
	rel_add(src, nameof(searchables), index)
	if(isnull(index.icon))
		rel_add(src, nameof(to_image), index)


/// Used to populate searchables and start generating if needed
/datum/lootpanel/proc/populate_contents()
	if(length(searchables))
		reset_contents()

	// Add source turf first
	var/datum/search_object/source = new(owner(), source_turf())
	add_to_index(source)

	for(var/atom/thing as anything in source_turf().contents)
		// validate
		if(!istype(thing))
			stack_trace("Non-atom in the contents of [source_turf()]!")
			continue
		if(QDELETED(thing))
			continue
		if(thing.mouse_opacity == MOUSE_OPACITY_TRANSPARENT)
			continue
		// if(thing.IsObscured())
		// 	continue
		if(thing.invisibility > owner().mob.see_invisible)
			continue

		// convert
		var/datum/search_object/index = new(owner(), thing)
		add_to_index(index)

	var/datum/tgui/window = SStgui.get_open_ui(owner().mob, src)
	window?.send_update()

	if(length(to_image))
		set_imaging(TRUE) // icon generation (was SSlooting): misc.dm process_images()


/// For: Resetting to empty. Ignores the searchable qdel event
/datum/lootpanel/proc/reset_contents()
	for(var/datum/search_object/index as anything in searchables)
		if(!QDELETED(index))
			unobserve(index, /datum/notice/qdeleting, src)
	// the search objects are ours: deleting them also empties to_image (a relation list)
	rel_clear(src, nameof(searchables))
