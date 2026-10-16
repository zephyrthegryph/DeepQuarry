// Optical labels are type configuration; active zoom is the actual borrowed native view.
STATIC_ENTRY(optical_view)

/proc/optical_view(device_name = null)
	return entry_make(ENTRY_OPTICAL_VIEW, null, list("device_name" = device_name))

/datum/type_trait/optical_view
	var/device_name = null

/datum/type_trait/optical_view/copy_values(datum/type_trait/optical_view/into)
	into.device_name = device_name

/datum/entry_engine/type_trait/optical_view
	kind = ENTRY_OPTICAL_VIEW
	trait_type = /datum/type_trait/optical_view
	publish_key = OPTICAL_VIEW_KEY
	base_type = /obj/item
	var_names = list("zoomdevicename" = "device_name")

READS_AS(/proc/optical_view_of, OPTICAL_VIEW_KEY)
/proc/optical_view_of(obj/item/I) as /datum/type_trait/optical_view
	READS_FROM(I)
	return type_trait_of(I, ENTRY_OPTICAL_VIEW)

/proc/item_zoom_active(obj/item/I)
	return !isnull(link_get(I, LK_ITEM_ZOOM_VIEW))
