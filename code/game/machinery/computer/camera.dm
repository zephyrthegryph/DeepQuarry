//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

/obj/machinery/computer/security
	name = "security camera monitor"
	desc = "Used to access the various cameras on the station."

	icon_keyboard = "security_key"
	icon_screen = "cameras"
	light_color = "#a91515"
	circuit = /obj/item/circuitboard/security

	var/mapping = 0//For the overview file, interesting bit of code.
	var/list/network = list() // ALLOW(instance_list): d: camera console network filter; many call sites

	var/datum/tgui_module/camera/camera
	var/camera_datum_type = /datum/tgui_module/camera

CAPABILITIES(/obj/machinery/computer/security)
	owns_one(nameof(camera), /datum/tgui_module/camera)
	op("station_map", menu(), label(".map"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_station_map)))
	op("open_ui_impl", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_open_ui_impl)))
	op("security_robot_use", remote(), when(req(/mob/living/silicon/robot, of = ON_ACTOR)), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(security_robot_use)))

// ALLOW(init/INSTANCE_STATE): its camera view is built for the networks the map gave it
/obj/machinery/computer/security/Initialize(mapload)
	. = ..()
	if(!LAZYLEN(network))
		network = get_default_networks()
	rel_set(src, nameof(camera), new camera_datum_type(src, network))

/obj/machinery/computer/security/proc/get_default_networks()
	. = using_map.station_networks.Copy()

/obj/machinery/computer/security/ui_redirect(mob/user)
	return camera

/obj/machinery/computer/security/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(!operable())
		return OP_OK
	tgui_interact(user)
	return OP_OK

/// Old attack_robot: a cyborg that isn't an AI shell uses it by hand; a shell interfaces as the AI.
/obj/machinery/computer/security/proc/security_robot_use(datum/act/op/A)
	var/mob/living/silicon/robot/R = A.actor // the op's when() admits cyborgs only
	if(R.shell)
		return OP_DECLINE
	attack_hand(R)
	return OP_OK

/obj/machinery/computer/security/proc/set_network(list/new_network)
	network = new_network
	camera.network = network
	camera.access_based = FALSE

//Camera control: arrow keys.
/obj/machinery/computer/security/telescreen
	name = "Telescreen"
	desc = "Used for watching an empty arena."
	icon_state = "wallframe"
	layer = ABOVE_WINDOW_LAYER
	icon_keyboard = null
	icon_screen = null
	light_range_on = 0
	network = list(NETWORK_THUNDER)
	density = FALSE
	circuit = null
	flags = WALL_ITEM

/obj/machinery/computer/security/telescreen/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/obj/machinery/computer/security/telescreen/entertainment
	name = "entertainment monitor"
	desc = "Damn, why do they never have anything interesting on these things? (Alt-click to toggle the display)"
	icon = 'icons/obj/entertainment_monitor.dmi'
	icon_state = "screen"
	icon_screen = null
	light_color = "#FFEEDB"
	light_range_on = 2
	network = list(NETWORK_THUNDER)
	circuit = /obj/item/circuitboard/security/telescreen/entertainment
	camera_datum_type = /datum/tgui_module/camera/virtual

	var/obj/item/radio/radio = null
	var/obj/effect/overlay/vis/pinboard
	var/atom/showing

	var/enabled = TRUE // on or off

REGISTRY_MEMBERSHIP(/obj/machinery/computer/security/telescreen/entertainment, REGISTRY_ENTERTAINMENT_SCREENS)

CAPABILITIES(/obj/machinery/computer/security/telescreen/entertainment)
	owns_one(nameof(radio), starts = /obj/item/radio)
	click_on(PROC_REF(click_input))

/obj/machinery/computer/security/telescreen/entertainment/Initialize(mapload)

	var/static/icon/mask = icon('icons/obj/entertainment_monitor.dmi', "mask")

	add_overlay(MAT_GLASS)

	rel_set(src, nameof(pinboard), add_vis_overlay(icon, "pinboard", layer = 0.1, alpha = 255, add_appearance_flags = KEEP_TOGETHER, add_vis_flags = VIS_INHERIT_ID|VIS_INHERIT_PLANE, unique = TRUE))
	pinboard.add_filter("screen cutter", 1, alpha_mask_filter(icon = mask))
	/*
	pinboard = new()
	pinboard.icon = icon
	pinboard.icon_state = "pinboard"
	pinboard.layer = 0.1
	pinboard.vis_flags = VIS_UNDERLAY|VIS_INHERIT_ID|VIS_INHERIT_PLANE
	pinboard.appearance_flags = KEEP_TOGETHER
	pinboard.add_filter("screen cutter", 1, alpha_mask_filter(icon = mask))
	vis_contents += pinboard
	*/

	. = ..()

	radio.listening = TRUE
	radio.broadcasting = FALSE
	radio.set_frequency(ENT_FREQ)
	radio.canhear_range = world.view // Same as default sight range.
	power_change()

// stops showing its feed.
/obj/machinery/computer/security/telescreen/entertainment/on_destroy(force)
	if(showing)
		stop_showing()
	..()

/obj/machinery/computer/security/telescreen/entertainment/proc/toggle()
	enabled = !enabled
	if(!enabled)
		stop_showing()
		radio?.on = FALSE
	else if(operable())
		radio?.on = TRUE

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/obj/machinery/computer/security/telescreen/entertainment/proc/click_input(datum/act/input/A)
	if(!handle_click_with_actor(A.actor, A.params))
		return INPUT_FALLTHROUGH

/obj/machinery/computer/security/telescreen/entertainment/proc/handle_click_with_actor(mob/user, params)
	var/list/modifiers = params2list(params)
	if(GLOB.input_router.click_is(modifiers, TYPE_TABLE_GET(GLOB.input_router, alternate_table), INPUT_ACTION_ALTERNATE))
		if(isliving(user) && Adjacent(user) && !user.incapacitated())
			toggle()
			act_message(user, src, MSG_SELF(span_info("You toggle %T% [enabled ? "on" : "off"].")), MSG_OTHERS(span_infoplain(span_bold("%U%") + " toggles %T% [enabled ? "on" : "off"].")), runemessage = "click")
	// start - Changing click to only come into play when shift or alt clicking. These things are ANNOYING.
			return TRUE
	if(GLOB.input_router.click_is(modifiers, TYPE_TABLE_GET(GLOB.input_router, shift_table), INPUT_ACTION_INSPECT))
		attack_hand(user)
		return TRUE
	return FALSE
	// end

/obj/machinery/computer/security/telescreen/entertainment/proc/show_thing(atom/thing)
	if(!enabled)
		return
	if(showing)
		stop_showing()
	if(has_stat(NOPOWER))
		return
	rel_set(src, nameof(showing), thing)
	if(pinboard)
		pinboard.vis_contents = list(thing)

/obj/machinery/computer/security/telescreen/entertainment/proc/stop_showing()
	// Reverse of the above
	if(pinboard)
		pinboard.vis_contents = null
	rel_clear(src, nameof(showing))

/obj/machinery/computer/security/telescreen/entertainment/proc/maybe_stop_showing(atom/thing)
	if(showing == thing)
		stop_showing()

/obj/machinery/computer/security/telescreen/entertainment/power_change()
	. = ..()
	if(has_stat(NOPOWER))
		radio?.on = FALSE
		stop_showing()
	else if(enabled)
		radio?.on = TRUE

/obj/machinery/computer/security/wooden_tv
	name = "security camera monitor"
	desc = "An old TV hooked into the station's camera network."
	icon_state = "television"
	icon_keyboard = null
	icon_screen = "detective_tv"
	circuit = /obj/item/circuitboard/security/tv
	light_color = "#3848B3"
	light_power_on = 0.5

/obj/machinery/computer/security/mining
	name = "outpost camera monitor"
	desc = "Used to watch over mining operations."
	icon_keyboard = "mining_key"
	icon_screen = "mining"
	network = list(NETWORK_MINE)
	circuit = /obj/item/circuitboard/security/mining
	light_color = "#F9BBFC"

/obj/machinery/computer/security/engineering
	name = "engineering camera monitor"
	desc = "Used to monitor fires and breaches."
	icon_keyboard = "power_key"
	icon_screen = "engie_cams"
	circuit = /obj/item/circuitboard/security/engineering
	light_color = "#FAC54B"

/obj/machinery/computer/security/engineering/get_default_networks()
	. = GLOB.engineering_networks.Copy()

/obj/machinery/computer/security/nuclear
	name = "head mounted camera monitor"
	desc = "Used to access the built-in cameras in helmets."
	icon_state = "syndie"
	network = list(NETWORK_MERCENARY)
	circuit = null
	req_access = list(150)

/obj/machinery/computer/security/abductor
	name = "camera uplink"
	desc = "Used for hacking into camera networks"
	icon = 'icons/obj/abductor.dmi'
	icon_state = "camera"
	network = list(NETWORK_MERCENARY,
					NETWORK_CARGO,
					NETWORK_CIRCUITS,
					NETWORK_CIVILIAN,
					NETWORK_COMMAND,
					NETWORK_ENGINE,
					NETWORK_ENGINEERING,
					NETWORK_EXPLORATION,
					NETWORK_MEDICAL,
					NETWORK_MINE,
					NETWORK_OUTSIDE,
					NETWORK_RESEARCH,
					NETWORK_RESEARCH_OUTPOST,
					NETWORK_ROBOTS,
					NETWORK_SECURITY,
					NETWORK_TELECOM,
					NETWORK_TETHER,
					NETWORK_TALON_SHIP,
					NETWORK_THUNDER,
					NETWORK_COMMUNICATORS
					)

/obj/machinery/computer/security/xenobio
	name = "xenobiology camera monitor"
	desc = "Used to access the xenobiology cell cameras."
	icon_keyboard = "mining_key"
	icon_screen = "mining"
	network = list(NETWORK_XENOBIO)
	circuit = /obj/item/circuitboard/security/xenobio
	light_color = "#F9BBFC"
