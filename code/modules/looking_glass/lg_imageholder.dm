#define LG_IMAGE_SIZE 736

/obj/effect/landmark/looking_glass
	var/image/holding

	/// The viewing players, by ckey (clients are not entities; a disconnected one resolves to null).
	var/list/viewers

	var/lg_id //Area sets this for you

	mouse_opacity = 0

/obj/effect/landmark/looking_glass/Initialize(mapload)
	. = ..()
	viewers = list()

/obj/effect/landmark/looking_glass/proc/gain_viewer(client/C)
	if(!C)
		return
	if(C.ckey in viewers)
		log_mapping("Looking Glass [x],[y],[z] tried to add a duplicate viewer.")
	viewers |= C.ckey
	if(holding)
		show_to(C)

/obj/effect/landmark/looking_glass/proc/lose_viewer(client/C)
	if(!C)
		return
	if(!(C.ckey in viewers))
		log_mapping("Looking Glass [x],[y],[z] tried to remove a viewer it didn't have")
	viewers -= C.ckey
	if(holding)
		unshow_to(C)

/// The connected viewer clients (ckeys of disconnected players resolve to nothing).
/obj/effect/landmark/looking_glass/proc/viewer_clients()
	. = list()
	for(var/viewer_ckey in viewers)
		var/client/C = GLOB.directory[viewer_ckey]
		if(C)
			. += C

/obj/effect/landmark/looking_glass/proc/show_to(client/C)
	C?.images |= holding

/obj/effect/landmark/looking_glass/proc/unshow_to(client/C)
	C?.images -= holding

/obj/effect/landmark/looking_glass/proc/take_image(image/newimage)
	if(!istype(newimage))
		return

	if(holding)
		for(var/client in viewer_clients())
			unshow_to(client)

	holding = newimage
	newimage.plane = PLANE_LOOKINGGLASS_IMG
	newimage.blend_mode = BLEND_MULTIPLY
	newimage.appearance_flags = RESET_TRANSFORM
	newimage.mouse_opacity = 0
	newimage.pixel_y = newimage.pixel_x = (LG_IMAGE_SIZE/-2) + 16
	image_anchor(newimage, src)

	for(var/client in viewer_clients())
		show_to(client)

/obj/effect/landmark/looking_glass/proc/drop_image()
	if(!holding)
		return

	for(var/client in viewer_clients())
		unshow_to(client)

	image_anchor(holding, null)
	holding = null


#undef LG_IMAGE_SIZE

