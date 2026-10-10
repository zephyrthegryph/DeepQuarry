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

	var/enabled = TRUE // on or off

REGISTRY_MEMBERSHIP(/obj/machinery/computer/security/telescreen/bodycamera, REGISTRY_BODYCAMERA_SCREENS)

/// What it shows (the wearer, or whatever holds them) and the bodycam feeding it; it follows them while both are set.
/obj/machinery/computer/security/telescreen/bodycamera/var/atom/showing
/datum/scheduler_field_definition/obj/machinery/computer/security/telescreen/bodycamera/showing
	of = /obj/machinery/computer/security/telescreen/bodycamera
	field = "showing"
	channel = CHANGE_MACHINE_SETTINGS
/obj/machinery/computer/security/telescreen/bodycamera/var/obj/item/clothing/accessory/bodycam/the_camera
/// Runs while it shows something. The camera view clearing alone (its bodycam destroyed) is handled
/// in the step, which then stops showing, so the pinboard and `showing` are cleaned up too.
CAPABILITIES(/obj/machinery/computer/security/telescreen/bodycamera)
	ref_one(nameof(showing), /atom)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(showing), wakes_on = list(nameof(showing)))
	owns_one(nameof(bradio), starts = /obj/item/radio)
	click_on(PROC_REF(click_input))

/obj/machinery/computer/security/telescreen/bodycamera/Initialize(mapload)

	var/static/icon/mask = icon('icons/obj/entertainment_monitor.dmi', "mask")

	rel_set(src, nameof(bpinboard), add_vis_overlay(icon, "pinboard", layer = 0.1, alpha = 255, add_appearance_flags = KEEP_TOGETHER, add_vis_flags = VIS_INHERIT_ID|VIS_INHERIT_PLANE, unique = TRUE))
	bpinboard.add_filter("screen cutter", 1, alpha_mask_filter(icon = mask))
	vis_contents += bpinboard

	. = ..()

	bradio.listening = TRUE
	bradio.broadcasting = FALSE
	bradio.set_frequency(BDCM_FREQ)
	bradio.canhear_range = world.view // Same as default sight range.
	power_change()


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

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/obj/machinery/computer/security/telescreen/bodycamera/proc/click_input(datum/act/input/A)
	if(!handle_click_with_actor(A.actor, A.params))
		return INPUT_FALLTHROUGH

/obj/machinery/computer/security/telescreen/bodycamera/proc/handle_click_with_actor(mob/user, params)
	var/list/modifiers = params2list(params)
	if(GLOB.input_router.click_is(modifiers, TYPE_TABLE_GET(GLOB.input_router, alternate_table), INPUT_ACTION_ALTERNATE))
		if(isliving(user) && Adjacent(user) && !user.incapacitated())
			bodycam_toggle()
			act_message(user, src, MSG_SELF("You toggle %T% [enabled ? "on" : "off"]."), MSG_OTHERS("<b>%U%</b> toggles %T% [enabled ? "on" : "off"]."), runemessage = "click")
	//Changing click to only come into play when shift or alt clicking. These things are ANNOYING.
			return TRUE
	if(GLOB.input_router.click_is(modifiers, TYPE_TABLE_GET(GLOB.input_router, shift_table), INPUT_ACTION_INSPECT))
		attack_hand(user)
		return TRUE
	return FALSE

/// Follows the camera while it shows one; otherwise it sleeps until it is shown one.
/obj/machinery/computer/security/telescreen/bodycamera/proc/work_step(datum/act/timer/A)
	var/atom/them = showing
	var/obj/item/clothing/accessory/bodycam/bo_cam = the_camera
	if(!bo_cam || get_turf(them) != get_turf(bo_cam))
		stop_showing()

/obj/machinery/computer/security/telescreen/bodycamera/proc/show_thing(atom/thing, obj/item/clothing/accessory/bodycam/other_thing)
	if(!enabled)
		return
	if(showing)
		stop_showing()
	if(power_lost())
		return
	if(!thing || !other_thing)
		return
	rel_set(src, nameof(the_camera), other_thing)
	var/tries = 10
	var/atom/recursive_loc = thing
	while(--tries)
		recursive_loc = recursive_loc.loc
		if(!istype(recursive_loc, /atom/movable))
			break
	thing = recursive_loc // should get the topmost atom, which *should* be a mob, or a locker, or something that isnt just ~clothes~
	rel_set(src, nameof(showing), thing)
	if(bpinboard)
		bpinboard.vis_contents = list(thing)

/obj/machinery/computer/security/telescreen/bodycamera/proc/stop_showing()
	// Reverse of the above
	if(bpinboard)
		bpinboard.vis_contents = null
	rel_clear(src, nameof(showing))
	rel_clear(src, nameof(the_camera))

/obj/machinery/computer/security/telescreen/bodycamera/proc/maybe_stop_showing(atom/thing)
	if(showing == thing)
		stop_showing()

/obj/machinery/computer/security/telescreen/bodycamera/power_change()
	. = ..()
	if(power_lost())
		bradio?.on = FALSE
		stop_showing()
	else if(enabled)
		bradio?.on = TRUE

/obj/machinery/computer/security/telescreen/bodycamera/draw(datum/look/look)
	..()
	look.overlay("glass")
