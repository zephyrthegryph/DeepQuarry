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

	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

CAPABILITIES(/obj/item/camerabug)
	owns_one(nameof(camera), /obj/machinery/camera/bug, starts = nameof(camtype))
	op("crush", in_hand(), stance(I_HURT), label("Crush camera pod"), then(PROC_REF(camerabug_crushed)))
	extend(/datum/act/hit/projectile, instead(then(PROC_REF(camerabug_shot))))
	op("pair", item(/obj/item/bug_monitor), label("Pair"), then(PROC_REF(interaction_pair)))
	// wrenching it down on the floor (any stance but harm; a harmful swing falls through to the hit)
	op("secure", tool(TOOL_WRENCH), wait(0), stance(I_HELP, I_DISARM, I_GRAB), label("Secure or unsecure"), needs(req(PROC_REF(lies_on_turf), because = MSG(camerabug/not_on_floor))), then(PROC_REF(interaction_wrench)))
	// the old attackby: a strong hit breaks the lens (and the hit goes on)
	op("hit", item(/obj/item), then(PROC_REF(interaction_item)))
	// the old object verb
	op("reset", menu(), label("Reset camera bug"), needs(carried()), then(PROC_REF(camerabug_reset)))

MSG_DEF_SELF(camerabug/not_on_floor, "It must be on the floor.")

/obj/item/camerabug/proc/camerabug_reset(datum/act/op/A)
	camerabug_reset_effect(A.actor)
	return OP_OK


/obj/item/camerabug/proc/camerabug_crushed(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, MSG_SELF(span_notice("You crush %T% under your foot, breaking it.")), \
		MSG_OTHERS(span_notice("%U% crushes %T% under %THEIR% foot, breaking it!")))
	replace_with(src, brokentype)
	return OP_OK

/obj/item/camerabug/proc/camerabug_reset_effect(mob/user)
	if(linkedmonitor())
		linkedmonitor().unpair(src)
	rel_clear(src, nameof(linkedmonitor))
	rel_clear(src, nameof(camera))
	rel_set(src, nameof(camera), new camtype(src))
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

	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

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

/obj/item/camerabug/draw(datum/look/look)
	..()

	if(anchored)	// Standard versions are relatively obvious if not hidden in a container. Anchoring them is advised, to disguise them.
		look.alpha = 50
	else
		look.alpha = 255

/obj/item/camerabug/proc/interaction_pair(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/bug_monitor/SM = A.held
	if(!linkedmonitor())
		to_chat(user, span_notice("\The [src] has been paired with \the [SM]."))
		SM.pair(src)
		rel_set(src, nameof(linkedmonitor), SM)
	else if (linkedmonitor() == SM)
		to_chat(user, span_notice("\The [src] has been unpaired from \the [SM]."))
		linkedmonitor().unpair(src)
		rel_clear(src, nameof(linkedmonitor))
	else
		to_chat(user, "Error: The device is linked to another monitor.")
	return OP_OK

/// Old attackby: any other item breaks the lens on a strong hit, but always fell through to ..().
/obj/item/camerabug/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(W.force >= 5)
		visible_message("\The [src] lens shatters!")
		new brokentype(get_turf(src))
		if(linkedmonitor())
			linkedmonitor().unpair(src)
		rel_clear(src, nameof(linkedmonitor))
		consume(src, user)
	return OP_DECLINE

/// Wrenching it down (any stance but harm; a harmful swing falls through to the hit).
/obj/item/camerabug/proc/interaction_wrench(datum/act/op/A)
	set_anchored(!anchored)
	to_chat(A.actor, span_notice("You [anchored ? "" : "un"]secure \the [src]."))
	return OP_OK

/// Requirement: it lies on the floor.
/obj/item/camerabug/proc/lies_on_turf(datum/act/op/A)
	return lies_on_floor(src)

/// Is `thing` lying loose on a turf (not carried or inside something)?
/proc/lies_on_floor(atom/movable/thing)
	READS_FROM() // where it lies is asked when the tool touches it
	return isturf(thing.loc)

/// A round shatters the bug.
/obj/item/camerabug/proc/camerabug_shot(datum/act/hit/projectile/A)
	visible_message("The [src] lens shatters!")
	if(linkedmonitor())
		linkedmonitor().unpair(src)
	rel_clear(src, nameof(linkedmonitor))
	replace_with(src, brokentype)
	return OP_OK

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

	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

/*
/obj/item/bug_monitor/Initialize(mapload)
	radio = new(src)
*/
CAPABILITIES(/obj/item/bug_monitor)
	op("item", item(/obj/item/camerabug), then(PROC_REF(interaction_item)))
	op("view", in_hand(), label("View paired cameras"), then(PROC_REF(bug_monitor_controls_opened)))

/obj/item/bug_monitor/proc/bug_monitor_controls_opened(datum/act/op/A)
	view_cameras(A.actor)
	return OP_OK

/obj/item/bug_monitor/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	W.attackby(src, user)
	return TRUE

/obj/item/bug_monitor/proc/unpair(obj/item/camerabug/SB)
	rel_remove(src, nameof(paired), SB.camera)

/obj/item/bug_monitor/proc/pair(obj/item/camerabug/SB)
	if(SB.camera)
		rel_add(src, nameof(paired), SB.camera)

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
		rel_set(src, nameof(selected_camera), cameras[1])
	else
		if(in_use) // Don't allow spamming tgui menus
			return
		in_use = TRUE
		if(!user || QDELETED(user) || !open_request(src, /datum/prompt/choice/bug_camera, PROC_REF(camera_chosen), answerer = user, choices = cameras))
			in_use = FALSE
		return
	view_camera(user)

/// Picking a paired camera. Re-checked on the answer: the monitor is still carried. Any ending frees the monitor.
/datum/prompt/choice/bug_camera
	title = "Camera Choice"
	question = "Select camera to view."
	ask_flags = ASK_CARRIED | ASK_CAPABLE
	timeout = 0

/obj/item/bug_monitor/proc/camera_chosen(datum/act/request/A)
	in_use = FALSE
	if(!A.answer)
		return
	rel_set(src, nameof(selected_camera), A.answer.value)
	view_camera(A.request.answerer)

/obj/item/bug_monitor/proc/view_camera(mob/user)
	if(loc != user) // Nice try smartass, must be in your hand and not in a box in your inventory
		return
	var/turf/T = get_turf(selected_camera())
	if(!T || !is_on_same_plane_or_station(T.z, user.z) || !selected_camera().can_use())
		to_chat(user, span_notice("Link to [selected_camera()] has been lost."))
		rel_remove(src, nameof(paired), selected_camera)
		rel_clear(src, nameof(selected_camera))
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

/// Relation view: linkedmonitor (reads null once it is gone).
/obj/item/camerabug/proc/linkedmonitor() as /obj/item/bug_monitor
	return linkedmonitor

/// Relation view: selected camera (reads null once it is gone).
/obj/item/bug_monitor/proc/selected_camera() as /obj/machinery/camera/bug
	return selected_camera
