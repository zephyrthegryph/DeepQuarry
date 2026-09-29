/*****************Marker Beacons**************************/
GLOBAL_LIST_INIT(marker_beacon_colors, list(
	"Burgundy" = LIGHT_COLOR_FLARE,
	"Bronze" = LIGHT_COLOR_ORANGE,
	"Yellow" = LIGHT_COLOR_YELLOW,
	"Lime" = LIGHT_COLOR_SLIME_LAMP,
	"Olive" = LIGHT_COLOR_GREEN,
	"Jade" = LIGHT_COLOR_BLUEGREEN,
	"Teal" = LIGHT_COLOR_LIGHT_CYAN,
	"Cerulean" = LIGHT_COLOR_BLUE,
	"Indigo" = LIGHT_COLOR_DARK_BLUE,
	"Purple" = LIGHT_COLOR_PURPLE,
	"Violet" = LIGHT_COLOR_LAVENDER,
	"Fuchsia" = LIGHT_COLOR_PINK
))

/obj/item/stack/marker_beacon
	name = "marker beacons"
	singular_name = "marker beacon"
	desc = "Prismatic path illumination devices. Used by explorers and miners to mark paths and warn of danger."
	icon = 'icons/obj/lighting.dmi'
	icon_state = "markerrandom"
	max_amount = 100
	no_variants = TRUE
	w_class = ITEMSIZE_SMALL
	var/icon_base = "marker"
	var/picked_color = "random"
	custom_handling = TRUE

/obj/item/stack/marker_beacon/ten
	amount = 10

/obj/item/stack/marker_beacon/thirty
	amount = 30

/obj/item/stack/marker_beacon/hundred
	amount = 100

/obj/item/stack/marker_beacon/Initialize(mapload)
	. = ..()
	update_icon()

/obj/item/stack/marker_beacon/examine(mob/user)
	. = ..()
	. += span_notice("Use in-hand to place a [singular_name].")
	. += span_notice("Alt-click to select a color. Current color is [picked_color].")

/obj/item/stack/marker_beacon/update_icon()
	icon_state = "[icon_base][lowertext(picked_color)]"

/// Requirement for placing: open floor with no beacon on it already.
/obj/item/stack/marker_beacon/proc/can_place(mob/user, atom/target, obj/item/held)
	if(!isturf(user.loc))
		return "you need more space to place a [singular_name] here"
	if(locate_within(user.loc, /obj/structure/marker_beacon))
		return "there is already a [singular_name] here"
	return TRUE

/// Requirement for picking a colour (shared by the stack and the placed beacon).
/proc/dq_marker_beacon_can_recolor(mob/living/user, atom/target, obj/item/held)
	if(user.incapacitated() || !istype(user))
		return "you can't do that right now"
	return TRUE

/// Old attack_self: place a beacon.
/obj/item/stack/marker_beacon/proc/marker_beacon_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(use(1))
		to_chat(user, span_notice("You activate and anchor [amount ? "a":"the"] [singular_name] in place."))
		play_sfx(src, SFX_MACHINES_CLICK)
		var/obj/structure/marker_beacon/M = new(user.loc, picked_color)
		transfer_fingerprints_to(M)

EXTEND_INTERACTIONS(/obj/item/stack/marker_beacon, \
	INTERACT_USE("Place", PROC_REF(marker_beacon_self), REQ_TARGET_STATE(/obj/item/stack/marker_beacon/proc/can_place)), \
	INTERACT_ALT(null, PROC_REF(interaction_alt), REQ_PROC(/proc/dq_marker_beacon_can_recolor, "you can't do that right now")), \
)

/// Old click_alt.
/obj/item/stack/marker_beacon/proc/interaction_alt(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(!in_range(src, user))
		return TRUE

	var/options = GLOB.marker_beacon_colors.Copy()
	options += list("Random" = FALSE) //not a true color, will pick a random color
	om_ask(user, /datum/om/prompt/choice, PROC_REF(color_chosen), choices = options, title = "Beacon Color", message = "Choose a color.", ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE)
	return TRUE

/obj/item/stack/marker_beacon/proc/color_chosen(datum/om/prompt/choice/ask)
	if(ask.choice)
		picked_color = ask.choice
		update_icon()

/obj/structure/marker_beacon
	name = "marker beacon"
	desc = "A prismatic path illumination device. It is anchored in place and glowing steadily."
	icon = 'icons/obj/lighting.dmi'
	icon_state = "markerrandom"
	anchored = TRUE
	light_range = 2
	light_power = 0.8
	var/icon_base = "marker"
	var/remove_speed = 15
	var/picked_color
	var/perma = FALSE
	var/mapped_in_color

/obj/structure/marker_beacon/Initialize(mapload, set_color)
	. = ..()
	if(set_color)
		picked_color = set_color
	else if(mapped_in_color)
		picked_color = mapped_in_color
	update_icon()

/obj/structure/marker_beacon/examine(mob/user)
	. = ..()
	if(!perma)
		. += span_notice("Alt-click to select a color. Current color is [picked_color].")

/obj/structure/marker_beacon/update_icon()
	if(!picked_color || !GLOB.marker_beacon_colors[picked_color])
		picked_color = pick(GLOB.marker_beacon_colors)
	icon_state = "[icon_base][lowertext(picked_color)]-on"
	set_light(light_range, light_power, GLOB.marker_beacon_colors[picked_color])

DECLARE_INTERACTIONS(/obj/structure/marker_beacon, \
	INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_ALT(null, PROC_REF(interaction_alt), REQ_TARGET_STATE(/obj/structure/marker_beacon/proc/can_recolor)), \
)

/// Old attack_hand.
/obj/structure/marker_beacon/proc/interaction_hand(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(perma)
		return TRUE
	to_chat(user, span_notice("You start picking [src] up..."))
	om_task_timed(user, remove_speed, target = src, receiver = src, on_done = PROC_REF(attack_hand_timed_done), done_args = list(user))
	return TRUE

/obj/structure/marker_beacon/proc/attack_hand_timed_done(mob/living/user)
	var/obj/item/stack/marker_beacon/M = new(loc)
	M.picked_color = picked_color
	M.update_icon()
	transfer_fingerprints_to(M)
	if(user.put_in_hands(M, TRUE)) //delete the beacon if it fails
		play_sfx(src, SFX_ITEMS_DECONSTRUCT)
		qdel(src) //otherwise delete us

/// Old attackby.
/obj/structure/marker_beacon/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(perma)
		return INTERACTION_HANDLED_PASS
	if(istype(I, /obj/item/stack/marker_beacon))
		var/obj/item/stack/marker_beacon/M = I
		to_chat(user, span_notice("You start picking [src] up..."))
		om_task_timed(user, remove_speed, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done), done_args = list(M))
	else
		return FALSE
	return INTERACTION_HANDLED_PASS

/obj/structure/marker_beacon/proc/attackby_timed_done(obj/item/stack/marker_beacon/M)
	if(!(M.get_amount() + 1 <= M.max_amount))
		return
	M.add(1)
	play_sfx(src, SFX_ITEMS_DECONSTRUCT)
	qdel(src)

/// Requirement for picking a colour (a permanent beacon ignores it silently).
/obj/structure/marker_beacon/proc/can_recolor(mob/living/user, atom/target, obj/item/held)
	if(perma)
		return TRUE
	return dq_marker_beacon_can_recolor(user, target, held)

/// Old click_alt.
/obj/structure/marker_beacon/proc/interaction_alt(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(perma)
		return TRUE
	if(!in_range(src, user))
		return TRUE

	var/options = GLOB.marker_beacon_colors.Copy()
	options += list("Random" = FALSE) //not a true color, will pick a random color
	om_ask(user, /datum/om/prompt/choice, PROC_REF(color_chosen), choices = options, title = "Beacon Color", message = "Choose a color.", ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE)
	return TRUE

/obj/structure/marker_beacon/proc/color_chosen(datum/om/prompt/choice/ask)
	if(ask.choice)
		picked_color = ask.choice
		update_icon()
