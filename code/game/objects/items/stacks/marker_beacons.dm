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

TRACKED(/obj/item/stack/marker_beacon, picked_color)

CAPABILITIES(/obj/item/stack/marker_beacon)
	without("ui_open")
	op("place", in_hand(), label("Place"), needs(req(PROC_REF(can_place), because = PROC_REF(place_refusal))), then(PROC_REF(marker_beacon_self)))
	op("recolor", hand(), gesture(GESTURE_ALT), label("Color"), then(PROC_REF(recolor_asked)))

MSG_DEF_SELF(marker_beacon/no_space, "You need more space to place a marker beacon here.")
MSG_DEF_SELF(marker_beacon/already_there, "There is already a marker beacon here.")

/obj/item/stack/marker_beacon/ten
	amount = 10

/obj/item/stack/marker_beacon/thirty
	amount = 30

/obj/item/stack/marker_beacon/hundred
	amount = 100

/obj/item/stack/marker_beacon/examine(mob/user)
	. = ..()
	. += span_notice("Use in-hand to place a [singular_name].")
	. += span_notice("Alt-click to select a color. Current color is [picked_color].")

/obj/item/stack/marker_beacon/draw(datum/look/look)
	..()
	look.state(look_state())

/// The pile shows its colour.
/obj/item/stack/marker_beacon/look_state()
	return "[icon_base][lowertext(picked_color)]"

/// Placing needs open floor with no beacon on it already.
/obj/item/stack/marker_beacon/proc/can_place(datum/act/op/A)
	var/mob/user = A.actor
	// ALLOW(reads): where the user stands is read when the beacon is placed, never from a cached menu
	if(!isturf(user.loc))
		return FALSE
	// ALLOW(reads): the same read of where the user stands, for the beacons already on that tile
	return !locate_within(user.loc, /obj/structure/marker_beacon)

/// Why it cannot be placed: no floor to stand on, or a beacon already there.
/obj/item/stack/marker_beacon/proc/place_refusal(datum/act/op/A)
	var/mob/user = A.actor
	if(!isturf(user.loc))
		return /datum/msg/marker_beacon/no_space
	return /datum/msg/marker_beacon/already_there

/// Using the stack in the hand places a beacon.
/obj/item/stack/marker_beacon/proc/marker_beacon_self(datum/act/op/A)
	var/mob/user = A.actor
	if(use(1))
		to_chat(user, span_notice("You activate and anchor [amount ? "a":"the"] [singular_name] in place."))
		play_sfx(src, SFX_MACHINES_CLICK)
		var/obj/structure/marker_beacon/M = new(user.loc, picked_color)
		transfer_fingerprints_to(M)
	return OP_OK

/// The colours a beacon can take, and "Random", which is not a true colour and picks one.
/proc/marker_beacon_color_choices()
	var/list/options = list()
	for(var/color_name in GLOB.marker_beacon_colors)
		options += color_name
	options += "Random"
	return options

/// The alt-click: ask which colour the beacons should be.
/obj/item/stack/marker_beacon/proc/recolor_asked(datum/act/op/A)
	var/mob/user = A.actor
	if(!in_range(src, user))
		return OP_OK
	open_request(src, /datum/prompt/choice, PROC_REF(color_chosen), answerer = user, title = "Beacon Color", question = "Choose a color.", choices = marker_beacon_color_choices(), ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)
	return OP_OK

/obj/item/stack/marker_beacon/proc/color_chosen(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	set_picked_color(A.answer.value)

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

TRACKED(/obj/structure/marker_beacon, picked_color)

CAPABILITIES(/obj/structure/marker_beacon)
	op("pick_up", hand(), ungated(), then(PROC_REF(picked_up_by_hand)))
	op("pick_up_into", item(/obj/item/stack/marker_beacon), passes(), then(PROC_REF(picked_up_into_stack)))
	op("recolor", hand(), gesture(GESTURE_ALT), label("Color"), then(PROC_REF(recolor_asked)))
	param(nameof(color_at_make), pos = 1, apply = PROC_REF(light_beacon))

/// The colour a beacon is set down with (its constructor param).
/obj/structure/marker_beacon/var/color_at_make

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). A beacon set down takes its colour, or the one it was mapped with.
/obj/structure/marker_beacon/proc/light_beacon(set_color)
	if(set_color)
		set_picked_color(set_color)
	else if(mapped_in_color)
		set_picked_color(mapped_in_color)

/// A beacon with no colour (or one the table does not know) picks one when it enters the world.
/obj/structure/marker_beacon/on_materialize()
	. = ..()
	if(!picked_color || !GLOB.marker_beacon_colors[picked_color])
		set_picked_color(pick(GLOB.marker_beacon_colors))

/obj/structure/marker_beacon/examine(mob/user)
	. = ..()
	if(!perma)
		. += span_notice("Alt-click to select a color. Current color is [picked_color].")

/obj/structure/marker_beacon/draw(datum/look/look)
	..()
	look.state("[icon_base][lowertext(picked_color)]-on")
	look.light(light_range, light_power, GLOB.marker_beacon_colors[picked_color])

/// An empty hand takes the beacon up after a wait (a permanent one stays).
/obj/structure/marker_beacon/proc/picked_up_by_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	if(perma)
		return OP_OK
	to_chat(user, span_notice("You start picking [src] up..."))
	om_task_timed(user, remove_speed, target = src, receiver = src, on_done = PROC_REF(attack_hand_timed_done), done_args = list(user))
	return OP_OK

/obj/structure/marker_beacon/proc/attack_hand_timed_done(mob/living/user)
	var/obj/item/stack/marker_beacon/M = new(loc)
	M.set_picked_color(picked_color)
	transfer_fingerprints_to(M)
	if(user.put_in_hands(M))
		play_sfx(src, SFX_ITEMS_DECONSTRUCT)
		replace_with(src, M)
	else
		consume(M, user)

/// A beacon stack held against a placed beacon takes it back into the stack after a wait (a permanent one stays).
/obj/structure/marker_beacon/proc/picked_up_into_stack(datum/act/op/A)
	var/mob/user = A.actor
	if(perma)
		return OP_OK
	var/obj/item/stack/marker_beacon/M = A.held
	to_chat(user, span_notice("You start picking [src] up..."))
	om_task_timed(user, remove_speed, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done), done_args = list(M))
	return OP_OK

/obj/structure/marker_beacon/proc/attackby_timed_done(obj/item/stack/marker_beacon/M)
	if(!(M.get_amount() + 1 <= M.max_amount))
		return
	M.add(1)
	play_sfx(src, SFX_ITEMS_DECONSTRUCT)
	consume(src)

/// The alt-click: ask which colour the beacon should be (a permanent one ignores it silently).
/obj/structure/marker_beacon/proc/recolor_asked(datum/act/op/A)
	var/mob/living/user = A.actor
	if(perma)
		return OP_OK
	if(!in_range(src, user))
		return OP_OK
	open_request(src, /datum/prompt/choice, PROC_REF(color_chosen), answerer = user, title = "Beacon Color", question = "Choose a color.", choices = marker_beacon_color_choices(), ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)
	return OP_OK

/obj/structure/marker_beacon/proc/color_chosen(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/chosen = A.answer.value
	if(!GLOB.marker_beacon_colors[chosen]) // "Random" is not a true colour: it picks one
		chosen = pick(GLOB.marker_beacon_colors)
	set_picked_color(chosen)
