/obj/machinery/computer/security/telescreen/bodycamera
	name = "bodycamera monitor"
	desc = "Damn, why do they never have anything interesting on these things? (Alt-click to toggle the display)"
	icon = 'icons/obj/entertainment_monitor.dmi'
	icon_state = "screen"
	icon_screen = null
	light_color = "#FFEEDB"
	light_range_on = 2
	network = list(NETWORK_BODYCAM)
	circuit = /obj/item/circuitboard/security/telescreen/bodycamera
	camera_datum_type = /datum/tgui_module/camera/bigscreen

	var/obj/item/radio/bradio = null
	var/obj/effect/overlay/vis/bpinboard
	var/showing
	var/the_camera

	var/enabled = TRUE // on or off

REGISTRY_MEMBERSHIP(/obj/machinery/computer/security/telescreen/bodycamera, REGISTRY_BODYCAMERA_SCREENS)

DECLARE_DEFAULT_CHILD(/obj/machinery/computer/security/telescreen/bodycamera, "bradio", /obj/item/radio)

/obj/machinery/computer/security/telescreen/bodycamera/Initialize(mapload)

	var/static/icon/mask = icon('icons/obj/entertainment_monitor.dmi', "mask")

	add_overlay("glass")

	bpinboard = GLOB.vis_overlays_service.add_vis_overlay(src, icon = icon, iconstate = "pinboard", layer = 0.1, add_appearance_flags = KEEP_TOGETHER, add_vis_flags = VIS_INHERIT_ID|VIS_INHERIT_PLANE, unique = TRUE)
	bpinboard.add_filter("screen cutter", 1, alpha_mask_filter(icon = mask))
	vis_contents += bpinboard

	. = ..()

	bradio.listening = TRUE
	bradio.broadcasting = FALSE
	bradio.set_frequency(BDCM_FREQ)
	bradio.canhear_range = world.view // Same as default sight range.
	power_change()

DECLARE_REF(/obj/machinery/computer/security/telescreen/bodycamera, "bpinboard", OWNED, null)
DECLARE_REF(/obj/machinery/computer/security/telescreen/bodycamera, "bradio", OWNED, null)

// stops showing its feed.
/obj/machinery/computer/security/telescreen/bodycamera/on_destroy(force)
	if(showing)
		stop_showing()
	..()

/obj/machinery/computer/security/telescreen/bodycamera/proc/bodycam_toggle()
	enabled = !enabled
	if(!enabled)
		stop_showing()
		bradio?.on = FALSE
	else if(operable())
		bradio?.on = TRUE

/obj/machinery/computer/security/telescreen/bodycamera/Click(location, control, params)
	var/list/modifiers = params2list(params)
	if(GLOB.input_router.click_is(modifiers, TYPE_TABLE_GET(GLOB.input_router, alternate_table), INPUT_ACTION_ALTERNATE))
		if(isliving(usr) && Adjacent(usr) && !usr.incapacitated())
			bodycam_toggle()
			visible_message("<b>[usr]</b> toggles [src] [enabled ? "on" : "off"].","You toggle [src] [enabled ? "on" : "off"].", runemessage = "click")
	//Changing click to only come into play when shift or alt clicking. These things are ANNOYING.
			return
	if(GLOB.input_router.click_is(modifiers, TYPE_TABLE_GET(GLOB.input_router, shift_table), INPUT_ACTION_INSPECT))
		attack_hand(usr)
		return
	..()

/obj/machinery/computer/security/telescreen/bodycamera/update_icon()
	return // NUH

/// Follows the camera while it shows one; otherwise it sleeps until it is shown one.
/obj/machinery/computer/security/telescreen/bodycamera/machine_step()
	if(!showing || !the_camera)
		stop_showing()
		return PROCESS_KILL
	var/atom/them = om_resolve(showing)
	var/obj/item/clothing/accessory/bodycam/bo_cam = om_resolve(the_camera)
	var/turf/here = get_turf(them)
	var/turf/there = get_turf(bo_cam)
	if(here != there)
		stop_showing()

/obj/machinery/computer/security/telescreen/bodycamera/proc/show_thing(atom/thing, obj/item/clothing/accessory/bodycam/other_thing)
	if(!enabled)
		return
	if(showing)
		stop_showing()
	if(has_stat(NOPOWER))
		return
	if(!thing || !other_thing)
		return
	the_camera = om_handle(other_thing)
	var/tries = 10
	var/atom/recursive_loc = thing
	while(--tries)
		recursive_loc = recursive_loc.loc
		if(!istype(recursive_loc, /atom/movable))
			break
	thing = recursive_loc // should get the topmost atom, which *should* be a mob, or a locker, or something that isnt just ~clothes~
	showing = om_handle(thing)
	MACHINE_WAKE(src)
	if(bpinboard)
		bpinboard.vis_contents = list(thing)

/obj/machinery/computer/security/telescreen/bodycamera/proc/stop_showing()
	// Reverse of the above
	if(bpinboard)
		bpinboard.vis_contents = null
	showing = null
	the_camera = null

/obj/machinery/computer/security/telescreen/bodycamera/proc/maybe_stop_showing(thingref)
	if(showing == thingref)
		stop_showing()

/obj/machinery/computer/security/telescreen/bodycamera/power_change()
	. = ..()
	if(has_stat(NOPOWER))
		bradio?.on = FALSE
		stop_showing()
	else if(enabled)
		bradio?.on = TRUE
