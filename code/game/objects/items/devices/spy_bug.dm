/obj/item/camerabug
	name = "mobile camera pod"
	desc = "A camera pod used by tactical operators. Must be linked to a camera scanner unit."
	icon = 'icons/obj/grenade.dmi'
	icon_state = "camgrenade"
	item_state = "empgrenade"
	w_class = ITEMSIZE_SMALL
	force = 0
	throwforce = 5.0
	throw_range = 15
	throw_speed = 3
	var/obj/item/bug_monitor/linkedmonitor
	var/brokentype = /obj/item/brokenbug

	var/obj/machinery/camera/bug/camera
	var/camtype = /obj/machinery/camera/bug

	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'


/obj/item/camerabug/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("You crush the [src] under your foot, breaking it."))
	visible_message(span_notice("[user.name] crushes the [src] under their foot, breaking it!"))
	replace_with(src, brokentype)

/obj/item/camerabug/proc/camerabug_reset_effect(mob/user, obj/item/held, datum/interaction/interaction)
	if(linkedmonitor())
		linkedmonitor().unpair(src)
	rel_clear(src, "linkedmonitor")
	qdel(camera)
	own_set(src, "camera", new camtype(src))
	to_chat(user, span_notice("You turn the [src] off and on again, delinking it from any monitors."))

/obj/item/brokenbug
	name = "broken mobile camera pod"
	desc = "A camera pod formerly used by tactical operators. The lens is smashed, and the circuits are damaged beyond repair."
	icon = 'icons/obj/grenade.dmi'
	icon_state = "camgrenadebroken"
	item_state = "empgrenade"
	force = 5.0
	w_class = ITEMSIZE_SMALL
	throwforce = 5.0
	throw_range = 15
	throw_speed = 3

	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

/obj/item/brokenbug/spy
	name = "broken bug"
	desc = ""	//Even when it's broken it's inconspicuous
	icon = 'icons/obj/weapons.dmi'
	icon_state = "eshield"
	item_state = "nothing"
	layer = TURF_LAYER+0.2
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	force = 0
	throwforce = 5.0
	throw_range = 15
	throw_speed = 3

/obj/item/camerabug/spy
	name = "bug"
	desc = ""	//Nothing to see here
	icon = 'icons/obj/weapons.dmi'
	icon_state = "eshield"
	item_state = "nothing"
	layer = TURF_LAYER+0.2
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	camtype = /obj/machinery/camera/bug/spy

/obj/item/camerabug/examine(mob/user)
	. = ..()
	if(get_dist(user, src) == 0)
		. += "It has a tiny camera inside. Needs to be both configured and brought in contact with monitor device to be fully functional."

/obj/item/camerabug/update_icon()
	..()

	if(anchored)	// Standard versions are relatively obvious if not hidden in a container. Anchoring them is advised, to disguise them.
		alpha = 50
	else
		alpha = 255

DECLARE_INTERACTIONS(/obj/item/camerabug, \
	INTERACT_INSERT(/obj/item/bug_monitor, PROC_REF(interaction_pair), "Pair"), \
	INTERACT_ITEM_AS(I_HELP, "Secure or unsecure", PROC_REF(interaction_wrench), REQ_TOOL(TOOL_WRENCH), REQ_ON(PRED_TARGET, /obj/item/camerabug/proc/lies_on_turf, "it must be on the floor")), \
	INTERACT_ITEM_AS(I_DISARM, "Secure or unsecure", PROC_REF(interaction_wrench), REQ_TOOL(TOOL_WRENCH), REQ_ON(PRED_TARGET, /obj/item/camerabug/proc/lies_on_turf, "it must be on the floor")), \
	INTERACT_ITEM_AS(I_GRAB, "Secure or unsecure", PROC_REF(interaction_wrench), REQ_TOOL(TOOL_WRENCH), REQ_ON(PRED_TARGET, /obj/item/camerabug/proc/lies_on_turf, "it must be on the floor")), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_USE_AS(I_HURT, "Crush", PROC_REF(interaction_self)), \
)

/obj/item/camerabug/proc/interaction_pair(mob/user, obj/item/bug_monitor/SM, datum/interaction/interaction)
	if(!linkedmonitor())
		to_chat(user, span_notice("\The [src] has been paired with \the [SM]."))
		SM.pair(src)
		rel_set(src, "linkedmonitor", SM)
	else if (linkedmonitor() == SM)
		to_chat(user, span_notice("\The [src] has been unpaired from \the [SM]."))
		linkedmonitor().unpair(src)
		rel_clear(src, "linkedmonitor")
	else
		to_chat(user, "Error: The device is linked to another monitor.")
	return TRUE

/// Old attackby: any other item breaks the lens on a strong hit, but always fell through to ..().
/obj/item/camerabug/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(W.force >= 5)
		visible_message("\The [src] lens shatters!")
		new brokentype(get_turf(src))
		if(linkedmonitor())
			linkedmonitor().unpair(src)
		rel_clear(src, "linkedmonitor")
		consume(src, user)
	return FALSE

/// Wrenching it down (any stance but harm; a harmful swing falls through to the hit).
/obj/item/camerabug/proc/interaction_wrench(mob/user, obj/item/tool, datum/interaction/interaction)
	anchored = !anchored
	to_chat(user, span_notice("You [anchored ? "" : "un"]secure \the [src]."))
	update_icon()
	return TRUE

/obj/item/camerabug/proc/lies_on_turf(mob/actor, atom/target, obj/item/held)
	return isturf(loc)

/obj/item/camerabug/bullet_act()
	visible_message("The [src] lens shatters!")
	if(linkedmonitor())
		linkedmonitor().unpair(src)
	rel_clear(src, "linkedmonitor")
	replace_with(src, brokentype)

// its monitor unpairs it.
/obj/item/camerabug/on_destroy(force)
	if(linkedmonitor())
		linkedmonitor().unpair(src)
	..()

/obj/item/bug_monitor
	name = "mobile camera pod monitor"
	desc = "A portable camera console designed to work with mobile camera pods."
	icon = 'icons/obj/device.dmi'
	icon_state = "forensic0"
	item_state = "electronic"
	w_class  = ITEMSIZE_SMALL

	/// Relation view: the camera being watched.
	var/obj/machinery/camera/bug/selected_camera
	/// Relation list view: the paired bug cameras (deleted ones leave it).
	var/list/obj/machinery/camera/bug/paired

	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

/*
/obj/item/bug_monitor/Initialize(mapload)
	radio = new(src)
*/
DECLARE_INTERACTIONS(/obj/item/bug_monitor, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_INSERT(/obj/item/camerabug, PROC_REF(interaction_item), null), \
)

/obj/item/bug_monitor/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	view_cameras(user)

/obj/item/bug_monitor/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	W.attackby(src, user)
	return TRUE

/obj/item/bug_monitor/proc/unpair(obj/item/camerabug/SB)
	rel_remove(src, "paired", SB.camera)

/obj/item/bug_monitor/proc/pair(obj/item/camerabug/SB)
	if(SB.camera)
		rel_add(src, "paired", SB.camera)

/// The paired cameras still alive (a deleted one leaves the view).
/obj/item/bug_monitor/proc/paired_cameras()
	. = list()
	for(var/obj/machinery/camera/bug/cam as anything in paired)
		. += cam

/obj/item/bug_monitor/proc/view_cameras(mob/user)
	if(in_use)
		return

	var/list/cameras = paired_cameras()
	if(cameras.len == 1 && user.is_remote_viewing())
		user.reset_perspective()
		return
	if(!can_use_cam(user))
		return

	if(cameras.len == 1)
		rel_set(src, "selected_camera", cameras[1])
	else
		if(in_use) // Don't allow spamming tgui menus
			return
		in_use = TRUE
		if(!om_ask(user, /datum/om/prompt/choice/bug_camera, PROC_REF(camera_chosen), choices = cameras, monitor = src))
			in_use = FALSE
		return
	view_camera(user)

/// Picking a paired camera. Re-checked on the answer: the monitor is still carried. Any ending frees the monitor.
/datum/om/prompt/choice/bug_camera
	title = "Camera Choice"
	message = "Select camera to view."
	ask_flags = ASK_CARRIED | ASK_CAPABLE
	var/obj/item/bug_monitor/monitor

/datum/om/prompt/choice/bug_camera/cancelled()
	if(monitor)
		monitor.in_use = FALSE
	return ..()

/datum/om/prompt/choice/bug_camera/refused(reason)
	if(monitor)
		monitor.in_use = FALSE
	return ..()

/obj/item/bug_monitor/proc/camera_chosen(datum/om/prompt/choice/bug_camera/ask)
	in_use = FALSE
	rel_set(src, "selected_camera", ask.choice)
	view_camera(ask.answerer)

/obj/item/bug_monitor/proc/view_camera(mob/user)
	if(loc != user) // Nice try smartass, must be in your hand and not in a box in your inventory
		return
	var/turf/T = get_turf(selected_camera())
	if(!T || !is_on_same_plane_or_station(T.z, user.z) || !selected_camera().can_use())
		to_chat(user, span_notice("Link to [selected_camera()] has been lost."))
		rel_remove(src, "paired", selected_camera)
		rel_clear(src, "selected_camera")
		return
	user.begin_remote_view(/datum/remote_view/item_zoom, selected_camera(), null, /datum/remote_view_config/camera_standard, src, 0, TRUE)

/obj/item/bug_monitor/proc/can_use_cam(mob/user)
	if(!length(paired_cameras()))
		to_chat(user, span_warning("No paired cameras detected!"))
		to_chat(user, span_warning("Bring a camera in contact with this device to pair the camera."))
		return FALSE
	return TRUE

/obj/item/bug_monitor/spy
	name = "\improper PDA"
	desc = "A portable microcomputer by Thinktronic Systems, LTD. Functionality determined by a preprogrammed ROM cartridge."
	icon = 'icons/obj/pda.dmi'
	icon_state = "pda"
	item_state = "electronic"

/obj/item/bug_monitor/spy/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += "The time '12:00' is blinking in the corner of the screen and \the [src] looks very cheaply made."

/obj/machinery/camera/bug
	network = list(NETWORK_SECURITY)

/obj/machinery/camera/bug/Initialize(mapload)
	. = ..()
	name = "Camera #[rand(1000,9999)]"
	c_tag = name

/obj/machinery/camera/bug/spy
	// These cheap toys are accessible from the mercenary camera console as well - only the antag ones though!
	network = list(NETWORK_MERCENARY)

/obj/machinery/camera/bug/spy/Initialize(mapload)
	. = ..()
	name = "DV-136ZB #[rand(1000,9999)]"
	c_tag = name

DECLARE_DEFAULT_CHILD(/obj/item/camerabug, "camera", "camtype")

/// Relation view: linkedmonitor (reads null once it is gone).
/obj/item/camerabug/proc/linkedmonitor() as /obj/item/bug_monitor
	return linkedmonitor

/// Relation view: selected camera (reads null once it is gone).
/obj/item/bug_monitor/proc/selected_camera() as /obj/machinery/camera/bug
	return selected_camera
/// Old object verbs.
EXTEND_INTERACTIONS(/obj/item/camerabug, \
	INTERACT_VERB("Reset camera bug", PROC_REF(camerabug_reset_effect), REQ_IN_INVENTORY), \
)
