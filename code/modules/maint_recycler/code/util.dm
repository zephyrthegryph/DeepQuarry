/datum/asset/simple/maint_recycler
	assets = list(
		"recycle.gif" = 'code/modules/maint_recycler/tgui/recycle.gif',
		"logo.png" = 'code/modules/maint_recycler/tgui/logo.png',
	)

/obj/effect/overlay/recycler
	anchored = TRUE
	plane = FLOAT_PLANE
	layer = FLOAT_LAYER //over the inserted items.
	vis_flags = VIS_INHERIT_ID
	appearance_flags = KEEP_TOGETHER | LONG_GLIDE | PASS_MOUSE


/datum/asset/spritesheet_batched/maint_vendor
	name = "MaintVendor"

/datum/asset/spritesheet_batched/maint_vendor/create_spritesheets()
	insert_all_icons("", 'code/modules/maint_recycler/icons/vendor_entries.dmi', prefix_with_dirs = FALSE)


GLOBAL_LIST_EMPTY(recycler_vendor_locations)

GLOBAL_LIST_EMPTY(recycler_locations)

/obj/effect/recycler_beacon
	icon = 'code/modules/maint_recycler/icons/maint_recycler.dmi'
	icon_state = "marker"
	invisibility = INVISIBILITY_ABSTRACT
	mouse_opacity = 0
	density = 0
	anchored = 1

CAPABILITIES(/obj/effect/recycler_beacon)
	map_resolver(GLOBAL_PROC_REF(resolve_recycler_beacon))

/// The map resolver of recycler beacons: a row in GLOB.recycler_locations.
/proc/resolve_recycler_beacon(atom/loc, path, list/varedits)
	GLOB.recycler_locations |= get_turf(loc)
	return TRUE

/obj/effect/recycler_vendor_beacon
	icon = 'code/modules/maint_recycler/icons/maint_vendor.dmi'
	icon_state = "marker"
	invisibility = INVISIBILITY_ABSTRACT
	pixel_x = -8
	mouse_opacity = 0
	density = 0
	anchored = 1

/obj/effect/recycler_vendor_beacon/Initialize(mapload)
	GLOB.recycler_vendor_locations |= get_turf(src)
	. = ..()
