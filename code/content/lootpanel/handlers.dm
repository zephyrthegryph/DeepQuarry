/// On searchables change, either reset or update
/datum/lootpanel/proc/on_searchable_deleted(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/search_object/source = A.target

	own_take_member(src, nameof(searchables), source) // it is being deleted: out of our lists now
	rel_remove(src, nameof(to_image), source)

	var/datum/tgui/window = SStgui.get_open_ui(owner().mob, src)
#if !defined(UNIT_TESTS) // we dont want to delete searchables if we're testing
	if(isnull(window))
		reset_contents()
		return
#endif

	if(isturf(source.item()))
		populate_contents()
		return

	window?.send_update()
