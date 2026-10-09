/obj/effect/overmap
	name = "map object"
	icon = 'icons/obj/overmap.dmi'
	icon_state = "object"

	/// If set to TRUE will show up on ship sensors for detailed scans
	var/scannable
	/// Description for scans
	var/scanner_desc

	/// Icon file to use for skybox
	var/skybox_icon
	/// Icon state to use for skybox
	var/skybox_icon_state
	/// Shift from lower left corner of skybox
	var/skybox_pixel_x
	/// Shift from lower left corner of skybox
	var/skybox_pixel_y
	/// Cachey
	var/image/cached_skybox_image

	/// For showing to the pilot of the ship, so they see the 'real' appearance, despite others seeing the unknown ones
	var/image/real_appearance

	light_on = FALSE

	///~~If we need to render a map for cameras and helms for this object~~ basically can you look at and use this as a ship or station.
	var/render_map = FALSE

	// Stuff needed to render the map
	var/map_name
	var/atom/movable/screen/map_view/cam_screen
	/// All the plane masters that need to be applied.
	var/list/cam_plane_masters
	var/atom/movable/screen/background/cam_background

CAPABILITIES(/obj/effect/overmap)
	owns_one(nameof(cam_background), /atom/movable/screen/background)
	owns_one(nameof(cam_screen), /atom/movable/screen/map_view)
	owns_many(nameof(cam_plane_masters))

/obj/effect/overmap/Initialize(mapload)
	. = ..()
	if(!using_map.use_overmap)
		return INITIALIZE_HINT_QDEL

	if(render_map) // Initialize map objects
		map_name = "overmap_[REF(src)]_map"
		rel_set(src, nameof(cam_screen), new /atom/movable/screen/map_view)
		cam_screen.name = "screen"
		cam_screen.assigned_map = map_name
		cam_screen.del_on_map_removal = FALSE
		cam_screen.screen_loc = "[map_name]:1,1"

		for(var/atom/movable/screen/plane_master as anything in get_tgui_plane_masters())
			rel_add(src, nameof(cam_plane_masters), plane_master)

		for(var/atom/movable/screen/instance as anything in cam_plane_masters)
			instance.assigned_map = map_name
			instance.del_on_map_removal = FALSE
			instance.screen_loc = "[map_name]:CENTER"

		rel_set(src, nameof(cam_background), new /atom/movable/screen/background)
		cam_background.assigned_map = map_name
		cam_background.del_on_map_removal = FALSE
		update_screen()


// Its real appearance holder is detached before phase 4 drops it (DECLARE_REF(..., OWNED)).
/obj/effect/overmap/lifecycle_dematerialize()
	image_anchor(real_appearance, null)
	return ..()

//Overlay of how this object should look on other skyboxes
/obj/effect/overmap/proc/get_skybox_representation(zlevel)
	if(!cached_skybox_image)
		build_skybox_representation(zlevel)
	return cached_skybox_image

/// cached_skybox_image is a declared cache: expire_skybox_representation() raises
/// CHANGE_EXPLICIT and the object-model core nulls it.
/obj/effect/overmap/declared_cache_vars()
	var/list/L = ..()
	L = L ? L.Copy() : list()
	L["cached_skybox_image"] = CACHE_ON_CHANGE(CHANGE_EXPLICIT)
	return L

/obj/effect/overmap/proc/build_skybox_representation(zlevel)
	if(!skybox_icon)
		return
	var/image/I = image(icon = skybox_icon, icon_state = skybox_icon_state)
	if(isnull(skybox_pixel_x))
		skybox_pixel_x = rand(200,600)
	if(isnull(skybox_pixel_y))
		skybox_pixel_y = rand(200,600)
	I.pixel_x = skybox_pixel_x
	I.pixel_y = skybox_pixel_y
	scheduler_record_of(src) // join the object model so the declared cache is cleared on CHANGE_EXPLICIT
	cached_skybox_image = I

/obj/effect/overmap/proc/expire_skybox_representation()
	changed(src, CHANGE_EXPLICIT)

/obj/effect/overmap/proc/update_skybox_representation()
	expire_skybox_representation()
	build_skybox_representation()
	for(var/obj/effect/overmap/visitable/O in contents_of(loc))
		SSskybox.ready().rebuild_skyboxes(O.map_z)

/obj/effect/overmap/proc/get_scan_data(mob/user)
	var/dat = {"\[b\]Scan conducted at\[/b\]: [stationtime2text()] [stationdate2text()]\n\n[scanner_desc]"}

	return dat

/obj/effect/overmap/Crossed(obj/effect/overmap/visitable/other)
	return

/obj/effect/overmap/Uncrossed(obj/effect/overmap/visitable/other)
	return

/**
 * Updates the screen object, which is displayed on all connected helms
 */
/obj/effect/overmap/proc/update_screen()
	if(render_map)
		var/list/visible_turfs = list()
		for(var/turf/T in view(4, get_turf(src)))
			visible_turfs += T

		var/list/bbox = get_bbox_of_atoms(visible_turfs)
		var/size_x = bbox[3] - bbox[1] + 1
		var/size_y = bbox[4] - bbox[2] + 1

		cam_screen?.vis_contents = visible_turfs
		cam_background.icon_state = "clear"
		cam_background.fill_rect(1, 1, size_x, size_y)
		return TRUE
